module m64k_core_cmpm_tb;
    import m64k_pkg::*;
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
    logic [31:0] operand_address [0:15];
    integer operand_count;
    integer cycles;

    m64k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    m64k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    m64k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n, .stopped, .faulted,
        .terminal_exception, .retire_valid, .retire_pc,
        .retire_instruction_id, .debug_pc, .debug_sr, .debug_usp,
        .debug_ssp, .debug_data_registers, .debug_address_registers,
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
        if (!rst_n) begin
            cycles <= 0;
            operand_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr >= 32'h0000_0200)) begin
                operand_address[operand_count] <= dmem_bus.req.addr;
                operand_count <= operand_count + 1;
                assert (dmem_bus.req.command == M64K_MEM_READ);
            end
            if (cycles > 3000)
                $fatal(1, "M64K CMPM test timed out");
        end
    end

    task automatic set_word(input integer address,
                            input logic [15:0] value);
        instruction_ram.storage[address] = value[15:8];
        instruction_ram.storage[address + 1] = value[7:0];
    endtask

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        data_ram.storage[address] = value[31:24];
        data_ram.storage[address + 1] = value[23:16];
        data_ram.storage[address + 2] = value[15:8];
        data_ram.storage[address + 3] = value[7:0];
    endtask

    task automatic wait_retire(input logic [31:0] expected_pc);
        while (!(retire_valid && retire_pc == expected_pc))
            @(negedge clk);
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        operand_count = 0;
        repeat (2) @(negedge clk);
        set_data_long(0, 32'h0000_0380);
        set_data_long(4, 32'h0000_0100);

        set_word('h100, 16'h207c); set_word('h102, 16'h0000);
        set_word('h104, 16'h0200); // A0=$200
        set_word('h106, 16'h227c); set_word('h108, 16'h0000);
        set_word('h10a, 16'h0220); // A1=$220
        set_word('h10c, 16'h003c); set_word('h10e, 16'h0010); // X=1
        set_word('h110, 16'hb308); // CMPM.B (A0)+,(A1)+

        set_word('h112, 16'h247c); set_word('h114, 16'h0000);
        set_word('h116, 16'h0240); // A2=$240
        set_word('h118, 16'hb54a); // CMPM.W (A2)+,(A2)+

        set_word('h11a, 16'h267c); set_word('h11c, 16'h0000);
        set_word('h11e, 16'h0260); // A3=$260
        set_word('h120, 16'h287c); set_word('h122, 16'h0000);
        set_word('h124, 16'h0280); // A4=$280
        set_word('h126, 16'hb98b); // CMPM.L (A3)+,(A4)+

        set_word('h128, 16'h207c); set_word('h12a, 16'h0000);
        set_word('h12c, 16'h02a0); // A0=$2a0
        set_word('h12e, 16'h2e7c); set_word('h130, 16'h0000);
        set_word('h132, 16'h02c0); // A7=$2c0
        set_word('h134, 16'hbf08); // CMPM.B (A0)+,(A7)+
        set_word('h136, 16'h4e72); set_word('h138, 16'h2700);

        data_ram.storage['h200] = 8'h10;
        data_ram.storage['h220] = 8'h20;
        data_ram.storage['h240] = 8'h80;
        data_ram.storage['h241] = 8'h00;
        data_ram.storage['h242] = 8'h7f;
        data_ram.storage['h243] = 8'hff;
        set_data_long('h260, 32'h0000_0001);
        set_data_long('h280, 32'h0000_0000);
        data_ram.storage['h2a0] = 8'h55;
        data_ram.storage['h2c0] = 8'h55;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_0110);
        assert (debug_address_registers[0*32 +: 32] == 32'h201);
        assert (debug_address_registers[1*32 +: 32] == 32'h221);
        assert (debug_sr[4:0] == 5'b1_0000);

        wait_retire(32'h0000_0118);
        assert (debug_address_registers[2*32 +: 32] == 32'h244);
        assert (debug_sr[4:0] == 5'b1_1011);

        wait_retire(32'h0000_0126);
        assert (debug_address_registers[3*32 +: 32] == 32'h264);
        assert (debug_address_registers[4*32 +: 32] == 32'h284);
        assert (debug_sr[4:0] == 5'b1_1001);

        wait_retire(32'h0000_0134);
        assert (debug_address_registers[0*32 +: 32] == 32'h2a1);
        assert (debug_address_registers[7*32 +: 32] == 32'h2c2);
        assert (debug_sr[4:0] == 5'b1_0100);

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (operand_count == 8);
        assert (operand_address[0] == 32'h200 &&
                operand_address[1] == 32'h220);
        assert (operand_address[2] == 32'h240 &&
                operand_address[3] == 32'h242);
        assert (operand_address[4] == 32'h260 &&
                operand_address[5] == 32'h280);
        assert (operand_address[6] == 32'h2a0 &&
                operand_address[7] == 32'h2c0);
        $display("PASS: M00 CMPM ordered reads, flags, alias and A7 byte step");
        $finish;
    end
endmodule
