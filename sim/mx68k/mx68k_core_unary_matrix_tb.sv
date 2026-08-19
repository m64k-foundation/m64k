module mx68k_core_unary_matrix_tb;
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
    logic [7:0] baseline [0:31];

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

    function automatic logic [31:0] size_mask(input integer size_index);
        case (size_index)
            0: return 32'h0000_00ff;
            1: return 32'h0000_ffff;
            default: return 32'hffff_ffff;
        endcase
    endfunction

    function automatic logic [31:0] sign_mask(input integer size_index);
        case (size_index)
            0: return 32'h0000_0080;
            1: return 32'h0000_8000;
            default: return 32'h8000_0000;
        endcase
    endfunction

    function automatic integer operand_step(input integer size_index,
                                             input integer register_index);
        if (size_index == 0)
            return (register_index == 7) ? 2 : 1;
        if (size_index == 1)
            return 2;
        return 4;
    endfunction

    function automatic logic [31:0] sample_operand(
        input integer size_index,
        input integer alias_index
    );
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] low_value;
        begin
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            case (alias_index & 3)
                0: low_value = 32'd0;
                1: low_value = 32'd1;
                2: low_value = sign_bit;
                default: low_value = mask;
            endcase
            sample_operand = ((size_index == 2) ? 32'd0 : 32'ha5a5_0000) |
                             low_value;
        end
    endfunction

    task automatic store_operand(input integer address,
                                 input integer size_index,
                                 input logic [31:0] value);
        if (size_index == 0)
            data_ram.storage[address] = value[7:0];
        else if (size_index == 1) begin
            data_ram.storage[address] = value[15:8];
            data_ram.storage[address + 1] = value[7:0];
        end else
            set_data_long(address, value);
    endtask

    function automatic logic [31:0] load_operand(input integer address,
                                                  input integer size_index);
        case (size_index)
            0: return {24'd0, data_ram.storage[address]};
            1: return {16'd0, data_ram.storage[address],
                      data_ram.storage[address + 1]};
            default: return {data_ram.storage[address],
                             data_ram.storage[address + 1],
                             data_ram.storage[address + 2],
                             data_ram.storage[address + 3]};
        endcase
    endfunction

    task automatic run_unary_case(input integer unary_index,
                                  input integer size_index,
                                  input integer ea_mode,
                                  input integer ea_register);
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer extension_count;
        integer stop_pc;
        integer case_cycles;
        integer opcode_base;
        logic [7:0] expected_instruction_id;
        logic [15:0] unary_opcode;
        logic [31:0] operand;
        logic [31:0] operand_sized;
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] result_sized;
        logic [31:0] expected_register;
        logic [4:0] expected_ccr;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            expected_address = base_address;
            extension_count = 0;
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            operand = sample_operand(size_index, ea_register);
            operand_sized = operand & mask;

            case (unary_index)
                0: begin
                    opcode_base = 16'h4200;
                    expected_instruction_id = MX_INSN_CLR;
                    result_sized = 32'd0;
                    expected_ccr = 5'b1_0100;
                end
                1: begin
                    opcode_base = 16'h4400;
                    expected_instruction_id = MX_INSN_NEG;
                    result_sized = (32'd0 - operand_sized) & mask;
                    expected_ccr[4] = (operand_sized != 0); // X=C
                    expected_ccr[3] = |(result_sized & sign_bit);
                    expected_ccr[2] = (result_sized == 0);
                    expected_ccr[1] = (operand_sized == sign_bit);
                    expected_ccr[0] = (operand_sized != 0);
                end
                default: begin
                    opcode_base = 16'h4600;
                    expected_instruction_id = MX_INSN_NOT;
                    result_sized = (~operand_sized) & mask;
                    expected_ccr[4] = 1'b1; // X preserved
                    expected_ccr[3] = |(result_sized & sign_bit);
                    expected_ccr[2] = (result_sized == 0);
                    expected_ccr[1] = 1'b0;
                    expected_ccr[0] = 1'b0;
                end
            endcase
            expected_register = (operand & ~mask) | result_sized;

            if (ea_mode == 3)
                expected_address = base_address +
                    operand_step(size_index, ea_register);
            else if (ea_mode == 4) begin
                effective_address = base_address -
                    operand_step(size_index, ea_register);
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
            for (int byte_index = 0; byte_index < 32; byte_index++)
                data_ram.storage[16'h210 + byte_index] =
                    8'(8'h40 + byte_index);

            if (ea_mode == 0) begin
                set_instruction_word(16'h100,
                    16'(16'h203c | (ea_register << 9)));
                set_instruction_word(16'h102, operand[31:16]);
                set_instruction_word(16'h104, operand[15:0]);
            end else begin
                set_instruction_word(16'h100,
                    16'(16'h207c | (ea_register << 9)));
                set_instruction_word(16'h102, 16'h0000);
                set_instruction_word(16'h104, base_address[15:0]);
                store_operand(effective_address, size_index, operand_sized);
                for (int byte_index = 0; byte_index < 32; byte_index++)
                    baseline[byte_index] =
                        data_ram.storage[16'h210 + byte_index];
            end
            set_instruction_word(16'h106, 16'h44fc); // MOVE.W #$1f,CCR
            set_instruction_word(16'h108, 16'h001f);

            unary_opcode = 16'(opcode_base | (size_index << 6) |
                               (ea_mode << 3) | ea_register);
            set_instruction_word(16'h10a, unary_opcode);
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
                        "unary matrix timeout: op=%0d size=%0d ea=%0d/%0d",
                        unary_index, size_index, ea_mode, ea_register);
            end

            assert (retire_instruction_id == expected_instruction_id);
            assert (debug_sr == {11'h138, expected_ccr});
            if (ea_mode == 0) begin
                assert (debug_data_registers[ea_register*32 +: 32] ==
                        expected_register);
                assert (target_accesses == 0);
            end else begin
                assert (load_operand(effective_address, size_index) ==
                        result_sized);
                for (int byte_index = 0; byte_index < 32; byte_index++)
                    if (((16'h210 + byte_index) < effective_address) ||
                        ((16'h210 + byte_index) >=
                         (effective_address + (1 << size_index))))
                        assert (data_ram.storage[16'h210 + byte_index] ==
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

        // Each family has 3 sizes x 50 legal data-alterable EAs.
        for (int unary_index = 0; unary_index < 3; unary_index++) begin
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int register_index = 0; register_index < 8;
                     register_index++)
                    run_unary_case(unary_index, size_index, 0,
                                   register_index);
                for (int mode_index = 2; mode_index <= 6; mode_index++)
                    for (int register_index = 0; register_index < 8;
                         register_index++)
                        run_unary_case(unary_index, size_index, mode_index,
                                       register_index);
                run_unary_case(unary_index, size_index, 7, 0);
                run_unary_case(unary_index, size_index, 7, 1);
            end
        end

        $display("PASS: all 450 legal M00 CLR/NEG/NOT words, flags and RMWs");
        $finish;
    end
endmodule
