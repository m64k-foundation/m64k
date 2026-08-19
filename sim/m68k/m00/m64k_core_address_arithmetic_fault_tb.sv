module m64k_core_address_arithmetic_fault_tb;
    import m64k_arch_pkg::*;

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
        .INJECT_FAULT_READ_ADDR(32'h0000_0200)
    ) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 4000)
                $fatal(1, "address arithmetic fault matrix timed out");
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

    function automatic logic [3:0] operation_nibble(input integer operation);
        return (operation == 0) ? 4'hd :
               (operation == 1) ? 4'h9 : 4'hb;
    endfunction

    task automatic initialize_exception_state(input logic [31:0] start_pc,
                                               input logic [15:0] handler_sr);
        begin
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, start_pc);
            set_data_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);
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
            assert (debug_pc == 32'h0000_0184);
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

    task automatic run_extension_fault(input integer operation,
                                       input logic second_word);
        logic [31:0] start_pc;
        logic [15:0] opcode;
        begin
            start_pc = second_word ? 32'h0000_01ec : 32'h0000_01ee;
            opcode = {operation_nibble(operation), 3'd1, 1'b1, 2'b11,
                      3'd7, second_word ? 3'd1 : 3'd0};
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(start_pc, 16'h2700);
            set_instruction_word(start_pc, opcode);
            if (second_word)
                set_instruction_word(16'h1ee, 16'h0000);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            assert (debug_address_registers[1*32 +: 32] == 32'd0);
            check_group0_frame(16'h0016, 32'h0000_01f0, opcode,
                               16'h2700, 32'h0000_01f0);
        end
    endtask

    task automatic run_data_fault(input integer operation,
                                  input integer size_index);
        logic [15:0] opcode;
        logic [31:0] destination;
        begin
            destination = 32'h1234_5678;
            opcode = {operation_nibble(operation), 3'd1, size_index[0],
                      2'b11, 3'd3, 3'd0}; // ADDA/SUBA/CMPA (A0)+,A1
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(32'h0000_0100, 16'h271f);
            set_instruction_word(16'h100, 16'h207c); // MOVEA.L #$200,A0
            set_instruction_word(16'h102, 16'h0000);
            set_instruction_word(16'h104, 16'h0200);
            set_instruction_word(16'h106, 16'h227c); // MOVEA.L #dest,A1
            set_instruction_word(16'h108, destination[31:16]);
            set_instruction_word(16'h10a, destination[15:0]);
            set_instruction_word(16'h10c, 16'h44fc); // MOVE.W #$1f,CCR
            set_instruction_word(16'h10e, 16'h001f);
            set_instruction_word(16'h110, opcode);
            set_instruction_word(16'h112, 16'h4e72); // must not execute
            set_instruction_word(16'h114, 16'h271f);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            assert (debug_address_registers[0*32 +: 32] == 32'h0000_0200);
            assert (debug_address_registers[1*32 +: 32] == destination);
            assert (debug_sr == 16'h271f); // handler STOP value
            check_group0_frame(16'h001d, 32'h0000_0200, opcode,
                               16'h271f, 32'h0000_0112);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;

        for (int operation = 0; operation < 3; operation++) begin
            run_extension_fault(operation, 1'b0);
            run_extension_fault(operation, 1'b1);
            run_data_fault(operation, 0);
            run_data_fault(operation, 1);
        end

        $display("PASS: ADDA/SUBA/CMPA extension and operand-read faults");
        $finish;
    end
endmodule
