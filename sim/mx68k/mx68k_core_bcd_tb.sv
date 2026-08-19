module mx68k_core_bcd_tb;
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;

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
    logic reset_devices_n;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    logic [31:0] operand_bus_address [0:15];
    logic operand_bus_write [0:15];
    integer operand_bus_count;
    integer cycles;

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
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp, .reset_devices_n,
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

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            operand_bus_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr >= 32'h0000_0180)) begin
                operand_bus_address[operand_bus_count] <= dmem_bus.req.addr;
                operand_bus_write[operand_bus_count] <=
                    (dmem_bus.req.command == MX_MEM_WRITE);
                operand_bus_count <= operand_bus_count + 1;
            end
            if (cycles > 2500)
                $fatal(1, "MX68K ABCD/SBCD test timed out");
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

    task automatic set_data_byte(input integer address,
                                 input logic [7:0] value);
        data_ram.storage[address] = value;
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

        set_word('h100, 16'h203c); // MOVE.L #$12340099,D0
        set_word('h102, 16'h1234);
        set_word('h104, 16'h0099);
        set_word('h106, 16'h7200); // MOVEQ #0,D1
        set_word('h108, 16'h44fc); // X=N=Z=V=1, C=0
        set_word('h10a, 16'h001e);
        set_word('h10c, 16'hc101); // ABCD D1,D0 -> $00, X=Z=C=1
        set_word('h10e, 16'hc101); // ABCD D1,D0 -> $01, X=Z=C=0

        set_word('h110, 16'h243c); // MOVE.L #$aaaa0000,D2
        set_word('h112, 16'haaaa);
        set_word('h114, 16'h0000);
        set_word('h116, 16'h7601); // MOVEQ #1,D3
        set_word('h118, 16'h44fc); // X=0,N=0,Z=1,V=1,C=0
        set_word('h11a, 16'h0006);
        set_word('h11c, 16'h8503); // SBCD D3,D2 -> $99, borrow

        set_word('h11e, 16'h207c); // MOVEA.L #$220,A0
        set_word('h120, 16'h0000);
        set_word('h122, 16'h0220);
        set_word('h124, 16'h227c); // MOVEA.L #$240,A1
        set_word('h126, 16'h0000);
        set_word('h128, 16'h0240);
        set_word('h12a, 16'h44fc); // X=1,Z=1
        set_word('h12c, 16'h0014);
        set_word('h12e, 16'hc308); // ABCD -(A0),-(A1): 45+54+1=00

        set_word('h130, 16'h247c); // MOVEA.L #$260,A2
        set_word('h132, 16'h0000);
        set_word('h134, 16'h0260);
        set_word('h136, 16'h44fc); // X=0,Z=1
        set_word('h138, 16'h0004);
        set_word('h13a, 16'h850a); // SBCD -(A2),-(A2): 00-01=99

        set_word('h13c, 16'h207c); // MOVEA.L #$2a0,A0
        set_word('h13e, 16'h0000);
        set_word('h140, 16'h02a0);
        set_word('h142, 16'h2e7c); // MOVEA.L #$300,A7
        set_word('h144, 16'h0000);
        set_word('h146, 16'h0300);
        set_word('h148, 16'h44fc); // X=0,Z=1
        set_word('h14a, 16'h0004);
        set_word('h14c, 16'hcf08); // ABCD -(A0),-(A7), A7 byte step=2
        set_word('h14e, 16'h283c); // MOVE.L #$bbbb0045,D4
        set_word('h150, 16'hbbbb);
        set_word('h152, 16'h0045);
        set_word('h154, 16'h44fc); // X=0,N=1,Z=1,V=0,C=0
        set_word('h156, 16'h000c);
        set_word('h158, 16'h4804); // NBCD D4 -> $55, decimal borrow
        set_word('h15a, 16'h267c); // MOVEA.L #$2c0,A3
        set_word('h15c, 16'h0000);
        set_word('h15e, 16'h02c0);
        set_word('h160, 16'h44fc); // X=1,Z=1
        set_word('h162, 16'h0014);
        set_word('h164, 16'h4823); // NBCD -(A3): 0-01-1=98
        set_word('h166, 16'h60fe);

        set_data_byte('h21f, 8'h45);
        set_data_byte('h23f, 8'h54);
        set_data_byte('h25f, 8'h01);
        set_data_byte('h25e, 8'h00);
        set_data_byte('h29f, 8'h00);
        set_data_byte('h2fe, 8'h00);
        set_data_byte('h2bf, 8'h01);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_010c)))
            @(negedge clk);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_0000);
        assert (debug_sr[4:0] == 5'b1_1111);

        while (!(retire_valid && (retire_pc == 32'h0000_010e)))
            @(negedge clk);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_0001);
        assert (debug_sr[4:0] == 5'b0_1010);

        while (!(retire_valid && (retire_pc == 32'h0000_011c)))
            @(negedge clk);
        assert (debug_data_registers[2*32 +: 32] == 32'haaaa_0099);
        assert (debug_sr[4:0] == 5'b1_0011);

        while (!(retire_valid && (retire_pc == 32'h0000_012e)))
            @(negedge clk);
        assert (data_ram.storage['h23f] == 8'h00);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_021f);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_023f);
        assert (debug_sr[4:0] == 5'b1_0101);

        while (!(retire_valid && (retire_pc == 32'h0000_013a)))
            @(negedge clk);
        assert (data_ram.storage['h25e] == 8'h99);
        assert (debug_address_registers[2*32 +: 32] == 32'h0000_025e);
        assert (debug_sr[4:0] == 5'b1_0001);

        while (!(retire_valid && (retire_pc == 32'h0000_014c)))
            @(negedge clk);
        assert (data_ram.storage['h2fe] == 8'h00);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_029f);
        assert (debug_ssp == 32'h0000_02fe);
        assert (debug_sr[4:0] == 5'b0_0100);
        assert (!stopped && !faulted && !terminal_exception.valid);

        while (!(retire_valid && (retire_pc == 32'h0000_0158)))
            @(negedge clk);
        assert (debug_data_registers[4*32 +: 32] == 32'hbbbb_0055);
        assert (debug_sr[4:0] == 5'b1_1001);

        while (!(retire_valid && (retire_pc == 32'h0000_0164)))
            @(negedge clk);
        assert (data_ram.storage['h2bf] == 8'h98);
        assert (debug_address_registers[3*32 +: 32] == 32'h0000_02bf);
        assert (debug_sr[4:0] == 5'b1_0001);
        assert (!stopped && !faulted && !terminal_exception.valid);

        assert (operand_bus_count == 11);
        assert (operand_bus_address[0] == 32'h0000_021f &&
                !operand_bus_write[0]);
        assert (operand_bus_address[1] == 32'h0000_023f &&
                !operand_bus_write[1]);
        assert (operand_bus_address[2] == 32'h0000_023f &&
                operand_bus_write[2]);
        assert (operand_bus_address[3] == 32'h0000_025f &&
                !operand_bus_write[3]);
        assert (operand_bus_address[4] == 32'h0000_025e &&
                !operand_bus_write[4]);
        assert (operand_bus_address[5] == 32'h0000_025e &&
                operand_bus_write[5]);
        assert (operand_bus_address[6] == 32'h0000_029f &&
                !operand_bus_write[6]);
        assert (operand_bus_address[7] == 32'h0000_02fe &&
                !operand_bus_write[7]);
        assert (operand_bus_address[8] == 32'h0000_02fe &&
                operand_bus_write[8]);
        assert (operand_bus_address[9] == 32'h0000_02bf &&
                !operand_bus_write[9]);
        assert (operand_bus_address[10] == 32'h0000_02bf &&
                operand_bus_write[10]);

        $display("PASS: M00 ABCD/SBCD/NBCD packed-BCD semantics");
        $finish;
    end
endmodule
