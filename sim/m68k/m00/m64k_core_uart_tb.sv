module m64k_core_uart_tb;
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
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;

    m64k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if core_dmem_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if vectors_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if uart_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if unused_bus(.clk(clk), .rst_n(rst_n));
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
        .irq(irq_bus),
        .imem(imem_bus), .dmem(core_dmem_bus)
    );

    m64k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );

    m64k_router_3 #(
        .PORT0_BASE(32'h0000_0000),
        .PORT0_MASK(32'hffff_ff00),
        .PORT1_BASE(32'h00ff_f900),
        .PORT1_MASK(32'hffff_ff00),
        .PORT2_ENABLE(1'b0)
    ) data_router (
        .clk, .rst_n,
        .upstream(core_dmem_bus),
        .port0(vectors_bus),
        .port1(uart_bus),
        .port2(unused_bus)
    );

    m64k_ram #(.MEM_BYTES(256)) vector_ram (
        .clk, .rst_n, .mem(vectors_bus)
    );

    m64k_uart_16550_model uart (
        .clk, .rst_n,
        .tx_valid(uart_tx_valid),
        .tx_data(uart_tx_data),
        .mem(uart_bus)
    );

    m64k_ram #(.BASE_ADDR(32'hdead_0000), .MEM_BYTES(16)) unused_target (
        .clk, .rst_n, .mem(unused_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer cycles;
    integer tx_count;
    logic [7:0] captured_tx;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            tx_count <= 0;
            captured_tx <= '0;
        end else begin
            cycles <= cycles + 1;
            if (uart_tx_valid) begin
                tx_count <= tx_count + 1;
                captured_tx <= uart_tx_data;
            end
            if (cycles > 3000)
                $fatal(1, "M64K native UART test timed out");
        end
    end

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        tx_count = 0;
        captured_tx = 0;
        repeat (2) @(negedge clk);

        vector_ram.storage[0] = 8'h00;
        vector_ram.storage[1] = 8'h00;
        vector_ram.storage[2] = 8'h10;
        vector_ram.storage[3] = 8'h00;
        vector_ram.storage[4] = 8'h00;
        vector_ram.storage[5] = 8'h00;
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h00;

        // MOVE.B #'X',$00fff900; STOP #$2700
        instruction_ram.storage[9'h100] = 8'h13;
        instruction_ram.storage[9'h101] = 8'hfc;
        instruction_ram.storage[9'h102] = 8'h00;
        instruction_ram.storage[9'h103] = 8'h58;
        instruction_ram.storage[9'h104] = 8'h00;
        instruction_ram.storage[9'h105] = 8'hff;
        instruction_ram.storage[9'h106] = 8'hf9;
        instruction_ram.storage[9'h107] = 8'h00;
        instruction_ram.storage[9'h108] = 8'h4e;
        instruction_ram.storage[9'h109] = 8'h72;
        instruction_ram.storage[9'h10a] = 8'h27;
        instruction_ram.storage[9'h10b] = 8'h00;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);

        assert (stopped && !faulted && !terminal_exception.valid);
        assert (tx_count == 1 && captured_tx == "X");
        assert (debug_pc == 32'h10c);
        $display("PASS: native M64K emitted '%c' through fabric UART", captured_tx);
        $finish;
    end
endmodule
