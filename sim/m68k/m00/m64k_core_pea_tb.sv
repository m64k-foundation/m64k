module m64k_core_pea_tb;
    import m64k_pkg::*;
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
            if (cycles > 2000)
                $fatal(1, "M64K PEA test timed out");
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
            @(negedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);

        set_word(16'h100, 16'h44fc); // MOVE.W #$001f,CCR
        set_word(16'h102, 16'h001f);
        set_word(16'h104, 16'h45f8); // LEA $0180.W,A2
        set_word(16'h106, 16'h0180);
        set_word(16'h108, 16'h47f8); // LEA $01c0.W,A3
        set_word(16'h10a, 16'h01c0);
        set_word(16'h10c, 16'h486b); // PEA 4(A3)
        set_word(16'h10e, 16'h0004);
        set_word(16'h110, 16'h486a); // PEA 16(A2)
        set_word(16'h112, 16'h0010);
        set_word(16'h114, 16'h4e71); // NOP, preserve observation window
        set_word(16'h116, 16'h4e72); // STOP #$2700
        set_word(16'h118, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_010c);
        assert (debug_ssp == 32'h0000_02fc);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_01c4);
        assert (debug_sr == 16'h271f);

        wait_retire(32'h0000_0110);
        assert (debug_ssp == 32'h0000_02f8);
        assert ({data_ram.storage[10'h2f8], data_ram.storage[10'h2f9],
                 data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                32'h0000_0190);
        assert (debug_sr == 16'h271f);

        wait (stopped);
        @(negedge clk);
        assert (!faulted && !terminal_exception.valid);
        assert (debug_address_registers[2*32 +: 32] == 32'h0000_0180);
        assert (debug_address_registers[3*32 +: 32] == 32'h0000_01c0);
        assert (debug_ssp == 32'h0000_02f8);

        $display("PASS: M00 PEA computes consecutive control EAs and preserves CCR");
        $finish;
    end
endmodule
