module mx68k_core_control_address_tb;
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
                $fatal(1, "MX68K control/address test timed out");
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

        set_word(16'h100, 16'h003c); // ORI #$1f,CCR
        set_word(16'h102, 16'h001f);

        // PRM 4-109/4-110: LEA calculates a control EA, performs no operand
        // read, writes all 32 An bits and leaves every condition code alone.
        set_word(16'h104, 16'h41f8); // LEA $ffff.W,A0
        set_word(16'h106, 16'hffff);
        set_word(16'h108, 16'h43fa); // LEA 4(PC),A1 => extension PC $10a + 4
        set_word(16'h10a, 16'h0004);

        // PRM 4-107/4-108: JMP transfers directly to the control EA.
        set_word(16'h10c, 16'h4ef8); // JMP $0120.W
        set_word(16'h10e, 16'h0120);
        set_word(16'h110, 16'h4afc); // must be skipped

        set_word(16'h120, 16'h4df8); // LEA $0280.W,A6
        set_word(16'h122, 16'h0280);

        // PRM 4-110/4-112: push old An, assign updated SP to An, then add
        // the sign-extended word displacement to SP.
        set_word(16'h124, 16'h4e56); // LINK A6,#-16
        set_word(16'h126, 16'hfff0);

        // PRM 4-108/4-109: JSR pushes the PC following the complete
        // instruction before transferring control.
        set_word(16'h128, 16'h4eb9); // JSR $00000160.L
        set_word(16'h12a, 16'h0000);
        set_word(16'h12c, 16'h0160);
        set_word(16'h12e, 16'h4e5e); // UNLK A6
        // PRM 4-110/4-193 operation ordering is observable when An=A7.
        // LINK stores the already-decremented SP.  UNLK then loads A7 from
        // memory before applying its final +4 to that newly loaded value.
        set_word(16'h130, 16'h4e57); // LINK A7,#-8
        set_word(16'h132, 16'hfff8);
        set_word(16'h134, 16'h4e5f); // UNLK A7
        set_word(16'h136, 16'h4e72); // STOP #$2700
        set_word(16'h138, 16'h2700);
        set_word(16'h160, 16'h4e75); // RTS
        set_data_long(16'h2f4, 32'h0000_0350); // UNLK A7 pulled value

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_0104);
        assert (debug_address_registers[0*32 +: 32] == 32'hffff_ffff);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0108);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_010e);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_010c);
        assert (debug_pc == 32'h0000_0120);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0124);
        assert (debug_address_registers[6*32 +: 32] == 32'h0000_02fc);
        assert (debug_ssp == 32'h0000_02ec);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0280);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0128);
        assert (debug_ssp == 32'h0000_02e8);
        assert ({data_ram.storage[10'h2e8], data_ram.storage[10'h2e9],
                 data_ram.storage[10'h2ea], data_ram.storage[10'h2eb]} ==
                32'h0000_012e);
        assert (debug_pc == 32'h0000_0160);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0160);
        assert (debug_ssp == 32'h0000_02ec);
        assert (debug_pc == 32'h0000_012e);

        wait_retire(32'h0000_012e);
        assert (debug_address_registers[6*32 +: 32] == 32'h0000_0280);
        assert (debug_ssp == 32'h0000_0300);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0130);
        assert (debug_ssp == 32'h0000_02f4);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_02fc);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0134);
        assert (debug_ssp == 32'h0000_0354);
        assert (debug_sr == 16'h271f);

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        $display("PASS: M00 JMP/JSR/LEA/LINK/UNLK control and stack semantics");
        $finish;
    end
endmodule
