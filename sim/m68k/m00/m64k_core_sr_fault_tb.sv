module m64k_core_sr_fault_tb;
    import m64k_arch_pkg::*;

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
    integer cycles;
    integer protected_operand_accesses;

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

    // Fetch is line based. The opcode at $1ee is in the preceding line and
    // its EA extension at $1f0 is the first word of the faulting line.
    m64k_ram #(
        .MEM_BYTES(512),
        .INJECT_FAULT_ENABLE(1'b1),
        .INJECT_FAULT_READ(1'b1),
        .INJECT_FAULT_READ_ADDR(32'h0000_01f0)
    ) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    m64k_ram #(
        .MEM_BYTES(1024),
        .INJECT_FAULT_ENABLE(1'b1),
        .INJECT_FAULT_READ(1'b1),
        .INJECT_FAULT_WRITE(1'b1),
        .INJECT_FAULT_READ_ADDR(32'h0000_0200),
        .INJECT_FAULT_WRITE_ADDR(32'h0000_0220)
    ) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            protected_operand_accesses <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr == 32'h0000_0240))
                protected_operand_accesses <= protected_operand_accesses + 1;
            if (cycles > 4000)
                $fatal(1, "SR fault matrix timed out");
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

    task automatic initialize_exception_state(input logic [31:0] start_pc,
                                               input logic [15:0] handler_sr);
        begin
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, start_pc);
            set_data_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);
            set_data_long(M64K_VECTOR_PRIVILEGE * 4, 32'h0000_0180);
            for (int stack_index = 16'h370; stack_index < 16'h380;
                 stack_index++)
                data_ram.storage[stack_index] = 8'h00;
            set_instruction_word(16'h180, 16'h4e72);
            set_instruction_word(16'h182, handler_sr);
        end
    endtask

    task automatic check_group0_frame(input logic [15:0] expected_ssw,
                                      input logic [31:0] expected_address,
                                      input logic [15:0] expected_opcode,
                                      input logic [15:0] expected_sr,
                                      input logic [31:0] expected_pc);
        begin
            assert (stopped && !faulted && !terminal_exception.valid);
            assert (debug_ssp == 32'h0000_0372);
            assert ({data_ram.storage[16'h372],
                     data_ram.storage[16'h373]} == expected_ssw);
            assert ({data_ram.storage[16'h374], data_ram.storage[16'h375],
                     data_ram.storage[16'h376], data_ram.storage[16'h377]} ==
                    expected_address);
            assert ({data_ram.storage[16'h378],
                     data_ram.storage[16'h379]} == expected_opcode);
            assert ({data_ram.storage[16'h37a],
                     data_ram.storage[16'h37b]} == expected_sr);
            assert ({data_ram.storage[16'h37c], data_ram.storage[16'h37d],
                     data_ram.storage[16'h37e], data_ram.storage[16'h37f]} ==
                    expected_pc);
        end
    endtask

    function automatic logic [15:0] operation_base(input integer operation);
        case (operation)
            MOVE_TO_CCR: return 16'h44c0;
            MOVE_TO_SR: return 16'h46c0;
            default: return 16'h40c0;
        endcase
    endfunction

    task automatic run_extension_fault(input integer operation);
        logic [15:0] opcode;
        begin
            opcode = operation_base(operation) | 16'h0028; // d16(A0)
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(32'h0000_01ee, 16'h2700);
            set_instruction_word(16'h1ee, opcode);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            // MC68000UM 6.3.9.1 and figure 6-7: supervisor program read is
            // R/W=1, I/N=0, FC=110, hence SSW $0016.
            check_group0_frame(16'h0016, 32'h0000_01f0, opcode,
                               16'h2700, 32'h0000_01f0);
        end
    endtask

    task automatic run_data_fault(input integer operation,
                                  input logic write_fault);
        integer operand_address;
        logic [15:0] opcode;
        logic [15:0] expected_ssw;
        begin
            operand_address = write_fault ? 16'h0220 : 16'h0200;
            opcode = operation_base(operation) | 16'h0018; // (A0)+
            expected_ssw = write_fault ? 16'h000d : 16'h001d;

            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(32'h0000_0100, 16'h2715);
            set_instruction_word(16'h100, 16'h207c);
            set_instruction_word(16'h102, 16'h0000);
            set_instruction_word(16'h104, operand_address[15:0]);
            set_instruction_word(16'h106, 16'h46fc);
            set_instruction_word(16'h108, 16'h2715);
            set_instruction_word(16'h10a, opcode);
            set_instruction_word(16'h10c, 16'h4e72);
            set_instruction_word(16'h10e, 16'h2700);
            data_ram.storage[operand_address] = 8'ha5;
            data_ram.storage[operand_address + 1] = 8'h15;

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            assert (debug_address_registers[31:0] == 32'(operand_address));
            assert ({data_ram.storage[operand_address],
                     data_ram.storage[operand_address + 1]} == 16'ha515);
            check_group0_frame(expected_ssw, 32'(operand_address), opcode,
                               16'h2715, 32'h0000_010c);
        end
    endtask

    task automatic run_user_privilege_case;
        begin
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(32'h0000_0100, 16'h2700);
            set_instruction_word(16'h100, 16'h207c);
            set_instruction_word(16'h102, 16'h0000);
            set_instruction_word(16'h104, 16'h0240);
            set_instruction_word(16'h106, 16'h46fc);
            set_instruction_word(16'h108, 16'h0015); // enter user mode
            set_instruction_word(16'h10a, 16'h46d8); // MOVE.W (A0)+,SR
            set_instruction_word(16'h10c, 16'h4e72); // must not execute
            set_instruction_word(16'h10e, 16'h2700);
            data_ram.storage[16'h240] = 8'h27;
            data_ram.storage[16'h241] = 8'h00;

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            assert (stopped && !faulted && !terminal_exception.valid);
            assert (protected_operand_accesses == 0);
            assert (debug_address_registers[31:0] == 32'h0000_0240);
            assert ({data_ram.storage[16'h37a],
                     data_ram.storage[16'h37b]} == 16'h0015);
            assert ({data_ram.storage[16'h37c], data_ram.storage[16'h37d],
                     data_ram.storage[16'h37e], data_ram.storage[16'h37f]} ==
                    32'h0000_010a);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        protected_operand_accesses = 0;

        for (int operation = MOVE_TO_CCR; operation <= MOVE_FROM_SR;
             operation++)
            run_extension_fault(operation);

        run_data_fault(MOVE_TO_CCR, 1'b0);
        run_data_fault(MOVE_TO_SR, 1'b0);
        run_data_fault(MOVE_FROM_SR, 1'b0);
        run_data_fault(MOVE_FROM_SR, 1'b1);
        run_user_privilege_case();

        $display("PASS: M00 SR/CCR extension, operand, RMW and privilege faults");
        $finish;
    end
endmodule
