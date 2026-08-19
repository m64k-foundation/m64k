module m64k_core_immediate_matrix_tb;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;
    import m64k_m00_decode_table_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
    logic stopped;
    logic faulted;
    m64k_exception_t terminal_exception;
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
    m64k_mem_command_t target_commands [0:1];
    logic [7:0] baseline [0:95];

    m64k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    m64k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    m64k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n, .stopped, .faulted,
        .terminal_exception, .retire_valid, .retire_pc,
        .retire_instruction_id, .debug_pc, .debug_sr, .debug_usp,
        .debug_ssp, .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    m64k_ram #(.MEM_BYTES(1024)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    m64k_ram #(.MEM_BYTES(1024)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            target_accesses <= 0;
            target_commands[0] <= M64K_MEM_READ;
            target_commands[1] <= M64K_MEM_READ;
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

    function automatic logic [15:0] operation_base(input integer operation);
        case (operation)
            0: return 16'h0000; // ORI
            1: return 16'h0200; // ANDI
            2: return 16'h0400; // SUBI
            3: return 16'h0600; // ADDI
            4: return 16'h0a00; // EORI
            default: return 16'h0c00; // CMPI
        endcase
    endfunction

    function automatic logic [7:0] operation_id(input integer operation);
        case (operation)
            0: return M64K_INSN_ORI;
            1: return M64K_INSN_ANDI;
            2: return M64K_INSN_SUBI;
            3: return M64K_INSN_ADDI;
            4: return M64K_INSN_EORI;
            default: return M64K_INSN_CMPI;
        endcase
    endfunction

    task automatic sample_values(input integer scenario,
                                 input integer size_index,
                                 output logic [31:0] operand,
                                 output logic [31:0] immediate);
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] operand_low;
        logic [31:0] immediate_low;
        begin
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            case (scenario & 7)
                0: begin operand_low = 0; immediate_low = 0; end
                1: begin operand_low = mask; immediate_low = 1; end
                2: begin operand_low = sign_bit - 1; immediate_low = 1; end
                3: begin operand_low = sign_bit; immediate_low = 1; end
                4: begin operand_low = 0; immediate_low = 1; end
                5: begin operand_low = 1; immediate_low = mask; end
                6: begin
                    operand_low = 32'h5555_5555 & mask;
                    immediate_low = 32'haaaa_aaaa & mask;
                end
                default: begin operand_low = mask; immediate_low = mask; end
            endcase
            operand = ((size_index == 2) ? 32'd0 : 32'ha5a5_0000) |
                      operand_low;
            immediate = immediate_low;
        end
    endtask

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

    function automatic logic addition_carry(input integer size_index,
                                              input logic [31:0] lhs,
                                              input logic [31:0] rhs);
        logic [32:0] extended;
        begin
            extended = {1'b0, lhs & size_mask(size_index)} +
                       {1'b0, rhs & size_mask(size_index)};
            case (size_index)
                0: return extended[8];
                1: return extended[16];
                default: return extended[32];
            endcase
        end
    endfunction

    task automatic run_immediate_case(input integer operation,
                                      input integer size_index,
                                      input integer ea_mode,
                                      input integer ea_register);
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer immediate_words;
        integer extension_words;
        integer cursor;
        integer stop_pc;
        integer case_cycles;
        integer scenario;
        logic compare_only;
        logic arithmetic;
        logic subtract;
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] operand;
        logic [31:0] immediate;
        logic [31:0] operand_sized;
        logic [31:0] immediate_sized;
        logic [31:0] result_sized;
        logic [31:0] expected_register;
        logic [4:0] initial_ccr;
        logic [4:0] expected_ccr;
        logic [15:0] opcode;
        logic operand_sign;
        logic immediate_sign;
        logic result_sign;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            expected_address = base_address;
            immediate_words = (size_index == 2) ? 2 : 1;
            extension_words = 0;
            compare_only = (operation == 5);
            arithmetic = (operation == 2) || (operation == 3) ||
                         compare_only;
            subtract = (operation == 2) || compare_only;
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            scenario = operation * 3 + size_index * 5 +
                       ea_mode * 2 + ea_register;
            sample_values(scenario, size_index, operand, immediate);
            operand_sized = operand & mask;
            immediate_sized = immediate & mask;

            case (operation)
                0: result_sized = operand_sized | immediate_sized;
                1: result_sized = operand_sized & immediate_sized;
                2, 5: result_sized =
                    (operand_sized - immediate_sized) & mask;
                3: result_sized =
                    (operand_sized + immediate_sized) & mask;
                default: result_sized = operand_sized ^ immediate_sized;
            endcase
            expected_register = compare_only ? operand :
                ((operand & ~mask) | result_sized);

            initial_ccr = 5'b1_0101;
            expected_ccr = initial_ccr;
            operand_sign = |(operand_sized & sign_bit);
            immediate_sign = |(immediate_sized & sign_bit);
            result_sign = |(result_sized & sign_bit);
            expected_ccr[3] = result_sign;
            expected_ccr[2] = (result_sized == 0);
            if (arithmetic) begin
                expected_ccr[1] = subtract ?
                    ((operand_sign != immediate_sign) &&
                     (result_sign != operand_sign)) :
                    ((operand_sign == immediate_sign) &&
                     (result_sign != operand_sign));
                expected_ccr[0] = subtract ?
                    (operand_sized < immediate_sized) :
                    addition_carry(size_index, operand_sized,
                                   immediate_sized);
                if (!compare_only)
                    expected_ccr[4] = expected_ccr[0];
            end else begin
                expected_ccr[1] = 1'b0;
                expected_ccr[0] = 1'b0;
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
                extension_words = 1;
            else if ((ea_mode == 7) && (ea_register == 1))
                extension_words = 2;

            rst_n = 1'b0;
            watch_enable = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);
            for (int byte_index = 0; byte_index < 96; byte_index++)
                data_ram.storage[16'h200 + byte_index] =
                    8'(8'h30 + byte_index);

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
            end
            set_instruction_word(16'h106, 16'h44fc); // MOVE.W #ccr,CCR
            set_instruction_word(16'h108, {11'd0, initial_ccr});

            opcode = operation_base(operation) | 16'(size_index << 6) |
                     16'(ea_mode << 3) | 16'(ea_register);
            set_instruction_word(16'h10a, opcode);
            cursor = 16'h10c;
            if (size_index == 2) begin
                set_instruction_word(cursor, immediate[31:16]);
                set_instruction_word(cursor + 2, immediate[15:0]);
                cursor = cursor + 4;
            end else begin
                // PRM: the byte immediate is the low byte of this word.
                set_instruction_word(cursor,
                    (size_index == 0) ? {8'ha5, immediate[7:0]} :
                                        immediate[15:0]);
                cursor = cursor + 2;
            end
            if ((ea_mode == 5) || (ea_mode == 6)) begin
                set_instruction_word(cursor, 16'h0000);
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 0)) begin
                set_instruction_word(cursor, base_address[15:0]);
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(cursor, 16'h0000);
                set_instruction_word(cursor + 2, base_address[15:0]);
                cursor = cursor + 4;
            end
            stop_pc = cursor;
            set_instruction_word(stop_pc, 16'h4e72);
            set_instruction_word(stop_pc + 2, 16'h2700);

            for (int byte_index = 0; byte_index < 96; byte_index++)
                baseline[byte_index] = data_ram.storage[16'h200 + byte_index];
            watched_address = effective_address;
            watch_enable = (ea_mode != 0);
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_010a))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 500)
                    $fatal(1,
                        "immediate matrix timeout: op=%0d size=%0d ea=%0d/%0d",
                        operation, size_index, ea_mode, ea_register);
            end

            assert (retire_instruction_id == operation_id(operation));
            assert (debug_sr == {11'h138, expected_ccr});
            if (ea_mode == 0) begin
                assert (debug_data_registers[ea_register*32 +: 32] ==
                        expected_register);
                assert (target_accesses == 0);
            end else begin
                assert (load_operand(effective_address, size_index) ==
                        (compare_only ? operand_sized : result_sized));
                for (int byte_index = 0; byte_index < 96; byte_index++)
                    if (((16'h200 + byte_index) < effective_address) ||
                        ((16'h200 + byte_index) >=
                         (effective_address + (1 << size_index))))
                        assert (data_ram.storage[16'h200 + byte_index] ==
                                baseline[byte_index]);
                if ((ea_mode >= 2) && (ea_mode <= 6))
                    assert (debug_address_registers[ea_register*32 +: 32] ==
                            expected_address);
                assert (target_accesses == (compare_only ? 1 : 2));
                assert (target_commands[0] == M64K_MEM_READ);
                if (!compare_only)
                    assert (target_commands[1] == M64K_MEM_WRITE);
            end

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        // PRM data-alterable table: 8 Dn + 40 An-memory aliases +
        // absolute word/long = 50 legal words per size and operation.
        for (int operation = 0; operation < 6; operation++) begin
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int register_index = 0; register_index < 8;
                     register_index++)
                    run_immediate_case(operation, size_index, 0,
                                       register_index);
                for (int mode_index = 2; mode_index <= 6; mode_index++)
                    for (int register_index = 0; register_index < 8;
                         register_index++)
                        run_immediate_case(operation, size_index,
                                           mode_index, register_index);
                run_immediate_case(operation, size_index, 7, 0);
                run_immediate_case(operation, size_index, 7, 1);
            end
        end

        $display("PASS: all 900 legal M00 immediate operation words");
        $finish;
    end
endmodule
