module m64k_core_line_cross_tb;
    import m64k_arch_pkg::*;

    logic clk;
    logic rst_n;
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
        .clk, .rst_n,
        .stopped, .faulted, .terminal_exception,
        .retire_valid, .retire_pc, .retire_instruction_id,
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp,
        .debug_data_registers, .debug_address_registers,
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

    integer cycles;
    integer retire_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retire_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (retire_valid)
                retire_count <= retire_count + 1;
            if (cycles > 5000)
                $fatal(1, "M64K line-crossing access test timed out");
        end
    end

    task automatic set_data_long(
        input integer address,
        input logic [31:0] value
    );
        begin
            data_ram.storage[address + 0] = value[31:24];
            data_ram.storage[address + 1] = value[23:16];
            data_ram.storage[address + 2] = value[15:8];
            data_ram.storage[address + 3] = value[7:0];
        end
    endtask

    task automatic set_word(
        input integer address,
        input logic [15:0] value
    );
        begin
            instruction_ram.storage[address + 0] = value[15:8];
            instruction_ram.storage[address + 1] = value[7:0];
        end
    endtask

    task automatic release_reset_and_wait;
        begin
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            while (!stopped && !faulted)
                @(negedge clk);
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        retire_count = 0;
        repeat (2) @(negedge clk);

        // A long at offset 14 is legal on MC68000, but spans two internal
        // 16-byte fabric lines. Exercise a split read and split RMW write.
        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);
        set_data_long(16'h00e, 32'h1122_3344);
        set_word(16'h100, 16'h41f8); // LEA $000e.W,A0
        set_word(16'h102, 16'h000e);
        set_word(16'h104, 16'h2010); // MOVE.L (A0),D0
        set_word(16'h106, 16'h4690); // NOT.L (A0)
        set_word(16'h108, 16'h2210); // MOVE.L (A0),D1
        set_word(16'h10a, 16'h4e72); // STOP #$2700
        set_word(16'h10c, 16'h2700);

        release_reset_and_wait();
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h1122_3344);
        assert (debug_data_registers[1*32 +: 32] == 32'heedd_ccbb);
        assert ({data_ram.storage[10'h00e], data_ram.storage[10'h00f],
                 data_ram.storage[10'h010], data_ram.storage[10'h011]} ==
                32'heedd_ccbb);
        assert (retire_count == 5);

        // JSR pushes its return PC at $000e and RTS reads it back, proving
        // that stack/control-flow traffic uses the same split machinery.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        set_data_long(0, 32'h0000_0012);
        set_data_long(4, 32'h0000_0140);
        set_word(16'h140, 16'h4eb9); // JSR $00000180.L
        set_word(16'h142, 16'h0000);
        set_word(16'h144, 16'h0180);
        set_word(16'h146, 16'h4e72); // STOP #$2700
        set_word(16'h148, 16'h2700);
        set_word(16'h180, 16'h4e75); // RTS

        release_reset_and_wait();
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_014a);
        assert (debug_ssp == 32'h0000_0012);
        assert ({data_ram.storage[10'h00e], data_ram.storage[10'h00f],
                 data_ram.storage[10'h010], data_ram.storage[10'h011]} ==
                32'h0000_0146);
        assert (retire_count == 3);

        // At the end of RAM the first word commits and the second word faults.
        // The group-0 frame must identify the failing second beat ($400), not
        // the logical base ($3fe), while preserving the visible partial write.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_01a0);
        set_data_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_01e0);
        data_ram.storage[10'h3fe] = 8'h55;
        data_ram.storage[10'h3ff] = 8'h66;
        set_word(16'h1a0, 16'h21fc); // MOVE.L #$aabbccdd,$03fe.W
        set_word(16'h1a2, 16'haabb);
        set_word(16'h1a4, 16'hccdd);
        set_word(16'h1a6, 16'h03fe);
        set_word(16'h1e0, 16'h4e72); // STOP #$2700 in vector-2 handler
        set_word(16'h1e2, 16'h2700);

        release_reset_and_wait();
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_ssp == 32'h0000_02f2);
        assert (data_ram.storage[10'h3fe] == 8'haa);
        assert (data_ram.storage[10'h3ff] == 8'hbb);
        assert ({data_ram.storage[10'h2f2], data_ram.storage[10'h2f3]} ==
                16'h000d);
        assert ({data_ram.storage[10'h2f4], data_ram.storage[10'h2f5],
                 data_ram.storage[10'h2f6], data_ram.storage[10'h2f7]} ==
                32'h0000_0400);
        assert ({data_ram.storage[10'h2f8], data_ram.storage[10'h2f9]} ==
                16'h21fc);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_01a8);
        assert (retire_count == 1);

        $display("PASS: M00 split long accesses across internal line boundary");
        $finish;
    end
endmodule
