module mx68k_core_quick_matrix_tb;
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
        input integer quick_value,
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
                1: low_value = mask;
                2: low_value = sign_bit;
                default: low_value = (sign_bit - quick_value) & mask;
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

    function automatic logic carry_out(input logic subtract,
                                        input integer size_index,
                                        input logic [31:0] lhs,
                                        input logic [31:0] rhs);
        logic [32:0] extended;
        begin
            if (subtract)
                return (lhs & size_mask(size_index)) < rhs;
            extended = {1'b0, lhs & size_mask(size_index)} + rhs;
            case (size_index)
                0: return extended[8];
                1: return extended[16];
                default: return extended[32];
            endcase
        end
    endfunction

    task automatic run_quick_case(input logic subtract,
                                  input integer quick_field,
                                  input integer size_index,
                                  input integer ea_mode,
                                  input integer ea_register);
        integer quick_value;
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer extension_count;
        integer stop_pc;
        integer case_cycles;
        logic address_destination;
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] operand;
        logic [31:0] operand_sized;
        logic [31:0] result_sized;
        logic [31:0] expected_register;
        logic [4:0] initial_ccr;
        logic [4:0] expected_ccr;
        logic [15:0] opcode;
        logic result_sign;
        logic operand_sign;
        begin
            quick_value = (quick_field == 0) ? 8 : quick_field;
            address_destination = (ea_mode == 1);
            base_address = 16'h0220;
            effective_address = base_address;
            expected_address = base_address;
            extension_count = 0;
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            operand = sample_operand(size_index, quick_value,
                                     quick_field + ea_mode + ea_register);
            operand_sized = operand & mask;
            result_sized = subtract ?
                ((operand_sized - quick_value) & mask) :
                ((operand_sized + quick_value) & mask);
            initial_ccr = 5'b0_1010;
            expected_ccr = initial_ccr;

            if (address_destination) begin
                operand = {operand[31:16], operand[15:0]};
                expected_register = subtract ? operand - quick_value :
                                               operand + quick_value;
            end else begin
                expected_register = (operand & ~mask) | result_sized;
                operand_sign = |(operand_sized & sign_bit);
                result_sign = |(result_sized & sign_bit);
                expected_ccr[4] = carry_out(subtract, size_index,
                                            operand_sized, quick_value);
                expected_ccr[3] = result_sign;
                expected_ccr[2] = (result_sized == 0);
                expected_ccr[1] = subtract ?
                    (operand_sign && !result_sign) :
                    (!operand_sign && result_sign);
                expected_ccr[0] = expected_ccr[4];
            end

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
            for (int byte_index = 0; byte_index < 48; byte_index++)
                data_ram.storage[16'h208 + byte_index] =
                    8'(8'h40 + byte_index);

            if ((ea_mode == 0) || address_destination) begin
                set_instruction_word(16'h100,
                    16'((address_destination ? 16'h207c : 16'h203c) |
                        (ea_register << 9)));
                set_instruction_word(16'h102, operand[31:16]);
                set_instruction_word(16'h104, operand[15:0]);
            end else begin
                set_instruction_word(16'h100,
                    16'(16'h207c | (ea_register << 9)));
                set_instruction_word(16'h102, 16'h0000);
                set_instruction_word(16'h104, base_address[15:0]);
                store_operand(effective_address, size_index, operand_sized);
                for (int byte_index = 0; byte_index < 48; byte_index++)
                    baseline[byte_index] =
                        data_ram.storage[16'h208 + byte_index];
            end
            set_instruction_word(16'h106, 16'h44fc); // MOVE.W #ccr,CCR
            set_instruction_word(16'h108, {11'd0, initial_ccr});

            opcode = 16'(16'h5000 | (quick_field << 9) |
                (subtract << 8) | (size_index << 6) |
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
            watch_enable = (ea_mode >= 2);
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_010a))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 400)
                    $fatal(1,
                        "quick matrix timeout: sub=%0d q=%0d size=%0d ea=%0d/%0d",
                        subtract, quick_field, size_index, ea_mode, ea_register);
            end

            assert (retire_instruction_id ==
                    (subtract ? MX_INSN_SUBQ : MX_INSN_ADDQ));
            assert (debug_sr == {11'h138, expected_ccr});
            if (ea_mode == 0)
                assert (debug_data_registers[ea_register*32 +: 32] ==
                        expected_register);
            else if (address_destination)
                assert (debug_address_registers[ea_register*32 +: 32] ==
                        expected_register);
            else begin
                assert (load_operand(effective_address, size_index) ==
                        result_sized);
                for (int byte_index = 0; byte_index < 48; byte_index++)
                    if (((16'h208 + byte_index) < effective_address) ||
                        ((16'h208 + byte_index) >=
                         (effective_address + (1 << size_index))))
                        assert (data_ram.storage[16'h208 + byte_index] ==
                                baseline[byte_index]);
                assert (debug_address_registers[ea_register*32 +: 32] ==
                        expected_address);
                assert (target_accesses == 2);
                assert (target_commands[0] == MX_MEM_READ);
                assert (target_commands[1] == MX_MEM_WRITE);
            end
            if ((ea_mode == 0) || address_destination)
                assert (target_accesses == 0);

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        for (int operation_index = 0; operation_index < 2;
             operation_index++) begin
            for (int quick_field = 0; quick_field < 8; quick_field++) begin
                for (int size_index = 0; size_index < 3; size_index++) begin
                    for (int register_index = 0; register_index < 8;
                         register_index++)
                        run_quick_case(operation_index[0], quick_field,
                                       size_index, 0, register_index);
                    if (size_index != 0)
                        for (int register_index = 0; register_index < 8;
                             register_index++)
                            run_quick_case(operation_index[0], quick_field,
                                           size_index, 1, register_index);
                    for (int mode_index = 2; mode_index <= 6; mode_index++)
                        for (int register_index = 0; register_index < 8;
                             register_index++)
                            run_quick_case(operation_index[0], quick_field,
                                           size_index, mode_index,
                                           register_index);
                    run_quick_case(operation_index[0], quick_field,
                                   size_index, 7, 0);
                    run_quick_case(operation_index[0], quick_field,
                                   size_index, 7, 1);
                end
            end
        end

        $display("PASS: all 2656 legal M00 ADDQ/SUBQ words, flags and RMWs");
        $finish;
    end
endmodule
