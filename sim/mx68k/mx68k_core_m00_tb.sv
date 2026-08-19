module mx68k_core_m00_tb;
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;
    import mx68k_m00_decode_table_pkg::*;

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
        .irq(irq_bus),
        .imem(imem_bus), .dmem(dmem_bus)
    );

    mx68k_ram #(.MEM_BYTES(512), .REQUEST_STALL_CYCLES(1)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(.MEM_BYTES(512), .REQUEST_STALL_CYCLES(2)) vector_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer cycles;
    integer retire_count;
    logic [31:0] retired_pcs [0:15];
    logic [7:0] retired_ids [0:15];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retire_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (retire_valid) begin
                if (retire_count < 16) begin
                    retired_pcs[retire_count] <= retire_pc;
                    retired_ids[retire_count] <= retire_instruction_id;
                end
                retire_count <= retire_count + 1;
            end
            if (cycles > 3000)
                $fatal(1, "MX68K native M00 core test timed out");
        end
    end

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        retire_count = 0;

        repeat (2) @(negedge clk);
        // Reset vectors: SSP=0x1000, PC=0x100, stored canonically by byte.
        vector_ram.storage[0] = 8'h00;
        vector_ram.storage[1] = 8'h00;
        vector_ram.storage[2] = 8'h10;
        vector_ram.storage[3] = 8'h00;
        vector_ram.storage[4] = 8'h00;
        vector_ram.storage[5] = 8'h00;
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h00;

        // 0100: MOVEQ #1,D0
        // 0102: BNE.S 0106 (taken, skips MOVEQ #5,D2)
        // 0104: MOVEQ #5,D2
        // 0106: MOVEQ #7,D2
        // 0108: MOVE.B #$4f,$00000080
        // 0110: STOP #$2700
        instruction_ram.storage[9'h100] = 8'h70;
        instruction_ram.storage[9'h101] = 8'h01;
        instruction_ram.storage[9'h102] = 8'h66;
        instruction_ram.storage[9'h103] = 8'h02;
        instruction_ram.storage[9'h104] = 8'h74;
        instruction_ram.storage[9'h105] = 8'h05;
        instruction_ram.storage[9'h106] = 8'h74;
        instruction_ram.storage[9'h107] = 8'h07;
        instruction_ram.storage[9'h108] = 8'h13;
        instruction_ram.storage[9'h109] = 8'hfc;
        instruction_ram.storage[9'h10a] = 8'h00;
        instruction_ram.storage[9'h10b] = 8'h4f;
        instruction_ram.storage[9'h10c] = 8'h00;
        instruction_ram.storage[9'h10d] = 8'h00;
        instruction_ram.storage[9'h10e] = 8'h00;
        instruction_ram.storage[9'h10f] = 8'h80;
        instruction_ram.storage[9'h110] = 8'h4e;
        instruction_ram.storage[9'h111] = 8'h72;
        instruction_ram.storage[9'h112] = 8'h27;
        instruction_ram.storage[9'h113] = 8'h00;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        while (!stopped && !faulted)
            @(negedge clk);
        // Retirement trace is registered independently from the architectural
        // commit edge; allow its final STOP pulse to be sampled.
        @(posedge clk);
        @(negedge clk);

        assert (stopped && !faulted);
        assert (!terminal_exception.valid);
        assert (debug_ssp == 32'h0000_1000);
        assert (debug_pc == 32'h0000_0114);
        assert (debug_sr == 16'h2700);
        assert (debug_data_registers[0*32 +: 32] == 32'd1);
        assert (debug_data_registers[2*32 +: 32] == 32'd7);
        assert (vector_ram.storage[8'h80] == 8'h4f);
        assert (retire_count == 5);
        assert (retired_pcs[0] == 32'h100 && retired_ids[0] == MX_INSN_MOVEQ);
        assert (retired_pcs[1] == 32'h102 && retired_ids[1] == MX_INSN_BCC);
        assert (retired_pcs[2] == 32'h106 && retired_ids[2] == MX_INSN_MOVEQ);
        assert (retired_pcs[3] == 32'h108 &&
                retired_ids[3] == MX_INSN_MOVE_B);
        assert (retired_pcs[4] == 32'h110 && retired_ids[4] == MX_INSN_STOP);

        // A faulting store must not retire or advance architectural PC. This
        // scenario deliberately has an inaccessible SSP, so group-0 frame
        // construction escalates to the architectural double-fault halt path.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h20;
        instruction_ram.storage[9'h120] = 8'h13;
        instruction_ram.storage[9'h121] = 8'hfc;
        instruction_ram.storage[9'h122] = 8'h00;
        instruction_ram.storage[9'h123] = 8'haa;
        instruction_ram.storage[9'h124] = 8'h00;
        instruction_ram.storage[9'h125] = 8'h00;
        instruction_ram.storage[9'h126] = 8'h02;
        instruction_ram.storage[9'h127] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!faulted)
            @(negedge clk);
        assert (!stopped && terminal_exception.valid);
        assert (terminal_exception.vector == MX_VECTOR_ACCESS_FAULT);
        assert (terminal_exception.exception_class == MX_EXC_DOUBLE_FAULT);
        assert (terminal_exception.stage == MX_FAULT_STAGE_FRAME);
        assert (terminal_exception.instruction_pc == 32'h120);
        assert (terminal_exception.logical_address == 32'h0ffc);
        assert (terminal_exception.write);
        assert (debug_pc == 32'h120 && retire_count == 0);

        // Execute the real GCC startup idioms through a nested subroutine:
        // register and zero pushes, JSR, stack-relative TST, SR update and RTS.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[0] = 8'h00;
        vector_ram.storage[1] = 8'h00;
        vector_ram.storage[2] = 8'h01;
        vector_ram.storage[3] = 8'h80;
        vector_ram.storage[4] = 8'h00;
        vector_ram.storage[5] = 8'h00;
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h40;

        // 0140: MOVE.L A2,-(SP); MOVE.L D2,-(SP); CLR.L -(SP)
        // 0146: JSR $00000160; STOP #$2700
        instruction_ram.storage[9'h140] = 8'h2f;
        instruction_ram.storage[9'h141] = 8'h0a;
        instruction_ram.storage[9'h142] = 8'h2f;
        instruction_ram.storage[9'h143] = 8'h02;
        instruction_ram.storage[9'h144] = 8'h42;
        instruction_ram.storage[9'h145] = 8'ha7;
        instruction_ram.storage[9'h146] = 8'h4e;
        instruction_ram.storage[9'h147] = 8'hb9;
        instruction_ram.storage[9'h148] = 8'h00;
        instruction_ram.storage[9'h149] = 8'h00;
        instruction_ram.storage[9'h14a] = 8'h01;
        instruction_ram.storage[9'h14b] = 8'h60;
        instruction_ram.storage[9'h14c] = 8'h4e;
        instruction_ram.storage[9'h14d] = 8'h72;
        instruction_ram.storage[9'h14e] = 8'h27;
        instruction_ram.storage[9'h14f] = 8'h00;

        // 0160: TST.B 7(SP); BEQ 016c; ANDI #$f8ff,SR; NOP
        // 016c: ORI #$0700,SR; RTS
        instruction_ram.storage[9'h160] = 8'h4a;
        instruction_ram.storage[9'h161] = 8'h2f;
        instruction_ram.storage[9'h162] = 8'h00;
        instruction_ram.storage[9'h163] = 8'h07;
        instruction_ram.storage[9'h164] = 8'h67;
        instruction_ram.storage[9'h165] = 8'h06;
        instruction_ram.storage[9'h166] = 8'h02;
        instruction_ram.storage[9'h167] = 8'h7c;
        instruction_ram.storage[9'h168] = 8'hf8;
        instruction_ram.storage[9'h169] = 8'hff;
        instruction_ram.storage[9'h16a] = 8'h4e;
        instruction_ram.storage[9'h16b] = 8'h71;
        instruction_ram.storage[9'h16c] = 8'h00;
        instruction_ram.storage[9'h16d] = 8'h7c;
        instruction_ram.storage[9'h16e] = 8'h07;
        instruction_ram.storage[9'h16f] = 8'h00;
        instruction_ram.storage[9'h170] = 8'h4e;
        instruction_ram.storage[9'h171] = 8'h75;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h150);
        assert (debug_ssp == 32'h174);
        assert (retire_count == 9);
        assert ({vector_ram.storage[9'h170], vector_ram.storage[9'h171],
                 vector_ram.storage[9'h172], vector_ram.storage[9'h173]} ==
                32'h0000_014c);
        assert ({vector_ram.storage[9'h174], vector_ram.storage[9'h175],
                 vector_ram.storage[9'h176], vector_ram.storage[9'h177]} ==
                32'h0000_0000);

        // Word division uses a 32-bit dividend and writes remainder:quotient.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h80;
        // 0180: MOVE.L #100,D0; DIVU.W #7,D0
        // 018a: MOVE.L #-100,D1; DIVS.W #-7,D1; STOP #$2700
        instruction_ram.storage[9'h180] = 8'h20;
        instruction_ram.storage[9'h181] = 8'h3c;
        instruction_ram.storage[9'h182] = 8'h00;
        instruction_ram.storage[9'h183] = 8'h00;
        instruction_ram.storage[9'h184] = 8'h00;
        instruction_ram.storage[9'h185] = 8'h64;
        instruction_ram.storage[9'h186] = 8'h80;
        instruction_ram.storage[9'h187] = 8'hfc;
        instruction_ram.storage[9'h188] = 8'h00;
        instruction_ram.storage[9'h189] = 8'h07;
        instruction_ram.storage[9'h18a] = 8'h22;
        instruction_ram.storage[9'h18b] = 8'h3c;
        instruction_ram.storage[9'h18c] = 8'hff;
        instruction_ram.storage[9'h18d] = 8'hff;
        instruction_ram.storage[9'h18e] = 8'hff;
        instruction_ram.storage[9'h18f] = 8'h9c;
        instruction_ram.storage[9'h190] = 8'h83;
        instruction_ram.storage[9'h191] = 8'hfc;
        instruction_ram.storage[9'h192] = 8'hff;
        instruction_ram.storage[9'h193] = 8'hf9;
        instruction_ram.storage[9'h194] = 8'h4e;
        instruction_ram.storage[9'h195] = 8'h72;
        instruction_ram.storage[9'h196] = 8'h27;
        instruction_ram.storage[9'h197] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0002_000e);
        assert (debug_data_registers[1*32 +: 32] == 32'hfffe_000e);
        assert (retire_count == 5);

        // Memory source and quotient-overflow paths must behave identically.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'hb0;
        vector_ram.storage[9'h080] = 8'h00;
        vector_ram.storage[9'h081] = 8'h07;
        // 01b0: MOVE.L #100,D0; DIVU.W $0080.W,D0; STOP #$2700
        instruction_ram.storage[9'h1b0] = 8'h20;
        instruction_ram.storage[9'h1b1] = 8'h3c;
        instruction_ram.storage[9'h1b2] = 8'h00;
        instruction_ram.storage[9'h1b3] = 8'h00;
        instruction_ram.storage[9'h1b4] = 8'h00;
        instruction_ram.storage[9'h1b5] = 8'h64;
        instruction_ram.storage[9'h1b6] = 8'h80;
        instruction_ram.storage[9'h1b7] = 8'hf8;
        instruction_ram.storage[9'h1b8] = 8'h00;
        instruction_ram.storage[9'h1b9] = 8'h80;
        instruction_ram.storage[9'h1ba] = 8'h4e;
        instruction_ram.storage[9'h1bb] = 8'h72;
        instruction_ram.storage[9'h1bc] = 8'h27;
        instruction_ram.storage[9'h1bd] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0002_000e);

        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'hc0;
        // 01c0: MOVE.L #$10000,D0; DIVU.W #1,D0; BVS.S 01ce
        // 01cc: MOVEQ #1,D1; 01ce: MOVEQ #7,D1; STOP #$2700
        instruction_ram.storage[9'h1c0] = 8'h20;
        instruction_ram.storage[9'h1c1] = 8'h3c;
        instruction_ram.storage[9'h1c2] = 8'h00;
        instruction_ram.storage[9'h1c3] = 8'h01;
        instruction_ram.storage[9'h1c4] = 8'h00;
        instruction_ram.storage[9'h1c5] = 8'h00;
        instruction_ram.storage[9'h1c6] = 8'h80;
        instruction_ram.storage[9'h1c7] = 8'hfc;
        instruction_ram.storage[9'h1c8] = 8'h00;
        instruction_ram.storage[9'h1c9] = 8'h01;
        instruction_ram.storage[9'h1ca] = 8'h69;
        instruction_ram.storage[9'h1cb] = 8'h02;
        instruction_ram.storage[9'h1cc] = 8'h72;
        instruction_ram.storage[9'h1cd] = 8'h01;
        instruction_ram.storage[9'h1ce] = 8'h72;
        instruction_ram.storage[9'h1cf] = 8'h07;
        instruction_ram.storage[9'h1d0] = 8'h4e;
        instruction_ram.storage[9'h1d1] = 8'h72;
        instruction_ram.storage[9'h1d2] = 8'h27;
        instruction_ram.storage[9'h1d3] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0001_0000);
        assert (debug_data_registers[1*32 +: 32] == 32'd7);

        // A format-0 M00 trap frame round-trips through RTE.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[2] = 8'h01;
        vector_ram.storage[3] = 8'hf0;
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h00;
        vector_ram.storage[9'h080] = 8'h00; // vector 32 -> $00000160
        vector_ram.storage[9'h081] = 8'h00;
        vector_ram.storage[9'h082] = 8'h01;
        vector_ram.storage[9'h083] = 8'h60;
        instruction_ram.storage[9'h100] = 8'h4e; // TRAP #0
        instruction_ram.storage[9'h101] = 8'h40;
        instruction_ram.storage[9'h102] = 8'h74; // MOVEQ #9,D2
        instruction_ram.storage[9'h103] = 8'h09;
        instruction_ram.storage[9'h104] = 8'h4e; // STOP #$2700
        instruction_ram.storage[9'h105] = 8'h72;
        instruction_ram.storage[9'h106] = 8'h27;
        instruction_ram.storage[9'h107] = 8'h00;
        instruction_ram.storage[9'h160] = 8'h72; // MOVEQ #7,D1
        instruction_ram.storage[9'h161] = 8'h07;
        instruction_ram.storage[9'h162] = 8'h4e; // RTE
        instruction_ram.storage[9'h163] = 8'h73;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h108 && debug_ssp == 32'h1f0);
        assert (debug_data_registers[1*32 +: 32] == 32'd7);
        assert (debug_data_registers[2*32 +: 32] == 32'd9);
        assert ({vector_ram.storage[9'h1ea], vector_ram.storage[9'h1eb]} ==
                16'h2700);
        assert ({vector_ram.storage[9'h1ec], vector_ram.storage[9'h1ed],
                 vector_ram.storage[9'h1ee], vector_ram.storage[9'h1ef]} ==
                32'h0000_0102);
        assert (retire_count == 4);

        // Divide by zero is precise and enters vector 5 without changing Dn.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[2] = 8'h01;
        vector_ram.storage[3] = 8'h80;
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'he0;
        vector_ram.storage[9'h014] = 8'h00; // vector 5 -> $000001f0
        vector_ram.storage[9'h015] = 8'h00;
        vector_ram.storage[9'h016] = 8'h01;
        vector_ram.storage[9'h017] = 8'hf0;
        instruction_ram.storage[9'h1e0] = 8'h70; // MOVEQ #10,D0
        instruction_ram.storage[9'h1e1] = 8'h0a;
        instruction_ram.storage[9'h1e2] = 8'h80; // DIVU.W #0,D0
        instruction_ram.storage[9'h1e3] = 8'hfc;
        instruction_ram.storage[9'h1e4] = 8'h00;
        instruction_ram.storage[9'h1e5] = 8'h00;
        instruction_ram.storage[9'h1f0] = 8'h4e; // STOP #$2700
        instruction_ram.storage[9'h1f1] = 8'h72;
        instruction_ram.storage[9'h1f2] = 8'h27;
        instruction_ram.storage[9'h1f3] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h1f4 && debug_ssp == 32'h17a);
        assert (debug_data_registers[0*32 +: 32] == 32'd10);
        assert ({vector_ram.storage[9'h17a], vector_ram.storage[9'h17b]} ==
                16'h2700);
        assert ({vector_ram.storage[9'h17c], vector_ram.storage[9'h17d],
                 vector_ram.storage[9'h17e], vector_ram.storage[9'h17f]} ==
                32'h0000_01e6);
        assert (retire_count == 2);

        // Dn-to-memory ALU operations must source the encoded Dn rather than
        // the default source-EA register field (D0).  This is the exact shape
        // emitted by newlib for ADD.L D6,(A2).
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'h20;
        // 0120: MOVEQ #3,D0; MOVEQ #5,D6
        // 0124: MOVE.L #10,$01a0.W; ADD.L D6,$01a0.W
        // 0132: MOVE.L $01a0.W,D1; STOP #$2700
        instruction_ram.storage[9'h120] = 8'h70;
        instruction_ram.storage[9'h121] = 8'h03;
        instruction_ram.storage[9'h122] = 8'h7c;
        instruction_ram.storage[9'h123] = 8'h05;
        instruction_ram.storage[9'h124] = 8'h21;
        instruction_ram.storage[9'h125] = 8'hfc;
        instruction_ram.storage[9'h126] = 8'h00;
        instruction_ram.storage[9'h127] = 8'h00;
        instruction_ram.storage[9'h128] = 8'h00;
        instruction_ram.storage[9'h129] = 8'h0a;
        instruction_ram.storage[9'h12a] = 8'h01;
        instruction_ram.storage[9'h12b] = 8'ha0;
        instruction_ram.storage[9'h12c] = 8'hdd;
        instruction_ram.storage[9'h12d] = 8'hb8;
        instruction_ram.storage[9'h12e] = 8'h01;
        instruction_ram.storage[9'h12f] = 8'ha0;
        instruction_ram.storage[9'h130] = 8'h22;
        instruction_ram.storage[9'h131] = 8'h38;
        instruction_ram.storage[9'h132] = 8'h01;
        instruction_ram.storage[9'h133] = 8'ha0;
        instruction_ram.storage[9'h134] = 8'h4e;
        instruction_ram.storage[9'h135] = 8'h72;
        instruction_ram.storage[9'h136] = 8'h27;
        instruction_ram.storage[9'h137] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'd3);
        assert (debug_data_registers[1*32 +: 32] == 32'd15);

        // CLR on Dn writes only the selected operand width.  GCC's unsigned
        // divide helper relies on CLR.W followed by SWAP before DIVU.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        vector_ram.storage[6] = 8'h01;
        vector_ram.storage[7] = 8'ha0;
        // 01a0: MOVE.L #$12342000,D2; CLR.W D2; STOP #$2700
        instruction_ram.storage[9'h1a0] = 8'h24;
        instruction_ram.storage[9'h1a1] = 8'h3c;
        instruction_ram.storage[9'h1a2] = 8'h12;
        instruction_ram.storage[9'h1a3] = 8'h34;
        instruction_ram.storage[9'h1a4] = 8'h20;
        instruction_ram.storage[9'h1a5] = 8'h00;
        instruction_ram.storage[9'h1a6] = 8'h42;
        instruction_ram.storage[9'h1a7] = 8'h42;
        instruction_ram.storage[9'h1a8] = 8'h4e;
        instruction_ram.storage[9'h1a9] = 8'h72;
        instruction_ram.storage[9'h1aa] = 8'h27;
        instruction_ram.storage[9'h1ab] = 8'h00;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[2*32 +: 32] == 32'h1234_0000);

        $display("PASS: native M00 ALU/DIV, precise exceptions and RTE");
        $finish;
    end
endmodule
