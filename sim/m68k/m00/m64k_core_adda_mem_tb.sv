module m64k_core_adda_mem_tb;
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
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 3000)
                $fatal(1, "M64K ADDA/SUBA memory-source test timed out");
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

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);
        set_data_long('h200, 32'h0000_0200);
        data_ram.storage['h204] = 8'h00;
        data_ram.storage['h205] = 8'h0c;
        set_data_long('h220, 32'h0000_0004);
        set_data_long('h300, 32'h0000_0000);

        set_word('h100, 16'h7005); // MOVEQ #5,D0: catch D0/An confusion
        set_word('h102, 16'h307c); // MOVEA.W #-$14,A0
        set_word('h104, 16'hffec);
        set_word('h106, 16'hd1f9); // ADDA.L $00000200,A0 -> $1ec
        set_word('h108, 16'h0000);
        set_word('h10a, 16'h0200);
        set_word('h10c, 16'h90f9); // SUBA.W $00000204,A0 -> $1e0
        set_word('h10e, 16'h0000);
        set_word('h110, 16'h0204);
        set_word('h112, 16'hdfdf); // ADDA.L (SP)+,SP -> $304
        set_word('h114, 16'h43f8); // LEA $0220.W,A1
        set_word('h116, 16'h0220);
        set_word('h118, 16'hd1d9); // ADDA.L (A1)+,A0 -> A0=$1e4,A1=$224
        set_word('h11a, 16'h60fe);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_0106)))
            @(negedge clk);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_01ec);

        while (!(retire_valid && (retire_pc == 32'h0000_010c)))
            @(negedge clk);
        assert (!stopped && !faulted && !terminal_exception.valid);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_01e0);
        assert (debug_data_registers[0*32 +: 32] == 32'd5);

        while (!(retire_valid && (retire_pc == 32'h0000_0112)))
            @(negedge clk);
        assert (debug_ssp == 32'h0000_0304);

        while (!(retire_valid && (retire_pc == 32'h0000_0118)))
            @(negedge clk);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_01e4);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_0224);

        $display("PASS: M00 ADDA/SUBA memory source and An side effects");
        $finish;
    end
endmodule
