module m64k_core_bus_error_tb;
    import m64k_arch_pkg::*;

    logic clk;
    logic rst_n;
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
        .clk, .rst_n,
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
    integer retire_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retire_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (retire_valid)
                retire_count <= retire_count + 1;
            if (cycles > 5000)
                $fatal(1, "M64K bus/address-error test timed out");
        end
    end

    task automatic set_long(
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

    task automatic check_special_frame(
        input logic [15:0] expected_ssw,
        input logic [31:0] expected_address,
        input logic [15:0] expected_ir,
        input logic [31:0] expected_pc
    );
        begin
            assert ({data_ram.storage[10'h2f2],
                     data_ram.storage[10'h2f3]} == expected_ssw);
            assert ({data_ram.storage[10'h2f4],
                     data_ram.storage[10'h2f5],
                     data_ram.storage[10'h2f6],
                     data_ram.storage[10'h2f7]} == expected_address);
            assert ({data_ram.storage[10'h2f8],
                     data_ram.storage[10'h2f9]} == expected_ir);
            assert ({data_ram.storage[10'h2fa],
                     data_ram.storage[10'h2fb]} == 16'h2700);
            assert ({data_ram.storage[10'h2fc],
                     data_ram.storage[10'h2fd],
                     data_ram.storage[10'h2fe],
                     data_ram.storage[10'h2ff]} == expected_pc);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        retire_count = 0;
        repeat (2) @(negedge clk);

        // A fabric access error builds the seven-word MC68000 group-0 frame.
        // The handler discards SSW/address/IR (8 bytes) before ordinary RTE.
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0100);
        set_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);
        set_word(16'h100, 16'h13fc); // MOVE.B #$aa,$00000400.L
        set_word(16'h102, 16'h00aa);
        set_word(16'h104, 16'h0000);
        set_word(16'h106, 16'h0400);
        set_word(16'h108, 16'h4e72); // STOP #$2700 after handler return
        set_word(16'h10a, 16'h2700);
        set_word(16'h180, 16'h4fef); // LEA 8(A7),A7
        set_word(16'h182, 16'h0008);
        set_word(16'h184, 16'h4e73); // RTE

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_010c);
        assert (debug_ssp == 32'h0000_0300);
        assert (retire_count == 3);
        check_special_frame(16'h000d, 32'h0000_0400,
                            16'h13fc, 32'h0000_0108);

        // Odd word access is rejected before it reaches the fabric and uses
        // vector 3 with the same diagnostic frame layout.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0120);
        set_long(M64K_VECTOR_ADDRESS_ERROR * 4, 32'h0000_01a0);
        data_ram.storage[10'h201] = 8'h5a;
        data_ram.storage[10'h202] = 8'ha5;
        set_word(16'h120, 16'h41f8); // LEA $0201.W,A0
        set_word(16'h122, 16'h0201);
        set_word(16'h124, 16'h30bc); // MOVE.W #$1234,(A0)
        set_word(16'h126, 16'h1234);
        set_word(16'h128, 16'h4e72); // STOP #$2700
        set_word(16'h12a, 16'h2700);
        set_word(16'h1a0, 16'h4fef); // LEA 8(A7),A7
        set_word(16'h1a2, 16'h0008);
        set_word(16'h1a4, 16'h4e73); // RTE

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_012c);
        assert (debug_ssp == 32'h0000_0300);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0201);
        assert (data_ram.storage[10'h201] == 8'h5a);
        assert (data_ram.storage[10'h202] == 8'ha5);
        assert (retire_count == 4);
        check_special_frame(16'h000d, 32'h0000_0201,
                            16'h30bc, 32'h0000_0128);

        // Instruction-fetch bus error identifies a supervisor program read in
        // the SSW (R/W=1, I/N=0, FC=110). Its diagnostic frame remains on the
        // stack because this handler intentionally stops instead of returning
        // to the still-unmapped address.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0140);
        set_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_01c0);
        set_word(16'h140, 16'h4ef9); // JMP $00000400.L
        set_word(16'h142, 16'h0000);
        set_word(16'h144, 16'h0400);
        set_word(16'h1c0, 16'h4e72); // STOP #$2700
        set_word(16'h1c2, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_01c4);
        assert (debug_ssp == 32'h0000_02f2);
        assert (retire_count == 2);
        check_special_frame(16'h0016, 32'h0000_0400,
                            16'h0000, 32'h0000_0400);

        $display("PASS: M00 bus/address-error special frames and handler RTE");
        $finish;
    end
endmodule
