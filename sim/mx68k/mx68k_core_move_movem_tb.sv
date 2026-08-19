module mx68k_core_move_movem_tb;
    import mx68k_arch_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
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
        .clk, .rst_n, .reset_devices_n,
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
            if (cycles > 8000)
                $fatal(1, "MX68K MOVE/MOVEM test timed out");
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

    task automatic wait_retire(input logic [31:0] expected_pc);
        begin
            while (!(retire_valid && (retire_pc == expected_pc)))
                @(negedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);
        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);
        set_data_long(16'h200, 32'h1122_3344);
        set_data_word(16'h240, 16'habcd);
        data_ram.storage[10'h300] = 8'h00;
        set_data_long(16'h310, 32'h1111_1111);
        set_data_long(16'h314, 32'hdead_beef);
        data_ram.storage[10'h350] = 8'h55;

        set_word(16'h100, 16'h003c); // ORI #$1f,CCR
        set_word(16'h102, 16'h001f);
        set_word(16'h104, 16'h203c); // MOVE.L #$12345678,D0
        set_word(16'h106, 16'h1234);
        set_word(16'h108, 16'h5678);
        set_word(16'h10a, 16'h103c); // MOVE.B #$80,D0
        set_word(16'h10c, 16'h0080);
        set_word(16'h10e, 16'h41f8); // LEA $ffff.W,A0
        set_word(16'h110, 16'hffff);
        set_word(16'h112, 16'h3208); // MOVE.W A0,D1
        set_word(16'h114, 16'h347c); // MOVEA.W #$8000,A2
        set_word(16'h116, 16'h8000);

        // PRM 4-115..4-117: source is evaluated/read before destination;
        // both EAs retain their individual address-register side effects.
        set_word(16'h118, 16'h47f8); // LEA $0200.W,A3
        set_word(16'h11a, 16'h0200);
        set_word(16'h11c, 16'h49f8); // LEA $0220.W,A4
        set_word(16'h11e, 16'h0220);
        set_word(16'h120, 16'h291b); // MOVE.L (A3)+,-(A4)

        // Source extension words precede destination extension words.
        set_word(16'h122, 16'h31f9); // MOVE.W $00000240.L,$0250.W
        set_word(16'h124, 16'h0000);
        set_word(16'h126, 16'h0240);
        set_word(16'h128, 16'h0250);
        set_word(16'h12a, 16'h141f); // MOVE.B (A7)+,D2; A7 step is two

        set_word(16'h12c, 16'h203c); // MOVE.L #$11223344,D0
        set_word(16'h12e, 16'h1122);
        set_word(16'h130, 16'h3344);
        set_word(16'h132, 16'h223c); // MOVE.L #$aabbccdd,D1
        set_word(16'h134, 16'haabb);
        set_word(16'h136, 16'hccdd);
        set_word(16'h138, 16'h43f8); // LEA $0280.W,A1
        set_word(16'h13a, 16'h0280);
        set_word(16'h13c, 16'h247c); // MOVEA.L #$12345678,A2
        set_word(16'h13e, 16'h1234);
        set_word(16'h140, 16'h5678);

        // PRM 4-127..4-130: control-mode masks walk D0..A7 and word loads
        // sign-extend each selected register.
        set_word(16'h142, 16'h4891); // MOVEM.W D0/D1/A2,(A1)
        set_word(16'h144, 16'h0403);
        set_word(16'h146, 16'h4c91); // MOVEM.W (A1),D2/D3/A3
        set_word(16'h148, 16'h080c);

        // Predecrement reverses mask correspondence/order.  M00 stores the
        // initial base-register value if that register is in the list.
        set_word(16'h14a, 16'h49f8); // LEA $02c0.W,A4
        set_word(16'h14c, 16'h02c0);
        set_word(16'h14e, 16'h48e4); // MOVEM.L D0/A4,-(A4)
        set_word(16'h150, 16'h8008);

        // Postincrement load ignores a memory value selected for its own
        // base register and leaves the final incremented address there.
        set_word(16'h152, 16'h4bf8); // LEA $0310.W,A5
        set_word(16'h154, 16'h0310);
        set_word(16'h156, 16'h4cdd); // MOVEM.L (A5)+,D4/A5
        set_word(16'h158, 16'h2010);

        set_word(16'h15a, 16'h4df8); // LEA $0350.W,A6
        set_word(16'h15c, 16'h0350);
        set_word(16'h15e, 16'h48d6); // MOVEM.L empty,(A6): no transfer
        set_word(16'h160, 16'h0000);
        set_word(16'h162, 16'h4e72); // STOP #$2700
        set_word(16'h164, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_010a);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_5680);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_0112);
        assert (debug_data_registers[1*32 +: 32] == 32'h0000_ffff);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_0114);
        assert (debug_address_registers[2*32 +: 32] == 32'hffff_8000);
        assert (debug_sr == 16'h2718); // MOVEA never changes flags

        wait_retire(32'h0000_0120);
        assert (debug_address_registers[3*32 +: 32] == 32'h0000_0204);
        assert (debug_address_registers[4*32 +: 32] == 32'h0000_021c);
        assert ({data_ram.storage[10'h21c], data_ram.storage[10'h21d],
                 data_ram.storage[10'h21e], data_ram.storage[10'h21f]} ==
                32'h1122_3344);
        assert (debug_sr == 16'h2710);
        wait_retire(32'h0000_0122);
        assert ({data_ram.storage[10'h250], data_ram.storage[10'h251]} ==
                16'habcd);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_012a);
        assert (debug_data_registers[2*32 +: 8] == 8'h00);
        assert (debug_ssp == 32'h0000_0302);
        assert (debug_sr == 16'h2714);

        wait_retire(32'h0000_0142);
        assert ({data_ram.storage[10'h280], data_ram.storage[10'h281]} ==
                16'h3344);
        assert ({data_ram.storage[10'h282], data_ram.storage[10'h283]} ==
                16'hccdd);
        assert ({data_ram.storage[10'h284], data_ram.storage[10'h285]} ==
                16'h5678);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_0280);
        assert (debug_sr == 16'h2718);

        wait_retire(32'h0000_0146);
        assert (debug_data_registers[2*32 +: 32] == 32'h0000_3344);
        assert (debug_data_registers[3*32 +: 32] == 32'hffff_ccdd);
        assert (debug_address_registers[3*32 +: 32] == 32'h0000_5678);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_0280);
        assert (debug_sr == 16'h2718);

        wait_retire(32'h0000_014e);
        assert (debug_address_registers[4*32 +: 32] == 32'h0000_02b8);
        assert ({data_ram.storage[10'h2b8], data_ram.storage[10'h2b9],
                 data_ram.storage[10'h2ba], data_ram.storage[10'h2bb]} ==
                32'h1122_3344);
        assert ({data_ram.storage[10'h2bc], data_ram.storage[10'h2bd],
                 data_ram.storage[10'h2be], data_ram.storage[10'h2bf]} ==
                32'h0000_02c0);
        assert (debug_sr == 16'h2718);

        wait_retire(32'h0000_0156);
        assert (debug_data_registers[4*32 +: 32] == 32'h1111_1111);
        assert (debug_address_registers[5*32 +: 32] == 32'h0000_0318);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_015e);
        assert (debug_address_registers[6*32 +: 32] == 32'h0000_0350);
        assert (data_ram.storage[10'h350] == 8'h55);
        assert (debug_sr == 16'h2718);

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        $display("PASS: M00 MOVE/MOVEA and MOVEM ordering/alias semantics");
        $finish;
    end
endmodule
