module mx68k_core_negx_tb;
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
                $fatal(1, "MX68K NEGX test timed out");
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

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);
        set_data_long(14, 32'h0000_0000);

        set_word('h100, 16'h7000); // MOVEQ #0,D0
        set_word('h102, 16'h44fc); // MOVE.W #$15,CCR: X=Z=C=1
        set_word('h104, 16'h0015);
        set_word('h106, 16'h4000); // NEGX.B D0 -> $ff
        set_word('h108, 16'h7200); // MOVEQ #0,D1 (preserves X)
        set_word('h10a, 16'h4041); // NEGX.W D1 -> $ffff

        set_word('h10c, 16'h7400); // MOVEQ #0,D2
        set_word('h10e, 16'h44fc); // Clear X and Z after loading D2
        set_word('h110, 16'h0000);
        set_word('h112, 16'h4082); // NEGX.L D2 -> 0, cumulative Z remains 0
        set_word('h114, 16'h6702); // BEQ skips sentinel if Z is wrong
        set_word('h116, 16'h7801); // MOVEQ #1,D4

        set_word('h118, 16'h7600); // MOVEQ #0,D3 establishes Z=1, X=0
        set_word('h11a, 16'h4083); // NEGX.L D3 -> 0, cumulative Z remains 1
        set_word('h11c, 16'h6602); // BNE skips sentinel if Z is wrong
        set_word('h11e, 16'h7a02); // MOVEQ #2,D5

        set_word('h120, 16'h41f8); // LEA $000e.W,A0
        set_word('h122, 16'h000e);
        set_word('h124, 16'h44fc); // X=Z=C=1
        set_word('h126, 16'h0015);
        set_word('h128, 16'h4090); // NEGX.L (A0), split-line RMW
        set_word('h12a, 16'h60fe); // BRA.S * (preserves final CCR)

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!(retire_valid && (retire_pc == 32'h0000_0128)))
            @(posedge clk);
        repeat (2) @(negedge clk);

        assert (!stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_00ff);
        assert (debug_data_registers[1*32 +: 32] == 32'h0000_ffff);
        assert (debug_data_registers[2*32 +: 32] == 32'h0000_0000);
        assert (debug_data_registers[3*32 +: 32] == 32'h0000_0000);
        assert (debug_data_registers[4*32 +: 32] == 32'h0000_0001);
        assert (debug_data_registers[5*32 +: 32] == 32'h0000_0002);
        assert ({data_ram.storage[10'h00e], data_ram.storage[10'h00f],
                 data_ram.storage[10'h010], data_ram.storage[10'h011]} ==
                32'hffff_ffff);
        // NEGX 0 with X=1 produces -1: X=1,N=1,Z=0,V=0,C=1.
        assert (debug_sr[4:0] == 5'b1_1001);

        $display("PASS: M00 NEGX register/memory, X input and cumulative Z");
        $finish;
    end
endmodule
