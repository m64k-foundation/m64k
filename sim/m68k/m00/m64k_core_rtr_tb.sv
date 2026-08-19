module m64k_core_rtr_tb;
    import m64k_pkg::*;
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
    integer stack_reads;
    logic [31:0] stack_read_address [0:1];
    m64k_mem_size_t stack_read_size [0:1];
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            stack_reads <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.command == M64K_MEM_READ) &&
                (dmem_bus.req.addr inside {32'h0000_0200,
                                           32'h0000_0202})) begin
                assert (stack_reads < 2);
                stack_read_address[stack_reads] <= dmem_bus.req.addr;
                stack_read_size[stack_reads] <= dmem_bus.req.size;
                stack_reads <= stack_reads + 1;
            end
            if (cycles > 2000)
                $fatal(1, "M64K RTR test timed out");
        end
    end

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        begin
            data_ram.storage[address + 0] = value[31:24];
            data_ram.storage[address + 1] = value[23:16];
            data_ram.storage[address + 2] = value[15:8];
            data_ram.storage[address + 3] = value[7:0];
        end
    endtask

    task automatic set_data_word(input integer address,
                                 input logic [15:0] value);
        begin
            data_ram.storage[address + 0] = value[15:8];
            data_ram.storage[address + 1] = value[7:0];
        end
    endtask

    task automatic set_word(input integer address,
                            input logic [15:0] value);
        begin
            instruction_ram.storage[address + 0] = value[15:8];
            instruction_ram.storage[address + 1] = value[7:0];
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        stack_reads = 0;
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0200);
        set_data_long(4, 32'h0000_0100);

        // RTR consumes a word containing the CCR and then a long PC.  The
        // upper byte of the stacked word must not modify the supervisor SR.
        set_data_word(16'h200, 16'hab04);
        set_data_long(16'h202, 32'h0000_0120);

        set_word(16'h100, 16'h46fc); // MOVE.W #$251f,SR
        set_word(16'h102, 16'h251f);
        set_word(16'h104, 16'h4e77); // RTR
        set_word(16'h120, 16'h4e72); // STOP #$2700
        set_word(16'h122, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_0104)))
            @(negedge clk);

        assert (!faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0120);
        assert (debug_ssp == 32'h0000_0206);
        assert (debug_sr == 16'h2504);
        assert (stack_reads == 2);
        assert (stack_read_address[0] == 32'h0000_0200);
        assert (stack_read_size[0] == M64K_SIZE_WORD);
        assert (stack_read_address[1] == 32'h0000_0202);
        assert (stack_read_size[1] == M64K_SIZE_LONG);

        wait (stopped);
        @(negedge clk);
        assert (!faulted && !terminal_exception.valid);

        $display("PASS: M00 RTR restores only CCR, then PC, and advances SP by six");
        $finish;
    end
endmodule
