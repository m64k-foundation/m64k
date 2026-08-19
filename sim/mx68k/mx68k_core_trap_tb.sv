module mx68k_core_trap_tb;
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

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

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
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 3000) begin
                $display("timeout pc=%08x sr=%04x ssp=%08x state=%0d retire=%0b retire_pc=%08x faulted=%0b",
                         debug_pc, debug_sr, debug_ssp, core.state_q,
                         retire_valid, retire_pc, faulted);
                $fatal(1, "MX68K trap test timed out");
            end
        end
    end

    task automatic set_long(input integer address,
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

        // M68000PRM 4-190: V=0 makes TRAPV a no-op; V=1 takes vector 7,
        // preserving flags and stacking the following PC in the 6-byte M00
        // group-2 frame.
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0100);
        set_long(MX_VECTOR_TRAPCC * 4, 32'h0000_0180);
        set_word(16'h100, 16'h7001); // MOVEQ #1,D0: V=0
        set_word(16'h102, 16'h4e76); // TRAPV: no trap
        set_word(16'h104, 16'h7002); // proves fall-through
        set_word(16'h106, 16'h003c); // ORI.B #2,CCR: V=1
        set_word(16'h108, 16'h0002);
        set_word(16'h10a, 16'h4e76); // TRAPV: vector 7, stacked PC=$10c
        set_word(16'h10c, 16'h70ff); // must not execute
        set_word(16'h180, 16'h4e72); // handler: STOP #$2700
        set_word(16'h182, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'd2);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2702);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_010c);

        // M68000PRM 4-187: TRAP #15 selects vector 47 and likewise stacks
        // the following PC without modifying condition codes.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0120);
        set_long((MX_VECTOR_TRAP_BASE + 15) * 4, 32'h0000_01a0);
        set_word(16'h120, 16'h70ff); // MOVEQ #-1,D0: N=1
        set_word(16'h122, 16'h4e4f); // TRAP #15, stacked PC=$124
        set_word(16'h124, 16'h7000); // must not execute
        set_word(16'h1a0, 16'h4e72); // handler: STOP #$2700
        set_word(16'h1a2, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'hffff_ffff);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2708);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0124);

        $display("PASS: M00 TRAPV condition and TRAP vector/frame semantics");
        $finish;
    end
endmodule
