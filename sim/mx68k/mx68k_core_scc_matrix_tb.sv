module mx68k_core_scc_matrix_tb;
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;
    import mx68k_m00_decode_table_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
    logic stopped;
    logic faulted;
    mx_exception_t terminal_exception;
    logic retire_valid;
    logic [31:0] retire_pc;
    logic [7:0] retire_instruction_id;
    logic [31:0] debug_pc;
    logic [15:0] debug_sr;
    logic [31:0] debug_usp;
    logic [31:0] debug_ssp;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    logic watch_enable;
    logic [31:0] watched_address;
    integer target_accesses;
    mx_mem_command_t target_commands [0:1];
    logic [7:0] baseline [0:47];

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    mx68k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n, .stopped, .faulted,
        .terminal_exception, .retire_valid, .retire_pc,
        .retire_instruction_id, .debug_pc, .debug_sr, .debug_usp,
        .debug_ssp, .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    mx68k_ram #(.MEM_BYTES(1024)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(.MEM_BYTES(1024)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            target_accesses <= 0;
            target_commands[0] <= MX_MEM_READ;
            target_commands[1] <= MX_MEM_READ;
        end else if (watch_enable && dmem_bus.req_valid &&
                     dmem_bus.req_ready &&
                     (dmem_bus.req.addr == watched_address)) begin
            assert (target_accesses < 2);
            target_commands[target_accesses] <= dmem_bus.req.command;
            target_accesses <= target_accesses + 1;
        end
    end

    task automatic set_instruction_word(input integer address,
                                        input logic [15:0] value);
        instruction_ram.storage[address] = value[15:8];
        instruction_ram.storage[address + 1] = value[7:0];
    endtask

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        data_ram.storage[address] = value[31:24];
        data_ram.storage[address + 1] = value[23:16];
        data_ram.storage[address + 2] = value[15:8];
        data_ram.storage[address + 3] = value[7:0];
    endtask

    // Independent transcription of PRM table 3-19.  The test deliberately
    // does not call mx_condition_true(), which is the RTL oracle under test.
    function automatic logic expected_condition(
        input logic [3:0] condition,
        input logic [3:0] nzvc
    );
        logic n;
        logic z;
        logic v;
        logic c;
        begin
            n = nzvc[3];
            z = nzvc[2];
            v = nzvc[1];
            c = nzvc[0];
            case (condition)
                4'h0: return 1'b1;             // T
                4'h1: return 1'b0;             // F
                4'h2: return !c && !z;          // HI
                4'h3: return c || z;            // LS
                4'h4: return !c;                // CC/HS
                4'h5: return c;                 // CS/LO
                4'h6: return !z;                // NE
                4'h7: return z;                 // EQ
                4'h8: return !v;                // VC
                4'h9: return v;                 // VS
                4'ha: return !n;                // PL
                4'hb: return n;                 // MI
                4'hc: return n == v;            // GE
                4'hd: return n != v;            // LT
                4'he: return !z && (n == v);    // GT
                default: return z || (n != v);  // LE
            endcase
        end
    endfunction

    function automatic logic [3:0] flags_for_result(
        input logic [3:0] condition,
        input logic desired
    );
        logic found;
        logic [3:0] selected;
        begin
            found = 1'b0;
            selected = 4'd0;
            for (int candidate = 0; candidate < 16; candidate++) begin
                if (!found &&
                    (expected_condition(condition, candidate[3:0]) ==
                     desired)) begin
                    selected = candidate[3:0];
                    found = 1'b1;
                end
            end
            // T and F have only one possible result.  Any flags still test
            // that those constant conditions ignore NZVC.
            return found ? selected : 4'd0;
        end
    endfunction

    function automatic integer byte_step(input integer register_index);
        return (register_index == 7) ? 2 : 1;
    endfunction

    task automatic run_scc_case(input integer condition_index,
                                input integer ea_mode,
                                input integer ea_register,
                                input logic desired_result);
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer extension_count;
        integer stop_pc;
        integer case_cycles;
        logic [3:0] nzvc;
        logic x_flag;
        logic condition_result;
        logic [4:0] initial_ccr;
        logic [7:0] expected_byte;
        logic [15:0] opcode;
        logic [31:0] initial_register;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            expected_address = base_address;
            extension_count = 0;
            nzvc = flags_for_result(condition_index[3:0], desired_result);
            x_flag = desired_result;
            initial_ccr = {x_flag, nzvc};
            condition_result = expected_condition(condition_index[3:0], nzvc);
            expected_byte = condition_result ? 8'hff : 8'h00;
            initial_register = 32'ha5a5_5a00 | ea_register[7:0];

            if (ea_mode == 3)
                expected_address = base_address + byte_step(ea_register);
            else if (ea_mode == 4) begin
                effective_address = base_address - byte_step(ea_register);
                expected_address = effective_address;
            end
            if ((ea_mode == 5) || (ea_mode == 6) ||
                ((ea_mode == 7) && (ea_register == 0)))
                extension_count = 1;
            else if ((ea_mode == 7) && (ea_register == 1))
                extension_count = 2;

            rst_n = 1'b0;
            watch_enable = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);
            for (int byte_index = 0; byte_index < 48; byte_index++)
                data_ram.storage[16'h208 + byte_index] =
                    8'(8'h30 + byte_index);

            if (ea_mode == 0) begin
                set_instruction_word(16'h100,
                    16'(16'h203c | (ea_register << 9)));
                set_instruction_word(16'h102, initial_register[31:16]);
                set_instruction_word(16'h104, initial_register[15:0]);
            end else begin
                set_instruction_word(16'h100,
                    16'(16'h207c | (ea_register << 9)));
                set_instruction_word(16'h102, 16'h0000);
                set_instruction_word(16'h104, base_address[15:0]);
                data_ram.storage[effective_address] = 8'h5a;
                for (int byte_index = 0; byte_index < 48; byte_index++)
                    baseline[byte_index] =
                        data_ram.storage[16'h208 + byte_index];
            end
            set_instruction_word(16'h106, 16'h44fc); // MOVE.W #ccr,CCR
            set_instruction_word(16'h108, {11'd0, initial_ccr});

            opcode = 16'(16'h50c0 | (condition_index << 8) |
                         (ea_mode << 3) | ea_register);
            set_instruction_word(16'h10a, opcode);
            if ((ea_mode == 5) || (ea_mode == 6))
                set_instruction_word(16'h10c, 16'h0000);
            else if ((ea_mode == 7) && (ea_register == 0))
                set_instruction_word(16'h10c, base_address[15:0]);
            else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(16'h10c, 16'h0000);
                set_instruction_word(16'h10e, base_address[15:0]);
            end
            stop_pc = 16'h10c + 2 * extension_count;
            set_instruction_word(stop_pc, 16'h4e72);
            set_instruction_word(stop_pc + 2, 16'h2700);

            watched_address = effective_address;
            watch_enable = (ea_mode != 0);
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_010a))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 400)
                    $fatal(1,
                        "Scc matrix timeout: cc=%0d ea=%0d/%0d desired=%0d",
                        condition_index, ea_mode, ea_register, desired_result);
            end

            assert (retire_instruction_id ==
                    8'(MX_INSN_ST + condition_index));
            assert (debug_sr == {11'h138, initial_ccr});
            if (ea_mode == 0) begin
                assert (debug_data_registers[ea_register*32 +: 32] ==
                        {initial_register[31:8], expected_byte});
                assert (target_accesses == 0);
            end else begin
                assert (data_ram.storage[effective_address] == expected_byte);
                for (int byte_index = 0; byte_index < 48; byte_index++)
                    if ((16'h208 + byte_index) != effective_address)
                        assert (data_ram.storage[16'h208 + byte_index] ==
                                baseline[byte_index]);
                assert (debug_address_registers[ea_register*32 +: 32] ==
                        expected_address);
                assert (target_accesses == 2);
                assert (target_commands[0] == MX_MEM_READ);
                assert (target_commands[1] == MX_MEM_WRITE);
            end

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        // Exercise every legal opcode word once with a requested false
        // result and once with true.  Constant T/F naturally retain their
        // architected fixed result in both passes.
        for (int condition_index = 0; condition_index < 16;
             condition_index++) begin
            for (int result_index = 0; result_index < 2; result_index++) begin
                for (int register_index = 0; register_index < 8;
                     register_index++)
                    run_scc_case(condition_index, 0, register_index,
                                 result_index[0]);
                for (int mode_index = 2; mode_index <= 6; mode_index++)
                    for (int register_index = 0; register_index < 8;
                         register_index++)
                        run_scc_case(condition_index, mode_index,
                                     register_index, result_index[0]);
                run_scc_case(condition_index, 7, 0, result_index[0]);
                run_scc_case(condition_index, 7, 1, result_index[0]);
            end
        end

        $display("PASS: all 800 legal M00 Scc words, both outcomes, flags and RMWs");
        $finish;
    end
endmodule
