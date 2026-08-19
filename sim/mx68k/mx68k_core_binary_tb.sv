module mx68k_core_binary_tb;
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
            if (cycles > 5000)
                $fatal(1, "MX68K binary operation test timed out");
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
        data_ram.storage[10'h200] = 8'h80;
        data_ram.storage[10'h210] = 8'h7f;

        set_word(16'h100, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h102, 16'h0200);
        set_word(16'h104, 16'h203c); // MOVE.L #$12347fff,D0
        set_word(16'h106, 16'h1234);
        set_word(16'h108, 16'h7fff);

        // PRM 4-3..4-5: An is a legal ADD source for word/long and the
        // operation writes only the selected portion of Dn.
        set_word(16'h10a, 16'hd048); // ADD.W A0,D0

        set_word(16'h10c, 16'h003c); // ORI #$10,CCR: X=1
        set_word(16'h10e, 16'h0010);
        // The generic <ea> source tables permit immediate data, although an
        // assembler normally emits ANDI/SUBI/CMPI instead.
        set_word(16'h110, 16'hc07c); // AND.W #$0ff0,D0
        set_word(16'h112, 16'h0ff0);
        set_word(16'h114, 16'h90bc); // SUB.L #$000001f0,D0
        set_word(16'h116, 16'h0000);
        set_word(16'h118, 16'h01f0);
        set_word(16'h11a, 16'hb07c); // CMP.W #0,D0
        set_word(16'h11c, 16'h0000);

        // PRM 4-149..4-151: logical source memory retains normal EA side
        // effects and preserves X.
        set_word(16'h11e, 16'h003c); // ORI #$10,CCR
        set_word(16'h120, 16'h0010);
        set_word(16'h122, 16'h7201); // MOVEQ #1,D1
        set_word(16'h124, 16'h8218); // OR.B (A0)+,D1

        set_word(16'h126, 16'h43f8); // LEA $0210.W,A1
        set_word(16'h128, 16'h0210);
        set_word(16'h12a, 16'h7401); // MOVEQ #1,D2

        // Destination-<ea> ADD/SUB/AND/OR are memory alterable only; EOR
        // additionally permits Dn.  Memory forms are ordered RMW cycles.
        set_word(16'h12c, 16'hd511); // ADD.B D2,(A1): $7f -> $80
        set_word(16'h12e, 16'h9511); // SUB.B D2,(A1): $80 -> $7f
        set_word(16'h130, 16'h003c); // restore X=1 for logical preservation
        set_word(16'h132, 16'h0010);
        set_word(16'h134, 16'hc511); // AND.B D2,(A1): $7f -> $01
        set_word(16'h136, 16'h8511); // OR.B D2,(A1): $01 -> $01
        set_word(16'h138, 16'hb511); // EOR.B D2,(A1): $01 -> $00

        set_word(16'h13a, 16'h4e72); // STOP #$2700
        set_word(16'h13c, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_010a);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_81ff);
        assert (debug_sr == 16'h270a); // N,V; no carry/extend

        wait_retire(32'h0000_0110);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_01f0);
        assert (debug_sr == 16'h2710); // X preserved by AND

        wait_retire(32'h0000_0114);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_0000);
        assert (debug_sr == 16'h2700);

        wait_retire(32'h0000_011a);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_0000);
        assert (debug_sr == 16'h2704); // CMP does not write D0

        wait_retire(32'h0000_0124);
        assert (debug_data_registers[1*32 +: 32] == 32'h0000_0081);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0201);
        assert (debug_sr == 16'h2718); // X,N and no V/C

        wait_retire(32'h0000_012c);
        assert (data_ram.storage[10'h210] == 8'h80);
        assert (debug_sr == 16'h270a); // N,V; X/C clear
        wait_retire(32'h0000_012e);
        assert (data_ram.storage[10'h210] == 8'h7f);
        assert (debug_sr == 16'h2702); // signed overflow, no borrow
        wait_retire(32'h0000_0134);
        assert (data_ram.storage[10'h210] == 8'h01);
        assert (debug_sr == 16'h2710);
        wait_retire(32'h0000_0136);
        assert (data_ram.storage[10'h210] == 8'h01);
        assert (debug_sr == 16'h2710);
        wait_retire(32'h0000_0138);
        assert (data_ram.storage[10'h210] == 8'h00);
        assert (debug_sr == 16'h2714); // X preserved, Z set

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        $display("PASS: M00 binary directions, immediate EAs, flags and RMW");
        $finish;
    end
endmodule
