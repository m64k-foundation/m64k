module m64k_core_sr_matrix_tb;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;
    import m64k_m00_decode_table_pkg::*;

    localparam int MOVE_TO_CCR = 0;
    localparam int MOVE_TO_SR = 1;
    localparam int MOVE_FROM_SR = 2;

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

    task automatic set_data_word(input integer address,
                                 input logic [15:0] value);
        data_ram.storage[address] = value[15:8];
        data_ram.storage[address + 1] = value[7:0];
    endtask

    function automatic logic [15:0] get_data_word(input integer address);
        return {data_ram.storage[address], data_ram.storage[address + 1]};
    endfunction

    function automatic integer extension_words(input integer ea_mode,
                                                input integer ea_register);
        if ((ea_mode == 5) || (ea_mode == 6))
            return 1;
        if (ea_mode != 7)
            return 0;
        if (ea_register == 1)
            return 2;
        return 1;
    endfunction

    task automatic run_sr_case(input integer operation,
                               input integer ea_mode,
                               input integer ea_register);
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer extension_count;
        integer stop_pc;
        integer case_cycles;
        logic [15:0] opcode;
        logic [15:0] source_word;
        logic [15:0] initial_sr;
        logic [15:0] expected_sr;
        logic [31:0] initial_data_register;
        logic [31:0] observed_data_register;
        logic [31:0] observed_address_register;
        logic [31:0] expected_data_register;
        logic [7:0] expected_instruction_id;
        begin
            // Motorola M68000 Family Programmer's Reference Manual (1992),
            // MOVE to CCR pp. 4-123--4-124, MOVE from SR p. 4-125, and
            // MOVE to SR pp. 6-19--6-20. Source forms use data addressing;
            // MOVE from SR uses word data-alterable destinations. The
            // MC68000 User's Manual, Ninth Edition (1993), table 7-13,
            // confirms the memory read and write counts.
            base_address = 16'h0180;
            effective_address = base_address;
            expected_address = base_address;
            extension_count = extension_words(ea_mode, ea_register);
            initial_data_register = 32'ha5a5_5a5a;
            case (operation)
                MOVE_TO_CCR: begin
                    opcode = 16'(16'h44c0 | (ea_mode << 3) | ea_register);
                    source_word = 16'ha5d5;
                    initial_sr = 16'h2700;
                    expected_sr = 16'h2715;
                    expected_instruction_id = M64K_INSN_MOVE_TO_CCR;
                end
                MOVE_TO_SR: begin
                    opcode = 16'(16'h46c0 | (ea_mode << 3) | ea_register);
                    source_word = 16'h2515;
                    initial_sr = 16'h2700;
                    expected_sr = 16'h2515;
                    expected_instruction_id = M64K_INSN_MOVE_TO_SR;
                end
                default: begin
                    opcode = 16'(16'h40c0 | (ea_mode << 3) | ea_register);
                    source_word = 16'h2515;
                    initial_sr = 16'h2515;
                    expected_sr = 16'h2515;
                    expected_instruction_id = M64K_INSN_MOVE_FROM_SR;
                end
            endcase

            if (ea_mode == 3)
                expected_address = base_address + 2;
            else if (ea_mode == 4) begin
                effective_address = base_address - 2;
                expected_address = effective_address;
            end

            rst_n = 1'b0;
            watch_enable = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);

            if (ea_mode == 0) begin
                set_instruction_word(16'h100,
                    16'(16'h203c | (ea_register << 9)));
                set_instruction_word(16'h102,
                    (operation == MOVE_FROM_SR) ?
                        initial_data_register[31:16] : 16'ha5a5);
                set_instruction_word(16'h104,
                    (operation == MOVE_FROM_SR) ?
                        initial_data_register[15:0] : source_word);
            end else begin
                // Keep the target opcode at a fixed PC for PC-relative forms.
                set_instruction_word(16'h100,
                    16'(16'h207c | (((ea_mode inside {2, 3, 4, 5, 6}) ?
                                      ea_register : 0) << 9)));
                set_instruction_word(16'h102, 16'h0000);
                set_instruction_word(16'h104, base_address[15:0]);
                if ((ea_mode != 7) || (ea_register != 4))
                    set_data_word(effective_address,
                        (operation == MOVE_FROM_SR) ? 16'ha55a : source_word);
            end

            set_instruction_word(16'h106, 16'h46fc);
            set_instruction_word(16'h108, initial_sr);
            set_instruction_word(16'h10a, opcode);
            if ((ea_mode == 5) || (ea_mode == 6))
                set_instruction_word(16'h10c, 16'h0000);
            else if ((ea_mode == 7) && (ea_register == 0))
                set_instruction_word(16'h10c, base_address[15:0]);
            else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(16'h10c, 16'h0000);
                set_instruction_word(16'h10e, base_address[15:0]);
            end else if ((ea_mode == 7) && (ea_register inside {2, 3}))
                set_instruction_word(16'h10c,
                    16'(base_address - 16'h010c));
            else if ((ea_mode == 7) && (ea_register == 4))
                set_instruction_word(16'h10c, source_word);

            stop_pc = 16'h10c + 2 * extension_count;
            set_instruction_word(stop_pc, 16'h4e72);
            set_instruction_word(stop_pc + 2, 16'h2700);

            watched_address = effective_address;
            watch_enable = (ea_mode != 0) &&
                           !((ea_mode == 7) && (ea_register == 4));
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_010a))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 500)
                    $fatal(1,
                        "SR matrix timeout: operation=%0d ea=%0d/%0d",
                        operation, ea_mode, ea_register);
            end

            assert (retire_instruction_id == expected_instruction_id);
            assert (debug_sr == expected_sr);
            observed_data_register = debug_data_registers >>
                                     (ea_register * 32);
            observed_address_register = debug_address_registers >>
                                        (ea_register * 32);
            if (ea_mode == 0) begin
                if (operation == MOVE_FROM_SR)
                    expected_data_register =
                        {initial_data_register[31:16], initial_sr};
                else
                    expected_data_register = {16'ha5a5, source_word};
                assert (observed_data_register == expected_data_register);
                assert (target_accesses == 0);
            end else if ((ea_mode == 7) && (ea_register == 4)) begin
                assert (operation != MOVE_FROM_SR);
                assert (target_accesses == 0);
            end else begin
                if (operation == MOVE_FROM_SR) begin
                    assert (get_data_word(effective_address) == initial_sr);
                    assert (target_accesses == 2);
                    assert (target_commands[0] == M64K_MEM_READ);
                    assert (target_commands[1] == M64K_MEM_WRITE);
                end else begin
                    assert (get_data_word(effective_address) == source_word);
                    assert (target_accesses == 1);
                    assert (target_commands[0] == M64K_MEM_READ);
                end
                if (ea_mode inside {2, 3, 4, 5, 6})
                    assert (observed_address_register == expected_address);
            end

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        watch_enable = 1'b0;
        watched_address = '0;

        for (int operation = MOVE_TO_CCR; operation <= MOVE_TO_SR;
             operation++) begin
            for (int register_index = 0; register_index < 8;
                 register_index++)
                run_sr_case(operation, 0, register_index);
            for (int mode_index = 2; mode_index <= 6; mode_index++)
                for (int register_index = 0; register_index < 8;
                     register_index++)
                    run_sr_case(operation, mode_index, register_index);
            for (int register_index = 0; register_index <= 4;
                 register_index++)
                run_sr_case(operation, 7, register_index);
        end

        for (int register_index = 0; register_index < 8; register_index++)
            run_sr_case(MOVE_FROM_SR, 0, register_index);
        for (int mode_index = 2; mode_index <= 6; mode_index++)
            for (int register_index = 0; register_index < 8;
                 register_index++)
                run_sr_case(MOVE_FROM_SR, mode_index, register_index);
        run_sr_case(MOVE_FROM_SR, 7, 0);
        run_sr_case(MOVE_FROM_SR, 7, 1);

        $display("PASS: all 53 MOVE-to-CCR, 53 MOVE-to-SR and 50 MOVE-from-SR M00 words");
        $finish;
    end
endmodule
