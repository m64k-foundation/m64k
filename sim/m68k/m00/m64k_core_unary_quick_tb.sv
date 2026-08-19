module m64k_core_unary_quick_tb;
    import m64k_arch_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
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
        .clk, .rst_n, .reset_devices_n,
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
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 5000)
                $fatal(1, "M64K unary/quick test timed out");
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

    task automatic begin_case;
        begin
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0300);
            set_data_long(4, 32'h0000_0100);
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        // PRM 4-133/4-134: MOVEQ sign-extends its byte, computes long N/Z,
        // clears V/C and preserves X.
        set_word(16'h100, 16'h003c); // ORI #$10,CCR
        set_word(16'h102, 16'h0010);
        set_word(16'h104, 16'h7680); // MOVEQ #-128,D3
        set_word(16'h106, 16'h7800); // MOVEQ #0,D4
        set_word(16'h108, 16'h4e72); // STOP #$2700
        set_word(16'h10a, 16'h2700);
        begin_case();
        wait_retire(32'h0000_0104);
        assert (debug_data_registers[3*32 +: 32] == 32'hffff_ff80);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_0106);
        assert (debug_data_registers[4*32 +: 32] == 32'h0000_0000);
        assert (debug_sr == 16'h2714);
        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);

        // PRM 4-105 and 4-183: EXT.W preserves Dn[31:16], EXT.L writes all
        // 32 bits, and SWAP tests the complete 32-bit result.  All preserve X.
        set_word(16'h100, 16'h203c); // MOVE.L #$12348080,D0
        set_word(16'h102, 16'h1234);
        set_word(16'h104, 16'h8080);
        set_word(16'h106, 16'h003c); // ORI #$10,CCR
        set_word(16'h108, 16'h0010);
        set_word(16'h10a, 16'h4880); // EXT.W D0
        set_word(16'h10c, 16'h48c0); // EXT.L D0
        set_word(16'h10e, 16'h4840); // SWAP D0
        set_word(16'h110, 16'h223c); // MOVE.L #$12340000,D1
        set_word(16'h112, 16'h1234);
        set_word(16'h114, 16'h0000);
        set_word(16'h116, 16'h4881); // EXT.W D1: word result is zero
        set_word(16'h118, 16'h7400); // MOVEQ #0,D2
        set_word(16'h11a, 16'h4842); // SWAP D2: long result is zero
        set_word(16'h11c, 16'h4e72); // STOP #$2700
        set_word(16'h11e, 16'h2700);
        begin_case();
        wait_retire(32'h0000_010a);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_ff80);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_010c);
        assert (debug_data_registers[0*32 +: 32] == 32'hffff_ff80);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_010e);
        assert (debug_data_registers[0*32 +: 32] == 32'hff80_ffff);
        assert (debug_sr == 16'h2718);
        wait_retire(32'h0000_0116);
        assert (debug_data_registers[1*32 +: 32] == 32'h1234_0000);
        assert (debug_sr == 16'h2714);
        wait_retire(32'h0000_011a);
        assert (debug_data_registers[2*32 +: 32] == 32'h0000_0000);
        assert (debug_sr == 16'h2714);
        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);

        // PRM 4-191/4-192: M00 TST accepts data-alterable EAs only, never
        // writes the operand, applies normal An side effects and preserves X.
        set_data_long(16'h200, 32'h8000_0000);
        set_word(16'h100, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h102, 16'h0200);
        set_word(16'h104, 16'h003c); // ORI #$10,CCR
        set_word(16'h106, 16'h0010);
        set_word(16'h108, 16'h4a18); // TST.B (A0)+
        set_word(16'h10a, 16'h41f8); // LEA $0204.W,A0
        set_word(16'h10c, 16'h0204);
        set_word(16'h10e, 16'h4aa0); // TST.L -(A0)
        set_word(16'h110, 16'h4e72); // STOP #$2700
        set_word(16'h112, 16'h2700);
        begin_case();
        wait_retire(32'h0000_0108);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0201);
        assert (debug_sr == 16'h2718);
        assert ({data_ram.storage[10'h200], data_ram.storage[10'h201],
                 data_ram.storage[10'h202], data_ram.storage[10'h203]} ==
                32'h8000_0000);
        wait_retire(32'h0000_010e);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0200);
        assert (debug_sr == 16'h2718);
        assert ({data_ram.storage[10'h200], data_ram.storage[10'h201],
                 data_ram.storage[10'h202], data_ram.storage[10'h203]} ==
                32'h8000_0000);
        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);

        // PRM 4-142/4-143 and 4-147/4-148: NEG writes X=C and has normal Z;
        // NOT preserves X and clears V/C.  Memory forms are ordered RMWs.
        set_data_long(16'h200, 32'h0100_0000);
        set_word(16'h100, 16'h203c); // MOVE.L #$12340080,D0
        set_word(16'h102, 16'h1234);
        set_word(16'h104, 16'h0080);
        set_word(16'h106, 16'h003c); // ORI #$10,CCR
        set_word(16'h108, 16'h0010);
        set_word(16'h10a, 16'h4400); // NEG.B D0
        set_word(16'h10c, 16'h223c); // MOVE.L #$aaaa0000,D1
        set_word(16'h10e, 16'haaaa);
        set_word(16'h110, 16'h0000);
        set_word(16'h112, 16'h4441); // NEG.W D1
        set_word(16'h114, 16'h243c); // MOVE.L #$ffffffff,D2
        set_word(16'h116, 16'hffff);
        set_word(16'h118, 16'hffff);
        set_word(16'h11a, 16'h003c); // ORI #$10,CCR
        set_word(16'h11c, 16'h0010);
        set_word(16'h11e, 16'h4682); // NOT.L D2
        set_word(16'h120, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h122, 16'h0200);
        set_word(16'h124, 16'h4418); // NEG.B (A0)+
        set_word(16'h126, 16'h4620); // NOT.B -(A0)
        set_word(16'h128, 16'h4e72); // STOP #$2700
        set_word(16'h12a, 16'h2700);
        begin_case();
        wait_retire(32'h0000_010a);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_0080);
        assert (debug_sr == 16'h271b);
        wait_retire(32'h0000_0112);
        assert (debug_data_registers[1*32 +: 32] == 32'haaaa_0000);
        assert (debug_sr == 16'h2704);
        wait_retire(32'h0000_011e);
        assert (debug_data_registers[2*32 +: 32] == 32'h0000_0000);
        assert (debug_sr == 16'h2714);
        wait_retire(32'h0000_0124);
        assert (data_ram.storage[10'h200] == 8'hff);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0201);
        assert (debug_sr == 16'h2719);
        wait_retire(32'h0000_0126);
        assert (data_ram.storage[10'h200] == 8'h00);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0200);
        assert (debug_sr == 16'h2714);
        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);

        // PRM 4-10/4-12 and 4-180/4-182: quick zero encodes eight; An word
        // and long operations use all 32 bits and preserve every flag.
        set_data_long(16'h200, 32'hff00_0000);
        set_word(16'h100, 16'h203c); // MOVE.L #$1234ffff,D0
        set_word(16'h102, 16'h1234);
        set_word(16'h104, 16'hffff);
        set_word(16'h106, 16'h5240); // ADDQ.W #1,D0
        set_word(16'h108, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h10a, 16'h0200);
        set_word(16'h10c, 16'h003c); // ORI #$1f,CCR
        set_word(16'h10e, 16'h001f);
        set_word(16'h110, 16'h5048); // ADDQ.W #8,A0
        set_word(16'h112, 16'h5388); // SUBQ.L #1,A0
        set_word(16'h114, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h116, 16'h0200);
        set_word(16'h118, 16'h5218); // ADDQ.B #1,(A0)+
        set_word(16'h11a, 16'h5120); // SUBQ.B #8,-(A0)
        set_word(16'h11c, 16'h4e72); // STOP #$2700
        set_word(16'h11e, 16'h2700);
        begin_case();
        wait_retire(32'h0000_0106);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_0000);
        assert (debug_sr == 16'h2715);
        wait_retire(32'h0000_0110);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0208);
        assert (debug_sr == 16'h271f);
        wait_retire(32'h0000_0112);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0207);
        assert (debug_sr == 16'h271f);
        wait_retire(32'h0000_0118);
        assert (data_ram.storage[10'h200] == 8'h00);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0201);
        assert (debug_sr == 16'h2715);
        wait_retire(32'h0000_011a);
        assert (data_ram.storage[10'h200] == 8'hf8);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0200);
        assert (debug_sr == 16'h2719);
        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);

        $display("PASS: M00 MOVEQ/EXT/SWAP/TST/NEG/NOT/ADDQ/SUBQ semantics");
        $finish;
    end
endmodule
