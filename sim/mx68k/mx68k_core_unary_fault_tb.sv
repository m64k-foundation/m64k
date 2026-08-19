module mx68k_core_unary_fault_tb;
    import mx68k_arch_pkg::*;

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
    integer cycles;

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

    mx68k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(
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
            if (cycles > 3000)
                $fatal(1, "unary RMW fault test timed out");
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

    function automatic logic [15:0] unary_opcode(input integer unary_index);
        case (unary_index)
            0: return 16'h4218; // CLR.B (A0)+
            1: return 16'h4418; // NEG.B (A0)+
            default: return 16'h4618; // NOT.B (A0)+
        endcase
    endfunction

    task automatic run_fault_case(input integer unary_index,
                                  input logic write_fault);
        integer operand_address;
        logic [15:0] opcode;
        logic [15:0] expected_ssw;
        begin
            operand_address = write_fault ? 16'h0220 : 16'h0200;
            opcode = unary_opcode(unary_index);
            // MC68000UM 6.3.9.1 and figure 6-7: R/W=1 denotes the failed
            // read, I/N=1 denotes an operand cycle, and FC=101 is
            // supervisor data space.
            expected_ssw = write_fault ? 16'h000d : 16'h001d;

            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);
            set_data_long(MX_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);
            for (int stack_index = 16'h370; stack_index < 16'h380;
                 stack_index++)
                data_ram.storage[stack_index] = 8'h00;

            set_instruction_word(16'h100, 16'h44fc); // MOVE.W #$001f,CCR
            set_instruction_word(16'h102, 16'h001f);
            set_instruction_word(16'h104, 16'h207c); // MOVEA.L #operand,A0
            set_instruction_word(16'h106, 16'h0000);
            set_instruction_word(16'h108, operand_address[15:0]);
            set_instruction_word(16'h10a, opcode);
            set_instruction_word(16'h10c, 16'h4e72); // must not execute
            set_instruction_word(16'h10e, 16'h2700);
            set_instruction_word(16'h180, 16'h4e72); // vector-2 handler
            set_instruction_word(16'h182, 16'h271f);
            data_ram.storage[operand_address] = 8'h80;

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            assert (stopped && !faulted && !terminal_exception.valid);
            assert (debug_pc == 32'h0000_0184);
            assert (debug_address_registers[0*32 +: 32] ==
                    32'(operand_address));
            assert (data_ram.storage[operand_address] == 8'h80);

            // The failed operand transaction builds the complete M00
            // group-0 frame and commits none of the candidate RMW result,
            // postincrement, flags or following PC.
            assert (debug_ssp == 32'h0000_0372);
            assert ({data_ram.storage[16'h372],
                     data_ram.storage[16'h373]} == expected_ssw);
            assert ({data_ram.storage[16'h374], data_ram.storage[16'h375],
                     data_ram.storage[16'h376], data_ram.storage[16'h377]} ==
                    32'(operand_address));
            assert ({data_ram.storage[16'h378],
                     data_ram.storage[16'h379]} == opcode);
            assert ({data_ram.storage[16'h37a],
                     data_ram.storage[16'h37b]} == 16'h271f);
            assert ({data_ram.storage[16'h37c], data_ram.storage[16'h37d],
                     data_ram.storage[16'h37e], data_ram.storage[16'h37f]} ==
                    32'h0000_010c);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        for (int unary_index = 0; unary_index < 3; unary_index++) begin
            run_fault_case(unary_index, 1'b0);
            run_fault_case(unary_index, 1'b1);
        end

        $display("PASS: CLR/NEG/NOT read/write faults suppress all RMW commit");
        $finish;
    end
endmodule
