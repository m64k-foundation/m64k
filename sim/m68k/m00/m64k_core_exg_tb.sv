module m64k_core_exg_tb;
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
    logic reset_devices_n;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    integer cycles;

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
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp, .reset_devices_n,
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

    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 1000)
                $fatal(1, "M64K EXG test timed out");
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

        set_data_long(0, 32'h0000_0380);
        set_data_long(4, 32'h0000_0100);

        set_word('h100, 16'h203c); // MOVE.L #$11112222,D0
        set_word('h102, 16'h1111);
        set_word('h104, 16'h2222);
        set_word('h106, 16'h223c); // MOVE.L #$33334444,D1
        set_word('h108, 16'h3333);
        set_word('h10a, 16'h4444);
        set_word('h10c, 16'h207c); // MOVEA.L #$55556666,A0
        set_word('h10e, 16'h5555);
        set_word('h110, 16'h6666);
        set_word('h112, 16'h227c); // MOVEA.L #$77778888,A1
        set_word('h114, 16'h7777);
        set_word('h116, 16'h8888);
        set_word('h118, 16'h243c); // MOVE.L #$9999aaaa,D2
        set_word('h11a, 16'h9999);
        set_word('h11c, 16'haaaa);
        set_word('h11e, 16'h44fc); // MOVE.W #$001f,CCR
        set_word('h120, 16'h001f);
        set_word('h122, 16'hc141); // EXG D1,D0
        set_word('h124, 16'hc149); // EXG A1,A0
        set_word('h126, 16'hc589); // EXG A1,D2
        set_word('h128, 16'hc14f); // EXG A7,A0
        set_word('h12a, 16'h60fe); // BRA.S *

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_0122)))
            @(negedge clk);
        assert (debug_data_registers[0*32 +: 32] == 32'h3333_4444);
        assert (debug_data_registers[1*32 +: 32] == 32'h1111_2222);
        assert (debug_sr[4:0] == 5'h1f);

        while (!(retire_valid && (retire_pc == 32'h0000_0124)))
            @(negedge clk);
        assert (debug_address_registers[0*32 +: 32] == 32'h7777_8888);
        assert (debug_address_registers[1*32 +: 32] == 32'h5555_6666);
        assert (debug_sr[4:0] == 5'h1f);

        while (!(retire_valid && (retire_pc == 32'h0000_0126)))
            @(negedge clk);
        assert (debug_data_registers[2*32 +: 32] == 32'h5555_6666);
        assert (debug_address_registers[1*32 +: 32] == 32'h9999_aaaa);
        assert (debug_sr[4:0] == 5'h1f);

        while (!(retire_valid && (retire_pc == 32'h0000_0128)))
            @(negedge clk);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0380);
        assert (debug_ssp == 32'h7777_8888);
        assert (debug_sr[4:0] == 5'h1f);
        assert (!stopped && !faulted && !terminal_exception.valid);

        $display("PASS: M00 EXG Dn/Dn, An/An, Dn/An, and active A7 bank");
        $finish;
    end
endmodule
