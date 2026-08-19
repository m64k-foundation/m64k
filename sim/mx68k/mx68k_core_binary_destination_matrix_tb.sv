module mx68k_core_binary_destination_matrix_tb;
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
    mx68k_ram #(.MEM_BYTES(2048)) data_ram (
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

    function automatic logic [3:0] operation_nibble(input integer operation);
        case (operation)
            0: return 4'hd; // ADD
            1: return 4'h9; // SUB
            2: return 4'hc; // AND
            3: return 4'h8; // OR
            default: return 4'hb; // EOR
        endcase
    endfunction

    task automatic sample_values(input integer scenario,
                                 input integer size_index,
                                 output logic [31:0] destination,
                                 output logic [31:0] source);
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] destination_low;
        logic [31:0] source_low;
        begin
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            case (scenario & 7)
                0: begin destination_low = 0; source_low = 0; end
                1: begin destination_low = mask; source_low = 1; end
                2: begin destination_low = sign_bit - 1; source_low = 1; end
                3: begin destination_low = sign_bit; source_low = 1; end
                4: begin destination_low = 0; source_low = 1; end
                5: begin destination_low = 1; source_low = mask; end
                6: begin
                    destination_low = 32'h5555_5555 & mask;
                    source_low = 32'haaaa_aaaa & mask;
                end
                default: begin destination_low = mask; source_low = mask; end
            endcase
            destination = ((size_index == 2) ? 32'd0 : 32'ha5a5_0000) |
                          destination_low;
            source = ((size_index == 2) ? 32'd0 : 32'h5a5a_0000) |
                     source_low;
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

    task automatic run_destination_case(input integer operation,
                                        input integer size_index,
                                        input integer source_register,
                                        input integer ea_mode,
                                        input integer ea_register);
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer cursor;
        integer case_cycles;
        logic register_destination;
        logic arithmetic;
        logic subtract;
        logic [31:0] mask;
        logic [31:0] sign_bit;
        logic [31:0] destination;
        logic [31:0] source;
        logic [31:0] destination_sized;
        logic [31:0] source_sized;
        logic [31:0] result_sized;
        logic [31:0] expected_destination_register;
        logic [4:0] initial_ccr;
        logic [4:0] expected_ccr;
        logic [15:0] opcode;
        logic destination_sign;
        logic source_sign;
        logic result_sign;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            expected_address = base_address;
            register_destination = (ea_mode == 0);
            arithmetic = (operation == 0) || (operation == 1);
            subtract = (operation == 1);
            mask = size_mask(size_index);
            sign_bit = sign_mask(size_index);
            sample_values(operation * 13 + size_index * 7 +
                          source_register * 3 + ea_mode + ea_register,
                          size_index, destination, source);
            if (register_destination &&
                (source_register == ea_register))
                source = destination;
            destination_sized = destination & mask;
            source_sized = source & mask;
            case (operation)
                0: result_sized = (destination_sized + source_sized) & mask;
                1: result_sized = (destination_sized - source_sized) & mask;
                2: result_sized = destination_sized & source_sized;
                3: result_sized = destination_sized | source_sized;
                default: result_sized = destination_sized ^ source_sized;
            endcase
            expected_destination_register =
                (destination & ~mask) | result_sized;

            initial_ccr = 5'b1_0101;
            expected_ccr = initial_ccr;
            destination_sign = |(destination_sized & sign_bit);
            source_sign = |(source_sized & sign_bit);
            result_sign = |(result_sized & sign_bit);
            expected_ccr[3] = result_sign;
            expected_ccr[2] = (result_sized == 0);
            if (arithmetic) begin
                expected_ccr[1] = subtract ?
                    ((destination_sign != source_sign) &&
                     (result_sign != destination_sign)) :
                    ((destination_sign == source_sign) &&
                     (result_sign != destination_sign));
                expected_ccr[0] = subtract ?
                    (destination_sized < source_sized) :
                    addition_carry(size_index, destination_sized,
                                   source_sized);
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
            end else if ((ea_mode == 6) && (ea_register == 6))
                effective_address = base_address + base_address;

            rst_n = 1'b0;
            watch_enable = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0780);
            set_data_long(4, 32'h0000_0100);

            set_instruction_word(16'h100,
                16'(16'h203c | (source_register << 9)));
            set_instruction_word(16'h102, source[31:16]);
            set_instruction_word(16'h104, source[15:0]);
            if (register_destination)
                set_instruction_word(16'h106,
                    16'(16'h203c | (ea_register << 9)));
            else
                set_instruction_word(16'h106,
                    16'(16'h207c | (ea_register << 9)));
            set_instruction_word(16'h108,
                register_destination ? destination[31:16] : 16'h0000);
            set_instruction_word(16'h10a,
                register_destination ? destination[15:0] :
                                       base_address[15:0]);
            set_instruction_word(16'h10c, 16'h44fc); // MOVE.W #ccr,CCR
            set_instruction_word(16'h10e, {11'd0, initial_ccr});

            opcode = {operation_nibble(operation), source_register[2:0],
                      1'b1, size_index[1:0],
                      ea_mode[2:0], ea_register[2:0]};
            set_instruction_word(16'h110, opcode);
            cursor = 16'h112;
            if (ea_mode == 5) begin
                set_instruction_word(cursor, 16'h0000);
                cursor = cursor + 2;
            end else if (ea_mode == 6) begin
                set_instruction_word(cursor, 16'he000); // A6.W + disp 0
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 0)) begin
                set_instruction_word(cursor, base_address[15:0]);
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(cursor, 16'h0000);
                set_instruction_word(cursor + 2, base_address[15:0]);
                cursor = cursor + 4;
            end
            set_instruction_word(cursor, 16'h4e72);
            set_instruction_word(cursor + 2, 16'h2700);

            if (!register_destination)
                store_operand(effective_address, size_index,
                              destination_sized);
            watched_address = effective_address;
            watch_enable = !register_destination;
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_0110))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 500)
                    $fatal(1,
                        "binary destination timeout: op=%0d size=%0d D=%0d ea=%0d/%0d",
                        operation, size_index, source_register,
                        ea_mode, ea_register);
            end

            assert (retire_instruction_id ==
                    8'(MX_INSN_ADD_DN_EA_B + operation * 3 + size_index));
            assert (debug_sr == {11'h138, expected_ccr});
            if (register_destination) begin
                assert (debug_data_registers[ea_register*32 +: 32] ==
                        expected_destination_register);
                assert (target_accesses == 0);
            end else begin
                assert (load_operand(effective_address, size_index) ==
                        result_sized);
                assert (debug_data_registers[source_register*32 +: 32] ==
                        source);
                assert (target_accesses == 2);
                assert (target_commands[0] == MX_MEM_READ);
                assert (target_commands[1] == MX_MEM_WRITE);
                if ((ea_mode >= 2) && (ea_mode <= 6))
                    assert (debug_address_registers[ea_register*32 +: 32] ==
                            expected_address);
            end

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        for (int operation = 0; operation < 5; operation++) begin
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int source_register = 0;
                     source_register < 8; source_register++) begin
                    if (operation == 4)
                        for (int ea_register = 0; ea_register < 8;
                             ea_register++)
                            run_destination_case(operation, size_index,
                                                 source_register, 0,
                                                 ea_register);
                    for (int ea_mode = 2; ea_mode <= 6; ea_mode++)
                        for (int ea_register = 0; ea_register < 8;
                             ea_register++)
                            run_destination_case(operation, size_index,
                                                 source_register, ea_mode,
                                                 ea_register);
                    run_destination_case(operation, size_index,
                                         source_register, 7, 0);
                    run_destination_case(operation, size_index,
                                         source_register, 7, 1);
                end
            end
        end

        $display("PASS: all 5232 legal M00 Dn,<ea> binary words");
        $finish;
    end
endmodule
