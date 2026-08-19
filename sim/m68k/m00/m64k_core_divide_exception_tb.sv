module m64k_core_divide_exception_tb;
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

    m64k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    m64k_ram #(.MEM_BYTES(1024)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
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

    task automatic run_nonzero_case(
        input logic signed_operation,
        input logic [31:0] dividend,
        input logic [15:0] divisor,
        input logic expected_overflow,
        input logic [31:0] expected_result,
        input logic expected_n,
        input logic expected_z
    );
        integer case_cycles;
        logic [15:0] opcode;
        begin
            opcode = signed_operation ? 16'h81fc : 16'h80fc;
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0300);
            set_data_long(4, 32'h0000_0100);
            set_instruction_word(16'h100, 16'h203c); // MOVE.L #value,D0
            set_instruction_word(16'h102, dividend[31:16]);
            set_instruction_word(16'h104, dividend[15:0]);
            set_instruction_word(16'h106, 16'h44fc); // MOVE.W #$15,CCR
            set_instruction_word(16'h108, 16'h0015);
            set_instruction_word(16'h10a, opcode);
            set_instruction_word(16'h10c, divisor);
            set_instruction_word(16'h10e, 16'h4e72);
            set_instruction_word(16'h110, 16'h2700);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_010a))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 300)
                    $fatal(1, "divide boundary case timed out");
            end

            assert (retire_instruction_id ==
                    (signed_operation ? M64K_INSN_DIVS : M64K_INSN_DIVU));
            assert (debug_data_registers[0*32 +: 32] ==
                    (expected_overflow ? dividend : expected_result));
            assert (debug_sr[M64K_SR_X] == 1'b1);
            assert (debug_sr[M64K_SR_V] == expected_overflow);
            assert (debug_sr[M64K_SR_C] == 1'b0);
            if (!expected_overflow) begin
                assert (debug_sr[M64K_SR_N] == expected_n);
                assert (debug_sr[M64K_SR_Z] == expected_z);
            end
            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    task automatic run_zero_case(input logic signed_operation);
        integer case_cycles;
        logic [15:0] opcode;
        logic [31:0] dividend;
        begin
            opcode = signed_operation ? 16'h81fc : 16'h80fc;
            dividend = signed_operation ? 32'hffff_ff9c : 32'h1234_5678;
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0300);
            set_data_long(4, 32'h0000_0100);
            set_data_long(M64K_VECTOR_ZERO_DIVIDE * 4, 32'h0000_0180);
            set_instruction_word(16'h100, 16'h203c);
            set_instruction_word(16'h102, dividend[31:16]);
            set_instruction_word(16'h104, dividend[15:0]);
            set_instruction_word(16'h106, 16'h44fc); // XNZVC all set
            set_instruction_word(16'h108, 16'h001f);
            set_instruction_word(16'h10a, opcode);
            set_instruction_word(16'h10c, 16'h0000);
            set_instruction_word(16'h10e, 16'h7000); // must not execute
            set_instruction_word(16'h180, 16'h4e72);
            set_instruction_word(16'h182, 16'h2700);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(stopped || faulted)) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 300)
                    $fatal(1, "divide-by-zero exception timed out");
            end
            repeat (2) @(negedge clk);

            // PRM 4-92/4-96: zero divisor takes vector 5.  The M00 group-2
            // frame contains the unchanged SR and the PC after the complete
            // immediate instruction; Dn is not modified.
            assert (stopped && !faulted && !terminal_exception.valid);
            assert (debug_data_registers[0*32 +: 32] == dividend);
            assert (debug_ssp == 32'h0000_02fa);
            assert ({data_ram.storage[16'h2fa],
                     data_ram.storage[16'h2fb]} == 16'h271e);
            assert ({data_ram.storage[16'h2fc], data_ram.storage[16'h2fd],
                     data_ram.storage[16'h2fe], data_ram.storage[16'h2ff]} ==
                    32'h0000_010e);
        end
    endtask

    initial begin
        rst_n = 1'b0;

        // Unsigned quotient boundary: $ffff fits, $10000 overflows.
        run_nonzero_case(1'b0, 32'h0000_ffff, 16'h0001, 1'b0,
                         32'h0000_ffff, 1'b1, 1'b0);
        run_nonzero_case(1'b0, 32'h0001_0000, 16'h0001, 1'b1,
                         32'd0, 1'b0, 1'b0);

        // Signed quotient boundaries and remainder sign follow PRM 4-91.
        run_nonzero_case(1'b1, 32'h0000_7fff, 16'h0001, 1'b0,
                         32'h0000_7fff, 1'b0, 1'b0);
        run_nonzero_case(1'b1, 32'hffff_8000, 16'h0001, 1'b0,
                         32'h0000_8000, 1'b1, 1'b0);
        run_nonzero_case(1'b1, 32'h0000_8000, 16'h0001, 1'b1,
                         32'd0, 1'b0, 1'b0);
        run_nonzero_case(1'b1, 32'hffff_7fff, 16'h0001, 1'b1,
                         32'd0, 1'b0, 1'b0);
        run_nonzero_case(1'b1, 32'h8000_0000, 16'hffff, 1'b1,
                         32'd0, 1'b0, 1'b0);
        run_nonzero_case(1'b1, 32'hffff_fff9, 16'h0003, 1'b0,
                         32'hffff_fffe, 1'b1, 1'b0);
        run_nonzero_case(1'b1, 32'h0000_0007, 16'hfffd, 1'b0,
                         32'h0001_fffe, 1'b1, 1'b0);

        run_zero_case(1'b0);
        run_zero_case(1'b1);

        $display("PASS: DIVU/DIVS boundaries, overflow preservation and vector 5");
        $finish;
    end
endmodule
