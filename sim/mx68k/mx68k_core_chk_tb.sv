module mx68k_core_chk_tb;
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
    integer retired_chk_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retired_chk_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (retire_valid && (retire_instruction_id == MX_INSN_CHK_W))
                retired_chk_count <= retired_chk_count + 1;
            if (cycles > 4000)
                $fatal(1, "MX68K CHK test timed out");
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

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        retired_chk_count = 0;
        repeat (2) @(negedge clk);

        // Reset and CHK vector.
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0100);
        set_long(MX_VECTOR_CHK * 4, 32'h0000_0180);
        data_ram.storage[10'h200] = 8'h00;
        data_ram.storage[10'h201] = 8'h0a;

        // An in-range immediate CHK retires. A negative CHK traps, returns,
        // then a memory/postincrement CHK traps because 20 > 10.
        set_word(16'h100, 16'h7005); // MOVEQ #5,D0
        set_word(16'h102, 16'h41bc); // CHK.W #10,D0
        set_word(16'h104, 16'h000a);
        set_word(16'h106, 16'h70ff); // MOVEQ #-1,D0
        set_word(16'h108, 16'h41bc); // CHK.W #10,D0
        set_word(16'h10a, 16'h000a);
        set_word(16'h10c, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h10e, 16'h0200);
        set_word(16'h110, 16'h7014); // MOVEQ #20,D0
        set_word(16'h112, 16'h4198); // CHK.W (A0)+,D0
        set_word(16'h114, 16'h4e72); // must not be reached
        set_word(16'h116, 16'h2700);

        // Preserve evidence from both stacked SR values before the handler
        // itself changes flags.  PRM 4-68/4-69 defines N on either trapping
        // path: set for Dn<0, clear for Dn>bound.
        set_word(16'h180, 16'h8657); // OR.W (SP),D3
        set_word(16'h182, 16'h5281); // ADDQ.L #1,D1
        set_word(16'h184, 16'h0c81); // CMPI.L #1,D1
        set_word(16'h186, 16'h0000);
        set_word(16'h188, 16'h0001);
        set_word(16'h18a, 16'h6602); // BNE.S second_trap
        set_word(16'h18c, 16'h4e73); // RTE
        set_word(16'h18e, 16'h4e72); // second_trap: STOP #$2700
        set_word(16'h190, 16'h2700);

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        repeat (2) @(negedge clk);

        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0192);
        assert (debug_data_registers[0*32 +: 32] == 32'd20);
        assert (debug_data_registers[1*32 +: 32] == 32'd2);
        assert (debug_data_registers[3*32 +: 16] == 16'h2708);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0202);
        assert (retired_chk_count == 1);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2700);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0114);

        $display("PASS: M00 CHK.W signed bounds, trap PC/N and EA update");
        $finish;
    end
endmodule
