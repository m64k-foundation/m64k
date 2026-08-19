module mx68k_core_logical_sr_tb;
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
            if (cycles > 3000)
                $fatal(1, "MX68K logical SR/CCR test timed out");
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

        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0100);
        set_long(MX_VECTOR_PRIVILEGE * 4, 32'h0000_0180);

        // M68000PRM 4-19, 4-103 and 4-154: CCR forms affect only the
        // low byte and are legal in user state.  The SR forms are word-wide
        // and privileged.
        set_word(16'h100, 16'h003c); // ORI.B #$1f,CCR: $2700 -> $271f
        set_word(16'h102, 16'h001f);
        set_word(16'h104, 16'h40c0); // MOVE SR,D0
        set_word(16'h106, 16'h023c); // ANDI.B #$0a,CCR -> $270a
        set_word(16'h108, 16'h000a);
        set_word(16'h10a, 16'h40c1); // MOVE SR,D1
        set_word(16'h10c, 16'h0a3c); // EORI.B #$0f,CCR -> $2705
        set_word(16'h10e, 16'h000f);
        set_word(16'h110, 16'h40c2); // MOVE SR,D2
        set_word(16'h112, 16'h0a7c); // EORI.W #$0705,SR -> $2000
        set_word(16'h114, 16'h0705);
        set_word(16'h116, 16'h40c3); // MOVE SR,D3
        set_word(16'h118, 16'h46fc); // MOVE.W #0,SR: user state
        set_word(16'h11a, 16'h0000);
        set_word(16'h11c, 16'h003c); // ORI.B #$1f,CCR remains legal
        set_word(16'h11e, 16'h001f);
        set_word(16'h120, 16'h40c4); // MOVE SR,D4 (legal on MC68000)
        set_word(16'h122, 16'h0a7c); // EORI SR: privilege, fault PC=$122
        set_word(16'h124, 16'hffff);
        set_word(16'h126, 16'h70ff); // must not execute
        set_word(16'h180, 16'h4e72); // privilege handler: STOP #$2700
        set_word(16'h182, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        wait (stopped || faulted);
        @(negedge clk);

        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_271f);
        assert (debug_data_registers[1*32 +: 32] == 32'h0000_270a);
        assert (debug_data_registers[2*32 +: 32] == 32'h0000_2705);
        assert (debug_data_registers[3*32 +: 32] == 32'h0000_2000);
        assert (debug_data_registers[4*32 +: 32] == 32'h0000_001f);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h001f);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0122);

        $display("PASS: M00 ORI/ANDI/EORI CCR/SR width and privilege");
        $finish;
    end
endmodule
