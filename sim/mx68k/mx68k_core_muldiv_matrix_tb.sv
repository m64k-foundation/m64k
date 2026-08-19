module mx68k_core_muldiv_matrix_tb;
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
    mx_mem_command_t target_command;

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
            target_command <= MX_MEM_READ;
        end else if (watch_enable && dmem_bus.req_valid &&
                     dmem_bus.req_ready &&
                     (dmem_bus.req.addr == watched_address)) begin
            assert (target_accesses == 0);
            target_command <= dmem_bus.req.command;
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

    task automatic set_data_word(input integer address,
                                 input logic [15:0] value);
        data_ram.storage[address] = value[15:8];
        data_ram.storage[address + 1] = value[7:0];
    endtask

    function automatic logic [15:0] get_data_word(input integer address);
        return {data_ram.storage[address], data_ram.storage[address + 1]};
    endfunction

    function automatic logic [7:0] operation_id(input integer operation);
        case (operation)
            0: return MX_INSN_MULU;
            1: return MX_INSN_MULS;
            2: return MX_INSN_DIVU;
            default: return MX_INSN_DIVS;
        endcase
    endfunction

    function automatic logic [15:0] operation_base(input integer operation);
        case (operation)
            0: return 16'hc0c0;
            1: return 16'hc1c0;
            2: return 16'h80c0;
            default: return 16'h81c0;
        endcase
    endfunction

    task automatic choose_operands(input integer operation,
                                   input integer scenario,
                                   output logic [31:0] destination,
                                   output logic [15:0] source);
        integer signed signed_divisor;
        integer signed signed_quotient;
        integer unsigned unsigned_divisor;
        integer unsigned unsigned_quotient;
        begin
            case (operation)
                0: begin
                    source = 16'((scenario * 16'h0137) ^ 16'ha55a);
                    destination = {16'hdead,
                                   16'((scenario * 16'h0029) ^ 16'h8001)};
                end
                1: begin
                    source = 16'((scenario * 16'h0211) ^ 16'h8003);
                    destination = {16'hbeef,
                                   16'((scenario * 16'h0043) ^ 16'h7ffd)};
                end
                2: begin
                    unsigned_divisor = 1 + ((scenario * 251) % 65535);
                    unsigned_quotient = (scenario * 997) % 60000;
                    source = 16'(unsigned_divisor);
                    destination = unsigned_divisor * unsigned_quotient +
                                  (scenario % unsigned_divisor);
                end
                default: begin
                    signed_divisor = 1 + ((scenario * 127) % 32767);
                    if (scenario & 1)
                        signed_divisor = -signed_divisor;
                    signed_quotient = (scenario * 313) % 30000;
                    if (scenario & 2)
                        signed_quotient = -signed_quotient;
                    source = 16'(signed_divisor);
                    destination = 32'(signed_divisor * signed_quotient);
                end
            endcase
        end
    endtask

    task automatic expected_result_and_sr(
        input integer operation,
        input logic [31:0] destination,
        input logic [15:0] source,
        output logic [31:0] result,
        output logic [15:0] expected_sr
    );
        logic [31:0] unsigned_quotient;
        logic [31:0] unsigned_remainder;
        logic signed [63:0] signed_product;
        logic signed [63:0] signed_quotient;
        logic signed [63:0] signed_remainder;
        begin
            expected_sr = 16'h2710; // X is unaffected; V and C clear.
            case (operation)
                0: begin
                    result = destination[15:0] * source;
                    expected_sr[MX_SR_N] = result[31];
                    expected_sr[MX_SR_Z] = (result == 0);
                end
                1: begin
                    signed_product = $signed(destination[15:0]) *
                                     $signed(source);
                    result = signed_product[31:0];
                    expected_sr[MX_SR_N] = result[31];
                    expected_sr[MX_SR_Z] = (result == 0);
                end
                2: begin
                    unsigned_quotient = destination / source;
                    unsigned_remainder = destination % source;
                    assert (unsigned_quotient <= 32'h0000_ffff);
                    result = {unsigned_remainder[15:0],
                              unsigned_quotient[15:0]};
                    expected_sr[MX_SR_N] = unsigned_quotient[15];
                    expected_sr[MX_SR_Z] = (unsigned_quotient == 0);
                end
                default: begin
                    signed_quotient = $signed(destination) /
                                      $signed(source);
                    signed_remainder = $signed(destination) %
                                       $signed(source);
                    assert ((signed_quotient >= -64'sd32768) &&
                            (signed_quotient <= 64'sd32767));
                    result = {signed_remainder[15:0],
                              signed_quotient[15:0]};
                    expected_sr[MX_SR_N] = signed_quotient[15];
                    expected_sr[MX_SR_Z] = (signed_quotient == 0);
                end
            endcase
        end
    endtask

    task automatic run_case(input integer operation,
                            input integer destination_register,
                            input integer ea_mode,
                            input integer ea_register);
        integer base_address;
        integer effective_address;
        integer helper_register;
        integer cursor;
        integer instruction_pc;
        integer extension_pc;
        integer case_cycles;
        logic memory_source;
        logic [31:0] destination;
        logic [15:0] source;
        logic [31:0] expected_result;
        logic [15:0] expected_sr;
        logic [15:0] opcode;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            memory_source = ((ea_mode >= 2) && (ea_mode <= 6)) ||
                            ((ea_mode == 7) && (ea_register <= 3));
            helper_register = (destination_register + 1) & 7;
            choose_operands(operation,
                            operation * 1000 + destination_register * 67 +
                            ea_mode * 11 + ea_register,
                            destination, source);

            // With Dn as both source and destination, the source word is the
            // original low word of Dn.  Choose nonzero, non-overflow divide
            // operands so this alias is exercised in the success matrix.
            if ((ea_mode == 0) &&
                (ea_register == destination_register)) begin
                if (operation == 2)
                    destination = 32'h0002_0003;
                else if (operation == 3)
                    destination = 32'hffff_fffd;
                source = destination[15:0];
            end
            expected_result_and_sr(operation, destination, source,
                                   expected_result, expected_sr);

            rst_n = 1'b0;
            watch_enable = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0780);
            set_data_long(4, 32'h0000_0100);

            cursor = 16'h0100;
            if ((ea_mode == 0) &&
                (ea_register != destination_register)) begin
                set_instruction_word(cursor,
                    16'(16'h203c | (ea_register << 9)));
                set_instruction_word(cursor + 2, 16'hcafe);
                set_instruction_word(cursor + 4, source);
                cursor = cursor + 6;
            end
            set_instruction_word(cursor,
                16'(16'h203c | (destination_register << 9)));
            set_instruction_word(cursor + 2, destination[31:16]);
            set_instruction_word(cursor + 4, destination[15:0]);
            cursor = cursor + 6;

            if ((ea_mode == 6) ||
                ((ea_mode == 7) && (ea_register == 3))) begin
                set_instruction_word(cursor,
                    16'(16'h203c | (helper_register << 9)));
                set_instruction_word(cursor + 2, 16'h0000);
                set_instruction_word(cursor + 4, 16'h0000);
                cursor = cursor + 6;
            end
            if ((ea_mode >= 2) && (ea_mode <= 6)) begin
                set_instruction_word(cursor,
                    16'(16'h207c | (ea_register << 9)));
                set_instruction_word(cursor + 2, 16'h0000);
                set_instruction_word(cursor + 4, base_address[15:0]);
                cursor = cursor + 6;
            end
            set_instruction_word(cursor, 16'h44fc); // MOVE.W #$15,CCR
            set_instruction_word(cursor + 2, 16'h0015);
            cursor = cursor + 4;

            instruction_pc = cursor;
            opcode = operation_base(operation) |
                     16'(destination_register << 9) |
                     16'(ea_mode << 3) | 16'(ea_register);
            set_instruction_word(cursor, opcode);
            cursor = cursor + 2;
            extension_pc = cursor;
            if (ea_mode == 5) begin
                set_instruction_word(cursor, 16'h0000);
                cursor = cursor + 2;
            end else if (ea_mode == 6) begin
                set_instruction_word(cursor,
                    16'((helper_register << 12) | 16'h0000));
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 0)) begin
                set_instruction_word(cursor, base_address[15:0]);
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(cursor, 16'h0000);
                set_instruction_word(cursor + 2, base_address[15:0]);
                cursor = cursor + 4;
            end else if ((ea_mode == 7) && (ea_register == 2)) begin
                set_instruction_word(cursor,
                    16'(base_address - extension_pc));
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 3)) begin
                effective_address = 16'h0180;
                set_instruction_word(cursor,
                    16'((helper_register << 12) |
                        ((effective_address - extension_pc) & 8'hff)));
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 4)) begin
                set_instruction_word(cursor, source);
                cursor = cursor + 2;
            end
            set_instruction_word(cursor, 16'h4e72);
            set_instruction_word(cursor + 2, 16'h2700);

            if (memory_source)
                set_data_word((ea_mode == 4) ? base_address - 2 :
                                                    effective_address,
                              source);
            if (ea_mode == 4)
                effective_address = base_address - 2;
            watched_address = effective_address;
            watch_enable = memory_source;
            repeat (2) @(negedge clk);
            rst_n = 1'b1;

            case_cycles = 0;
            while (!(retire_valid && (retire_pc == instruction_pc))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 600)
                    $fatal(1,
                        "MUL/DIV timeout: op=%0d D=%0d ea=%0d/%0d opcode=%04x",
                        operation, destination_register, ea_mode,
                        ea_register, opcode);
            end

            assert (retire_instruction_id == operation_id(operation));
            assert (debug_data_registers[
                        destination_register*32 +: 32] == expected_result)
                else $fatal(1,
                    "MUL/DIV result: op=%0d D=%0d ea=%0d/%0d opcode=%04x got=%08x expected=%08x",
                    operation, destination_register, ea_mode, ea_register,
                    opcode,
                    debug_data_registers[destination_register*32 +: 32],
                    expected_result);
            assert (debug_sr == expected_sr)
                else $fatal(1,
                    "MUL/DIV SR: op=%0d D=%0d ea=%0d/%0d got=%04x expected=%04x",
                    operation, destination_register, ea_mode, ea_register,
                    debug_sr, expected_sr);
            if (memory_source) begin
                assert (get_data_word(effective_address) == source);
                assert (target_accesses == 1);
                assert (target_command == MX_MEM_READ);
            end else
                assert (target_accesses == 0);
            if ((ea_mode >= 2) && (ea_mode <= 6))
                assert (debug_address_registers[ea_register*32 +: 32] ==
                    ((ea_mode == 3) ? base_address + 2 :
                     (ea_mode == 4) ? base_address - 2 : base_address));

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        for (int operation = 0; operation < 4; operation++)
            for (int destination_register = 0;
                 destination_register < 8; destination_register++) begin
                run_case(operation, destination_register, 0, 0);
                for (int ea_register = 1; ea_register < 8; ea_register++)
                    run_case(operation, destination_register, 0,
                             ea_register);
                for (int ea_mode = 2; ea_mode <= 6; ea_mode++)
                    for (int ea_register = 0; ea_register < 8;
                         ea_register++)
                        run_case(operation, destination_register, ea_mode,
                                 ea_register);
                for (int ea_register = 0; ea_register <= 4; ea_register++)
                    run_case(operation, destination_register, 7,
                             ea_register);
            end

        $display("PASS: all 1696 legal M00 MULU/MULS/DIVU/DIVS words");
        $finish;
    end
endmodule
