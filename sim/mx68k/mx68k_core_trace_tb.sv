module mx68k_core_trace_tb;
    import mx68k_arch_pkg::*;

    logic clk;
    logic rst_n;
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

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    mx68k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n,
        .stopped, .faulted, .terminal_exception,
        .retire_valid, .retire_pc, .retire_instruction_id,
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp,
        .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    mx68k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(.MEM_BYTES(1024)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer cycles;
    integer acknowledge_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            acknowledge_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (irq_bus.acknowledge)
                acknowledge_count <= acknowledge_count + 1;
            if (cycles > 5000)
                $fatal(1, "MX68K trace test timed out");
        end
    end

    task automatic set_long(
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

    initial begin
        rst_n = 1'b0;
        irq_bus.request = 1'b0;
        irq_bus.level = 3'd0;
        irq_bus.vector_valid = 1'b0;
        irq_bus.vector = 8'd0;
        cycles = 0;
        acknowledge_count = 0;
        repeat (2) @(negedge clk);

        // Normal trace wins over a simultaneously pending interrupt. The
        // interrupt is then taken before the first trace-handler instruction.
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0100);
        set_long(MX_VECTOR_TRACE * 4, 32'h0000_0180);
        set_long((MX_VECTOR_AUTOVECTOR_BASE + 6) * 4, 32'h0000_01a0);

        set_word(16'h100, 16'h027c); // ANDI.W #$f8ff,SR: I=0
        set_word(16'h102, 16'hf8ff);
        set_word(16'h104, 16'h007c); // ORI.W #$8000,SR: T1=1
        set_word(16'h106, 16'h8000);
        set_word(16'h108, 16'h4e71); // NOP: traced, stacked PC=$10a
        set_word(16'h10a, 16'h4e72); // must not execute
        set_word(16'h10c, 16'h2700);

        set_word(16'h180, 16'h7409); // trace: MOVEQ #9,D2
        set_word(16'h182, 16'h4e72); // STOP #$2700
        set_word(16'h184, 16'h2700);
        set_word(16'h1a0, 16'h7006); // IRQ6: MOVEQ #6,D0
        set_word(16'h1a2, 16'h4e73); // RTE to trace handler

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!(retire_valid && (retire_pc == 32'h0000_0108)))
            @(negedge clk);
        irq_bus.request = 1'b1;
        irq_bus.level = 3'd6;
        while (!irq_bus.acknowledge)
            @(negedge clk);
        assert (irq_bus.acknowledged_level == 3'd6);
        irq_bus.request = 1'b0;

        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0186);
        assert (debug_ssp == 32'h0000_02fa);
        assert (debug_data_registers[0*32 +: 32] == 32'd6);
        assert (debug_data_registers[2*32 +: 32] == 32'd9);
        assert (acknowledge_count == 1);
        // Outer trace frame: status at instruction start, following PC.
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'ha000);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_010a);
        // Nested IRQ frame proves trace entry occurred before IRQ acceptance.
        assert ({data_ram.storage[10'h2f4], data_ram.storage[10'h2f5]} ==
                16'h2000);
        assert ({data_ram.storage[10'h2f6], data_ram.storage[10'h2f7],
                 data_ram.storage[10'h2f8], data_ram.storage[10'h2f9]} ==
                32'h0000_0180);

        // A synchronous instruction trap is processed before its trace. The
        // trace handler returns into the trap handler, not into user code.
        rst_n = 1'b0;
        irq_bus.request = 1'b0;
        irq_bus.level = 3'd0;
        repeat (2) @(negedge clk);
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0120);
        set_long(MX_VECTOR_TRACE * 4, 32'h0000_01a0);
        set_long(MX_VECTOR_TRAP_BASE * 4, 32'h0000_0180);

        set_word(16'h120, 16'h027c); // ANDI.W #$f8ff,SR
        set_word(16'h122, 16'hf8ff);
        set_word(16'h124, 16'h007c); // ORI.W #$8000,SR
        set_word(16'h126, 16'h8000);
        set_word(16'h128, 16'h4e40); // TRAP #0, stacked PC=$12a
        set_word(16'h12a, 16'h4e72); // must not execute
        set_word(16'h12c, 16'h2700);

        set_word(16'h180, 16'h4e72); // trap handler: STOP #$2700
        set_word(16'h182, 16'h2700);
        set_word(16'h1a0, 16'h7409); // trace handler: MOVEQ #9,D2
        set_word(16'h1a2, 16'h4e73); // RTE to trap handler

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0184);
        assert (debug_ssp == 32'h0000_02fa);
        assert (debug_data_registers[2*32 +: 32] == 32'd9);
        assert (acknowledge_count == 0);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'ha000);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_012a);
        assert ({data_ram.storage[10'h2f4], data_ram.storage[10'h2f5]} ==
                16'h2000);
        assert ({data_ram.storage[10'h2f6], data_ram.storage[10'h2f7],
                 data_ram.storage[10'h2f8], data_ram.storage[10'h2f9]} ==
                32'h0000_0180);

        $display("PASS: M00 trace frames and trap/trace/IRQ precedence");
        $finish;
    end
endmodule
