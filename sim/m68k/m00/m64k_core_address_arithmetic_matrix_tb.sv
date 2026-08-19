module m64k_core_address_arithmetic_matrix_tb;
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
    m64k_mem_command_t target_command;

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
    m64k_ram #(.MEM_BYTES(2048)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            target_accesses <= 0;
            target_command <= M64K_MEM_READ;
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

    task automatic store_operand(input integer address,
                                 input integer size_index,
                                 input logic [31:0] value);
        if (size_index == 0) begin
            data_ram.storage[address] = value[15:8];
            data_ram.storage[address + 1] = value[7:0];
        end else
            set_data_long(address, value);
    endtask

    function automatic logic [31:0] load_operand(input integer address,
                                                  input integer size_index);
        if (size_index == 0)
            return {16'd0, data_ram.storage[address],
                    data_ram.storage[address + 1]};
        return {data_ram.storage[address], data_ram.storage[address + 1],
                data_ram.storage[address + 2],
                data_ram.storage[address + 3]};
    endfunction

    function automatic integer operand_step(input integer size_index);
        return (size_index == 0) ? 2 : 4;
    endfunction

    function automatic logic [3:0] operation_nibble(input integer operation);
        case (operation)
            0: return 4'hd;
            1: return 4'h9;
            default: return 4'hb;
        endcase
    endfunction

    function automatic logic [7:0] operation_id(input integer operation,
                                                 input integer size_index);
        case (operation)
            0: return size_index ? M64K_INSN_ADDA_L : M64K_INSN_ADDA_W;
            1: return size_index ? M64K_INSN_SUBA_L : M64K_INSN_SUBA_W;
            default: return size_index ? M64K_INSN_CMPA_L : M64K_INSN_CMPA_W;
        endcase
    endfunction

    function automatic logic [15:0] compare_sr(
        input logic [15:0] old_sr,
        input logic [31:0] destination,
        input logic [31:0] source
    );
        logic [15:0] value;
        logic [31:0] result;
        begin
            value = old_sr;
            result = destination - source;
            value[M64K_SR_N] = result[31];
            value[M64K_SR_Z] = (result == 0);
            value[M64K_SR_V] = (destination[31] != source[31]) &&
                             (result[31] != destination[31]);
            value[M64K_SR_C] = (destination < source);
            return value;
        end
    endfunction

    task automatic sample_values(input integer scenario,
                                 input integer size_index,
                                 output logic [31:0] destination,
                                 output logic [31:0] source);
        begin
            case (scenario & 7)
                0: begin destination = 32'd0; source = 32'd0; end
                1: begin destination = 32'hffff_ffff; source = 32'd1; end
                2: begin destination = 32'h7fff_ffff; source = 32'd1; end
                3: begin destination = 32'h8000_0000; source = 32'd1; end
                4: begin destination = 32'd0; source = 32'd1; end
                5: begin destination = 32'd1; source = 32'hffff_ffff; end
                6: begin
                    destination = 32'h5555_5555;
                    source = 32'haaaa_aaaa;
                end
                default: begin
                    destination = 32'hffff_ffff;
                    source = 32'hffff_ffff;
                end
            endcase
            if (size_index == 0)
                source = {16'ha55a, source[15:0]};
        end
    endtask

    task automatic run_address_case(input integer operation,
                                    input integer size_index,
                                    input integer destination_register,
                                    input integer ea_mode,
                                    input integer ea_register);
        integer base_address;
        integer effective_address;
        integer source_setup_register;
        integer cursor;
        integer case_cycles;
        logic memory_source;
        logic same_address_register;
        logic [31:0] destination;
        logic [31:0] source;
        logic [31:0] source_operand;
        logic [31:0] arithmetic_destination;
        logic [31:0] expected_destination;
        logic [31:0] expected_source_address;
        logic [15:0] expected_sr;
        logic [15:0] opcode;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            memory_source = ((ea_mode >= 2) && (ea_mode <= 6)) ||
                            ((ea_mode == 7) && (ea_register <= 3));
            same_address_register = (ea_mode >= 1) && (ea_mode <= 6) &&
                                    (ea_register == destination_register);
            sample_values(operation * 13 + size_index * 7 +
                          destination_register * 3 + ea_mode + ea_register,
                          size_index, destination, source);

            if (same_address_register) begin
                if (ea_mode == 1)
                    destination = source;
                else
                    destination = base_address;
            end

            if ((ea_mode == 7) && (ea_register == 3))
                effective_address = 16'h0180;
            source_operand = (size_index == 0) ?
                {{16{source[15]}}, source[15:0]} : source;
            arithmetic_destination = destination;
            expected_source_address = base_address;
            if (ea_mode == 3) begin
                expected_source_address = base_address +
                                          operand_step(size_index);
                if (same_address_register)
                    arithmetic_destination = expected_source_address;
            end else if (ea_mode == 4) begin
                effective_address = base_address - operand_step(size_index);
                expected_source_address = effective_address;
                if (same_address_register)
                    arithmetic_destination = expected_source_address;
            end

            case (operation)
                0: expected_destination = arithmetic_destination +
                                              source_operand;
                1: expected_destination = arithmetic_destination -
                                              source_operand;
                default: expected_destination = same_address_register &&
                    ((ea_mode == 3) || (ea_mode == 4)) ?
                    expected_source_address : destination;
            endcase
            expected_sr = (operation == 2) ?
                compare_sr(16'h2715, arithmetic_destination,
                           source_operand) : 16'h2715;

            rst_n = 1'b0;
            watch_enable = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0780);
            set_data_long(4, 32'h0000_0100);

            set_instruction_word(16'h100, 16'h2c3c); // MOVE.L #0,D6
            set_instruction_word(16'h102, 16'h0000);
            set_instruction_word(16'h104, 16'h0000);
            if (ea_mode == 0) begin
                set_instruction_word(16'h106,
                    16'(16'h203c | (ea_register << 9)));
                set_instruction_word(16'h108, source[31:16]);
                set_instruction_word(16'h10a, source[15:0]);
            end else begin
                source_setup_register = (ea_mode == 7) ? 5 : ea_register;
                set_instruction_word(16'h106,
                    16'(16'h207c | (source_setup_register << 9)));
                set_instruction_word(16'h108,
                    (ea_mode == 1) ? source[31:16] : 16'h0000);
                set_instruction_word(16'h10a,
                    (ea_mode == 1) ? source[15:0] :
                    ((ea_mode == 7) ? 16'h0000 : base_address[15:0]));
            end
            set_instruction_word(16'h10c,
                16'(16'h207c | (destination_register << 9)));
            set_instruction_word(16'h10e, destination[31:16]);
            set_instruction_word(16'h110, destination[15:0]);
            set_instruction_word(16'h112, 16'h44fc); // MOVE.W #ccr,CCR
            set_instruction_word(16'h114, 16'h0015);

            opcode = {operation_nibble(operation),
                      destination_register[2:0], size_index[0], 2'b11,
                      ea_mode[2:0], ea_register[2:0]};
            set_instruction_word(16'h116, opcode);
            cursor = 16'h118;
            if (ea_mode == 5) begin
                set_instruction_word(cursor, 16'h0000);
                cursor = cursor + 2;
            end else if (ea_mode == 6) begin
                set_instruction_word(cursor, 16'h6000); // D6.W + disp 0
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 0)) begin
                set_instruction_word(cursor, base_address[15:0]);
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(cursor, 16'h0000);
                set_instruction_word(cursor + 2, base_address[15:0]);
                cursor = cursor + 4;
            end else if ((ea_mode == 7) && (ea_register == 2)) begin
                set_instruction_word(cursor, 16'h0108); // $220 - $118
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 3)) begin
                set_instruction_word(cursor, 16'h6068); // D6.W + $68
                cursor = cursor + 2;
            end else if ((ea_mode == 7) && (ea_register == 4)) begin
                if (size_index == 0) begin
                    set_instruction_word(cursor, source[15:0]);
                    cursor = cursor + 2;
                end else begin
                    set_instruction_word(cursor, source[31:16]);
                    set_instruction_word(cursor + 2, source[15:0]);
                    cursor = cursor + 4;
                end
            end
            set_instruction_word(cursor, 16'h4e72);
            set_instruction_word(cursor + 2, 16'h2700);

            if (memory_source)
                store_operand(effective_address, size_index, source);
            watched_address = effective_address;
            watch_enable = memory_source;
            repeat (2) @(negedge clk);
            rst_n = 1'b1;

            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_0116))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 500)
                    $fatal(1,
                        "address arithmetic timeout: op=%0d size=%0d A=%0d ea=%0d/%0d",
                        operation, size_index, destination_register,
                        ea_mode, ea_register);
            end

            assert (retire_instruction_id ==
                    operation_id(operation, size_index));
            assert (debug_address_registers[
                        destination_register*32 +: 32] ==
                    expected_destination)
                else $fatal(1,
                    "address arithmetic result: op=%0d size=%0d A=%0d ea=%0d/%0d opcode=%04x got=%08x expected=%08x",
                    operation, size_index, destination_register, ea_mode,
                    ea_register, opcode,
                    debug_address_registers[destination_register*32 +: 32],
                    expected_destination);
            assert (debug_sr == expected_sr);
            if (memory_source) begin
                assert (load_operand(effective_address, size_index) ==
                        ((size_index == 0) ? {16'd0, source[15:0]} : source));
                assert (target_accesses == 1);
                assert (target_command == M64K_MEM_READ);
            end else
                assert (target_accesses == 0);
            if ((ea_mode >= 1) && (ea_mode <= 6) &&
                (ea_register != destination_register))
                assert (debug_address_registers[ea_register*32 +: 32] ==
                        ((ea_mode inside {3, 4}) ? expected_source_address :
                                                   ((ea_mode == 1) ? source :
                                                                     base_address)));

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        for (int operation = 0; operation < 3; operation++)
            for (int size_index = 0; size_index < 2; size_index++)
                for (int destination_register = 0;
                     destination_register < 8; destination_register++) begin
                    for (int ea_mode = 0; ea_mode <= 6; ea_mode++)
                        for (int ea_register = 0; ea_register < 8;
                             ea_register++)
                            run_address_case(operation, size_index,
                                             destination_register, ea_mode,
                                             ea_register);
                    for (int ea_register = 0; ea_register <= 4; ea_register++)
                        run_address_case(operation, size_index,
                                         destination_register, 7,
                                         ea_register);
                end

        $display("PASS: all 2928 legal M00 ADDA/SUBA/CMPA words");
        $finish;
    end
endmodule
