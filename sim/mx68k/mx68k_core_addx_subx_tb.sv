module mx68k_core_addx_subx_tb;
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
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    logic [31:0] operand_bus_address [0:15];
    logic operand_bus_write [0:15];
    integer operand_bus_count;

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
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            operand_bus_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr >= 32'h0000_0180)) begin
                operand_bus_address[operand_bus_count] <=
                    dmem_bus.req.addr;
                operand_bus_write[operand_bus_count] <=
                    (dmem_bus.req.command == MX_MEM_WRITE);
                operand_bus_count <= operand_bus_count + 1;
            end
            if (cycles > 3000)
                $fatal(1, "MX68K ADDX/SUBX test timed out");
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

    task automatic set_data_word(input integer address,
                                 input logic [15:0] value);
        begin
            data_ram.storage[address + 0] = value[15:8];
            data_ram.storage[address + 1] = value[7:0];
        end
    endtask

    task automatic set_data_byte(input integer address,
                                 input logic [7:0] value);
        begin
            data_ram.storage[address] = value;
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

        set_word('h100, 16'h780a); // MOVEQ #10,D4
        set_word('h102, 16'h7c03); // MOVEQ #3,D6
        set_word('h104, 16'h44fc); // X=1,Z=1
        set_word('h106, 16'h0014);
        set_word('h108, 16'h9986); // SUBX.L D6,D4 -> 6
        set_word('h10a, 16'h203c); // MOVE.L #$ffffffff,D0
        set_word('h10c, 16'hffff);
        set_word('h10e, 16'hffff);
        set_word('h110, 16'h7200); // MOVEQ #0,D1
        set_word('h112, 16'h44fc); // X=1,Z=1
        set_word('h114, 16'h0014);
        set_word('h116, 16'hd181); // ADDX.L D1,D0 -> 0, X=C=Z=1
        set_word('h118, 16'hd181); // ADDX.L D1,D0 -> 1, all flags clear
        set_word('h11a, 16'h243c); // MOVE.L #$123400ff,D2
        set_word('h11c, 16'h1234);
        set_word('h11e, 16'h00ff);
        set_word('h120, 16'h7600); // MOVEQ #0,D3
        set_word('h122, 16'h44fc); // X=1,Z=1
        set_word('h124, 16'h0014);
        set_word('h126, 16'hd503); // ADDX.B D3,D2 -> $12340000
        set_word('h128, 16'hd503); // ADDX.B D3,D2 -> $12340001

        set_word('h12a, 16'h283c); // MOVE.L #$aaaa7fff,D4
        set_word('h12c, 16'haaaa);
        set_word('h12e, 16'h7fff);
        set_word('h130, 16'h7a00); // MOVEQ #0,D5
        set_word('h132, 16'h44fc); // X=1,Z=1
        set_word('h134, 16'h0014);
        set_word('h136, 16'hd945); // ADDX.W D5,D4 -> $aaaa8000

        set_word('h138, 16'h2c3c); // MOVE.L #$11220000,D6
        set_word('h13a, 16'h1122);
        set_word('h13c, 16'h0000);
        set_word('h13e, 16'h7e01); // MOVEQ #1,D7
        set_word('h140, 16'h44fc); // X=1,Z=1
        set_word('h142, 16'h0014);
        set_word('h144, 16'h9d07); // SUBX.B D7,D6 -> $112200fe

        set_word('h146, 16'h203c); // MOVE.L #$face8000,D0
        set_word('h148, 16'hface);
        set_word('h14a, 16'h8000);
        set_word('h14c, 16'h7201); // MOVEQ #1,D1
        set_word('h14e, 16'h44fc); // X=0,Z=1
        set_word('h150, 16'h0004);
        set_word('h152, 16'h9141); // SUBX.W D1,D0 -> $face7fff
        set_word('h154, 16'h207c); // MOVEA.L #$200,A0
        set_word('h156, 16'h0000);
        set_word('h158, 16'h0200);
        set_word('h15a, 16'h227c); // MOVEA.L #$220,A1
        set_word('h15c, 16'h0000);
        set_word('h15e, 16'h0220);
        set_word('h160, 16'h44fc); // X=1,Z=1
        set_word('h162, 16'h0014);
        set_word('h164, 16'hd308); // ADDX.B -(A0),-(A1)

        set_word('h166, 16'h247c); // MOVEA.L #$240,A2
        set_word('h168, 16'h0000);
        set_word('h16a, 16'h0240);
        set_word('h16c, 16'h44fc); // X=0,Z=1
        set_word('h16e, 16'h0004);
        set_word('h170, 16'hd54a); // ADDX.W -(A2),-(A2)

        set_word('h172, 16'h267c); // MOVEA.L #$260,A3
        set_word('h174, 16'h0000);
        set_word('h176, 16'h0260);
        set_word('h178, 16'h287c); // MOVEA.L #$280,A4
        set_word('h17a, 16'h0000);
        set_word('h17c, 16'h0280);
        set_word('h17e, 16'h44fc); // X=1,Z=1
        set_word('h180, 16'h0014);
        set_word('h182, 16'h998b); // SUBX.L -(A3),-(A4)

        set_word('h184, 16'h207c); // MOVEA.L #$2a0,A0
        set_word('h186, 16'h0000);
        set_word('h188, 16'h02a0);
        set_word('h18a, 16'h2e7c); // MOVEA.L #$300,A7
        set_word('h18c, 16'h0000);
        set_word('h18e, 16'h0300);
        set_word('h190, 16'h44fc); // X=0,Z=0
        set_word('h192, 16'h0000);
        set_word('h194, 16'h9f08); // SUBX.B -(A0),-(A7)
        set_word('h196, 16'h60fe);

        set_data_byte('h1ff, 8'hff);
        set_data_byte('h21f, 8'h00);
        set_data_word('h23e, 16'h0001);
        set_data_word('h23c, 16'hffff);
        set_data_long('h25c, 32'h0000_0001);
        set_data_long('h27c, 32'h0000_0000);
        set_data_byte('h29f, 8'h01);
        set_data_byte('h2fe, 8'h05);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        while (!(retire_valid && (retire_pc == 32'h0000_0108)))
            @(negedge clk);
        assert (debug_data_registers[4*32 +: 32] == 32'd6);
        assert (debug_sr[4:0] == 5'b0_0000);

        while (!(retire_valid && (retire_pc == 32'h0000_0116)))
            @(negedge clk);
        assert (debug_data_registers[0*32 +: 32] == 32'd0);
        assert (debug_sr[4:0] == 5'b1_0101);

        while (!(retire_valid && (retire_pc == 32'h0000_0118)))
            @(negedge clk);
        assert (!stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'd1);
        assert (debug_sr[4:0] == 5'b0_0000);

        while (!(retire_valid && (retire_pc == 32'h0000_0126)))
            @(negedge clk);
        assert (debug_data_registers[2*32 +: 32] == 32'h1234_0000);
        assert (debug_sr[4:0] == 5'b1_0101);

        while (!(retire_valid && (retire_pc == 32'h0000_0128)))
            @(negedge clk);
        assert (debug_data_registers[2*32 +: 32] == 32'h1234_0001);
        assert (debug_sr[4:0] == 5'b0_0000);

        while (!(retire_valid && (retire_pc == 32'h0000_0136)))
            @(negedge clk);
        assert (debug_data_registers[4*32 +: 32] == 32'haaaa_8000);
        assert (debug_sr[4:0] == 5'b0_1010);

        while (!(retire_valid && (retire_pc == 32'h0000_0144)))
            @(negedge clk);
        assert (debug_data_registers[6*32 +: 32] == 32'h1122_00fe);
        assert (debug_sr[4:0] == 5'b1_1001);

        while (!(retire_valid && (retire_pc == 32'h0000_0152)))
            @(negedge clk);
        assert (debug_data_registers[0*32 +: 32] == 32'hface_7fff);
        assert (debug_sr[4:0] == 5'b0_0010);

        while (!(retire_valid && (retire_pc == 32'h0000_0164)))
            @(negedge clk);
        assert (data_ram.storage['h21f] == 8'h00);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_01ff);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_021f);
        assert (debug_sr[4:0] == 5'b1_0101);

        while (!(retire_valid && (retire_pc == 32'h0000_0170)))
            @(negedge clk);
        assert ({data_ram.storage['h23c], data_ram.storage['h23d]} ==
                16'h0000);
        assert (debug_address_registers[2*32 +: 32] == 32'h0000_023c);
        assert (debug_sr[4:0] == 5'b1_0101);

        while (!(retire_valid && (retire_pc == 32'h0000_0182)))
            @(negedge clk);
        assert ({data_ram.storage['h27c], data_ram.storage['h27d],
                 data_ram.storage['h27e], data_ram.storage['h27f]} ==
                32'hffff_fffe);
        assert (debug_address_registers[3*32 +: 32] == 32'h0000_025c);
        assert (debug_address_registers[4*32 +: 32] == 32'h0000_027c);
        assert (debug_sr[4:0] == 5'b1_1001);

        while (!(retire_valid && (retire_pc == 32'h0000_0194)))
            @(negedge clk);
        assert (data_ram.storage['h2fe] == 8'h04);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_029f);
        assert (debug_address_registers[7*32 +: 32] == 32'h0000_02fe);
        assert (debug_sr[4:0] == 5'b0_0000);

        assert (operand_bus_count == 12);
        assert (!operand_bus_write[0] &&
                operand_bus_address[0] == 32'h0000_01ff);
        assert (!operand_bus_write[1] &&
                operand_bus_address[1] == 32'h0000_021f);
        assert (operand_bus_write[2] &&
                operand_bus_address[2] == 32'h0000_021f);
        assert (!operand_bus_write[3] &&
                operand_bus_address[3] == 32'h0000_023e);
        assert (!operand_bus_write[4] &&
                operand_bus_address[4] == 32'h0000_023c);
        assert (operand_bus_write[5] &&
                operand_bus_address[5] == 32'h0000_023c);
        assert (!operand_bus_write[6] &&
                operand_bus_address[6] == 32'h0000_025c);
        assert (!operand_bus_write[7] &&
                operand_bus_address[7] == 32'h0000_027c);
        assert (operand_bus_write[8] &&
                operand_bus_address[8] == 32'h0000_027c);
        assert (!operand_bus_write[9] &&
                operand_bus_address[9] == 32'h0000_029f);
        assert (!operand_bus_write[10] &&
                operand_bus_address[10] == 32'h0000_02fe);
        assert (operand_bus_write[11] &&
                operand_bus_address[11] == 32'h0000_02fe);

        $display("PASS: M00 ADDX/SUBX register and predecrement-memory semantics");
        $finish;
    end
endmodule
