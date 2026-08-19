module mx68k_core_muldiv_tb;
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
                $fatal(1, "MX68K multiply/divide test timed out");
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
        set_data_long(16'h200, 32'hfffe_0000);

        set_word(16'h100, 16'h003c); // ORI #$10,CCR: X=1
        set_word(16'h102, 16'h0010);
        set_word(16'h104, 16'h203c); // MOVE.L #$abcdffff,D0
        set_word(16'h106, 16'habcd);
        set_word(16'h108, 16'hffff);
        set_word(16'h10a, 16'hc0fc); // MULU.W #2,D0
        set_word(16'h10c, 16'h0002);
        set_word(16'h10e, 16'h223c); // MOVE.L #$00007fff,D1
        set_word(16'h110, 16'h0000);
        set_word(16'h112, 16'h7fff);
        set_word(16'h114, 16'hc3fc); // MULS.W #-2,D1
        set_word(16'h116, 16'hfffe);
        set_word(16'h118, 16'h7400); // MOVEQ #0,D2
        set_word(16'h11a, 16'hc5fc); // MULS.W #0,D2
        set_word(16'h11c, 16'h0000);

        // PRM 4-91/4-98: DIVS remainder follows dividend sign and occupies
        // the upper result word; quotient occupies the lower word.
        set_word(16'h11e, 16'h263c); // MOVE.L #-100,D3
        set_word(16'h120, 16'hffff);
        set_word(16'h122, 16'hff9c);
        set_word(16'h124, 16'h87fc); // DIVS.W #7,D3
        set_word(16'h126, 16'h0007);

        // Both unsigned and signed quotient overflow preserve Dn, set V and
        // clear C. N/Z are architecturally undefined and are not asserted.
        set_word(16'h128, 16'h283c); // MOVE.L #$00010000,D4
        set_word(16'h12a, 16'h0001);
        set_word(16'h12c, 16'h0000);
        set_word(16'h12e, 16'h88fc); // DIVU.W #1,D4: overflow
        set_word(16'h130, 16'h0001);
        set_word(16'h132, 16'h2a3c); // MOVE.L #$80000000,D5
        set_word(16'h134, 16'h8000);
        set_word(16'h136, 16'h0000);
        set_word(16'h138, 16'h8bfc); // DIVS.W #-1,D5: overflow
        set_word(16'h13a, 16'hffff);

        // A legal memory source updates its address register once.
        set_word(16'h13c, 16'h7c03); // MOVEQ #3,D6
        set_word(16'h13e, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h140, 16'h0200);
        set_word(16'h142, 16'hcdd8); // MULS.W (A0)+,D6 => -6
        set_word(16'h144, 16'h4e72); // STOP #$2700
        set_word(16'h146, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_010a);
        assert (debug_data_registers[0*32 +: 32] == 32'h0001_fffe);
        assert (debug_sr == 16'h2710);
        wait_retire(32'h0000_0114);
        assert (debug_data_registers[1*32 +: 32] == 32'hffff_0002);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_011a);
        assert (debug_data_registers[2*32 +: 32] == 32'h0000_0000);
        assert (debug_sr == 16'h2714);
        wait_retire(32'h0000_0124);
        assert (debug_data_registers[3*32 +: 32] == 32'hfffe_fff2);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_012e);
        assert (debug_data_registers[4*32 +: 32] == 32'h0001_0000);
        assert ((debug_sr & 16'h0013) == 16'h0012); // X=1,V=1,C=0
        wait_retire(32'h0000_0138);
        assert (debug_data_registers[5*32 +: 32] == 32'h8000_0000)
            else $error("DIVS overflow changed D5 to %08x",
                        debug_data_registers[5*32 +: 32]);
        assert ((debug_sr & 16'h0013) == 16'h0012); // X=1,V=1,C=0
        wait_retire(32'h0000_0142);
        assert (debug_data_registers[6*32 +: 32] == 32'hffff_fffa);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0202);
        assert (debug_sr == 16'h2718);

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        $display("PASS: M00 MUL/DIV result, flags, overflow and EA semantics");
        $finish;
    end
endmodule
