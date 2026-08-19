module m64k_core_binary_fault_tb;
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
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 4000)
                $fatal(1, "binary fault matrix timed out");
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

    function automatic logic [3:0] source_operation_nibble(
        input integer operation
    );
        case (operation)
            0: return 4'hd; // ADD
            1: return 4'h9; // SUB
            2: return 4'hc; // AND
            3: return 4'h8; // OR
            default: return 4'hb; // CMP
        endcase
    endfunction

    function automatic logic [3:0] destination_operation_nibble(
        input integer operation
    );
        case (operation)
            0: return 4'hd; // ADD
            1: return 4'h9; // SUB
            2: return 4'hc; // AND
            3: return 4'h8; // OR
            default: return 4'hb; // EOR
        endcase
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

    task automatic run_extension_fault(input logic destination_direction,
                                       input integer operation);
        logic [15:0] opcode;
        begin
            opcode = {destination_direction ?
                      destination_operation_nibble(operation) :
                      source_operation_nibble(operation),
                      3'd0, destination_direction, 2'b00,
                      3'd7, 3'd0}; // .B D0,$abs.w or $abs.w,D0
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(32'h0000_01ee, 16'h2700);
            set_instruction_word(16'h1ee, opcode);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            check_group0_frame(16'h0016, 32'h0000_01f0, opcode,
                               16'h2700, 32'h0000_01f0);
        end
    endtask

    task automatic run_data_fault(input logic destination_direction,
                                  input integer operation,
                                  input logic write_fault);
        integer operand_address;
        logic [15:0] opcode;
        logic [15:0] expected_ssw;
        begin
            operand_address = write_fault ? 16'h0220 : 16'h0200;
            opcode = {destination_direction ?
                      destination_operation_nibble(operation) :
                      source_operation_nibble(operation),
                      3'd0, destination_direction, 2'b00,
                      3'd3, 3'd0}; // byte D0,(A0)+ or (A0)+,D0
            expected_ssw = write_fault ? 16'h000d : 16'h001d;

            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            initialize_exception_state(32'h0000_0100, 16'h271f);
            set_instruction_word(16'h100, 16'h203c); // MOVE.L #1,D0
            set_instruction_word(16'h102, 16'h0000);
            set_instruction_word(16'h104, 16'h0001);
            set_instruction_word(16'h106, 16'h207c); // MOVEA.L #operand,A0
            set_instruction_word(16'h108, 16'h0000);
            set_instruction_word(16'h10a, operand_address[15:0]);
            set_instruction_word(16'h10c, 16'h44fc); // MOVE.W #$1f,CCR
            set_instruction_word(16'h10e, 16'h001f);
            set_instruction_word(16'h110, opcode);
            set_instruction_word(16'h112, 16'h4e72); // must not execute
            set_instruction_word(16'h114, 16'h271f);
            data_ram.storage[operand_address] = 8'h80;

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            assert (debug_data_registers[0*32 +: 32] == 32'h0000_0001);
            assert (debug_address_registers[0*32 +: 32] ==
                    32'(operand_address));
            assert (data_ram.storage[operand_address] == 8'h80);
            check_group0_frame(expected_ssw, 32'(operand_address), opcode,
                               16'h271f, 32'h0000_0112);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;

        for (int operation = 0; operation < 5; operation++) begin
            run_extension_fault(1'b0, operation);
            run_extension_fault(1'b1, operation);
            run_data_fault(1'b0, operation, 1'b0);
            run_data_fault(1'b1, operation, 1'b0);
            run_data_fault(1'b1, operation, 1'b1);
        end

        $display("PASS: binary source/destination fetch and RMW faults");
        $finish;
    end
endmodule
