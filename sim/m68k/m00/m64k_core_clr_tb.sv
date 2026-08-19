module m64k_core_clr_tb;
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
    integer target_accesses;
    m64k_mem_command_t target_commands [0:1];
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            target_accesses <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr == 32'h0000_0204)) begin
                assert (target_accesses < 2);
                target_commands[target_accesses] <= dmem_bus.req.command;
                target_accesses <= target_accesses + 1;
            end
            if (cycles > 2000)
                $fatal(1, "M64K CLR test timed out");
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
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);
        data_ram.storage[10'h204] = 8'ha5;

        set_word(16'h100, 16'h44fc); // MOVE.W #$10,CCR: retain X=1
        set_word(16'h102, 16'h0010);
        set_word(16'h104, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h106, 16'h0200);
        set_word(16'h108, 16'h4228); // CLR.B 4(A0)
        set_word(16'h10a, 16'h0004);
        set_word(16'h10c, 16'h60fe); // preserve final state

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_0108)))
            @(negedge clk);
        assert (!stopped && !faulted && !terminal_exception.valid);
        assert (data_ram.storage[10'h204] == 8'h00);
        assert (debug_sr[4:0] == 5'b1_0100);
        assert (target_accesses == 2);
        assert (target_commands[0] == M64K_MEM_READ);
        assert (target_commands[1] == M64K_MEM_WRITE);

        $display("PASS: M00 CLR flags and MC68000 memory read-before-write");
        $finish;
    end
endmodule
