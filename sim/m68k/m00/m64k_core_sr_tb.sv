module m64k_core_sr_tb;
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
    integer sr_target_accesses;
    m64k_mem_command_t sr_target_commands [0:1];
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            sr_target_accesses <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr == 32'h0000_0202)) begin
                assert (sr_target_accesses < 2);
                sr_target_commands[sr_target_accesses] <=
                    dmem_bus.req.command;
                sr_target_accesses <= sr_target_accesses + 1;
            end
            if (cycles > 2000)
                $fatal(1, "M64K SR test timed out");
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
        set_data_long(M64K_VECTOR_PRIVILEGE * 4, 32'h0000_0180);
        data_ram.storage[10'h200] = 8'h20;
        data_ram.storage[10'h201] = 8'h09;
        data_ram.storage[10'h202] = 8'ha5;
        data_ram.storage[10'h203] = 8'h5a;

        set_word(16'h100, 16'h46fc); // MOVE.W #$2015,SR
        set_word(16'h102, 16'h2015);
        set_word(16'h104, 16'h40c0); // MOVE.W SR,D0
        set_word(16'h106, 16'h46f8); // MOVE.W $0200.W,SR
        set_word(16'h108, 16'h0200);
        set_word(16'h10a, 16'h4e71); // observe memory result before next SR write
        set_word(16'h10c, 16'h40f8); // MOVE SR,$0202.W: M00 reads then writes
        set_word(16'h10e, 16'h0202);
        set_word(16'h110, 16'h46fc); // enter user mode, retain Z
        set_word(16'h112, 16'h0004);
        set_word(16'h114, 16'h46fc); // privileged in user mode: vector 8
        set_word(16'h116, 16'h2700);
        set_word(16'h118, 16'h4e72); // must not execute
        set_word(16'h11a, 16'h2700);
        set_word(16'h180, 16'h4e72); // privilege handler: STOP #$2700
        set_word(16'h182, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_0100)))
            @(negedge clk);
        assert (debug_sr == 16'h2015);

        while (!(retire_valid && (retire_pc == 32'h0000_010a)))
            @(negedge clk);
        assert (debug_sr == 16'h2009);

        wait (stopped);
        @(negedge clk);
        assert (!faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_2015);
        assert ({data_ram.storage[10'h202], data_ram.storage[10'h203]} ==
                16'h2009);
        assert (sr_target_accesses == 2);
        assert (sr_target_commands[0] == M64K_MEM_READ);
        assert (sr_target_commands[1] == M64K_MEM_WRITE);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h0004);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0114);

        $display("PASS: M00 MOVE SR/CCR privilege and read-before-write");
        $finish;
    end
endmodule
