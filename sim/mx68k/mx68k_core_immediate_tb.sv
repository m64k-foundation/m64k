module mx68k_core_immediate_tb;
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
                $fatal(1, "MX68K immediate-operation test timed out");
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
        set_data_long(16'h200, 32'hff00_8000);
        set_data_long(16'h204, 32'h0000_0000);

        // PRM immediate-operation entries: byte data occupies the low byte
        // of one extension word, word uses that word and long uses two words.
        // Logical operations preserve X; ADDI/SUBI write X=C; CMPI preserves
        // X and never writes its destination.
        set_word(16'h100, 16'h203c); // MOVE.L #$123480f0,D0
        set_word(16'h102, 16'h1234);
        set_word(16'h104, 16'h80f0);
        set_word(16'h106, 16'h003c); // ORI #$10,CCR
        set_word(16'h108, 16'h0010);
        set_word(16'h10a, 16'h0000); // ORI.B #$0f,D0
        set_word(16'h10c, 16'h000f);
        set_word(16'h10e, 16'h0240); // ANDI.W #$00ff,D0
        set_word(16'h110, 16'h00ff);
        set_word(16'h112, 16'h0a80); // EORI.L #$923400ff,D0
        set_word(16'h114, 16'h9234);
        set_word(16'h116, 16'h00ff);
        set_word(16'h118, 16'h223c); // MOVE.L #$1234007f,D1
        set_word(16'h11a, 16'h1234);
        set_word(16'h11c, 16'h007f);
        set_word(16'h11e, 16'h0601); // ADDI.B #1,D1
        set_word(16'h120, 16'h0001);
        set_word(16'h122, 16'h243c); // MOVE.L #$aaaa0000,D2
        set_word(16'h124, 16'haaaa);
        set_word(16'h126, 16'h0000);
        set_word(16'h128, 16'h0442); // SUBI.W #1,D2
        set_word(16'h12a, 16'h0001);
        set_word(16'h12c, 16'h0c82); // CMPI.L #$aaaaffff,D2
        set_word(16'h12e, 16'haaaa);
        set_word(16'h130, 16'hffff);

        // The memory forms below cover ordered RMW, postincrement, result
        // flags and the read-only CMPI path.
        set_word(16'h132, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h134, 16'h0200);
        set_word(16'h136, 16'h0018); // ORI.B #1,(A0)+
        set_word(16'h138, 16'h0001);
        set_word(16'h13a, 16'h41f8); // LEA $0202.W,A0
        set_word(16'h13c, 16'h0202);
        set_word(16'h13e, 16'h0658); // ADDI.W #$8000,(A0)+
        set_word(16'h140, 16'h8000);
        set_word(16'h142, 16'h41f8); // LEA $0204.W,A0
        set_word(16'h144, 16'h0204);
        set_word(16'h146, 16'h0a90); // EORI.L #$ffffffff,(A0)
        set_word(16'h148, 16'hffff);
        set_word(16'h14a, 16'hffff);
        set_word(16'h14c, 16'h0490); // SUBI.L #1,(A0)
        set_word(16'h14e, 16'h0000);
        set_word(16'h150, 16'h0001);
        set_word(16'h152, 16'h0c90); // CMPI.L #$fffffffe,(A0)
        set_word(16'h154, 16'hffff);
        set_word(16'h156, 16'hfffe);
        set_word(16'h158, 16'h4e72); // STOP #$2700
        set_word(16'h15a, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_010a);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_80ff);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_010e);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_00ff);
        assert (debug_sr == 16'h2710);
        wait_retire(32'h0000_0112);
        assert (debug_data_registers[0*32 +: 32] == 32'h8000_0000);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_011e);
        assert (debug_data_registers[1*32 +: 32] == 32'h1234_0080);
        assert (debug_sr == 16'h270a);
        wait_retire(32'h0000_0128);
        assert (debug_data_registers[2*32 +: 32] == 32'haaaa_ffff);
        assert (debug_sr == 16'h2719);
        wait_retire(32'h0000_012c);
        assert (debug_data_registers[2*32 +: 32] == 32'haaaa_ffff);
        assert (debug_sr == 16'h2714);

        wait_retire(32'h0000_0136);
        assert (data_ram.storage[10'h200] == 8'hff);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0201);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_013e);
        assert ({data_ram.storage[10'h202], data_ram.storage[10'h203]} ==
                16'h0000);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0204);
        assert (debug_sr == 16'h2717);
        wait_retire(32'h0000_0146);
        assert ({data_ram.storage[10'h204], data_ram.storage[10'h205],
                 data_ram.storage[10'h206], data_ram.storage[10'h207]} ==
                32'hffff_ffff);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_014c);
        assert ({data_ram.storage[10'h204], data_ram.storage[10'h205],
                 data_ram.storage[10'h206], data_ram.storage[10'h207]} ==
                32'hffff_fffe);
        assert (debug_sr == 16'h2708);
        wait_retire(32'h0000_0152);
        assert ({data_ram.storage[10'h204], data_ram.storage[10'h205],
                 data_ram.storage[10'h206], data_ram.storage[10'h207]} ==
                32'hffff_fffe);
        assert (debug_sr == 16'h2704);

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        $display("PASS: M00 immediate arithmetic/logical/compare semantics");
        $finish;
    end
endmodule
