module mx68k_core_tas_tb;
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;

    logic clk;
    logic rst_n;
    logic stopped;
    logic faulted;
    logic reset_devices_n;
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
        .reset_devices_n,
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
    integer atomic_accesses;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            atomic_accesses <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.command == MX_MEM_ATOMIC)) begin
                assert (dmem_bus.req.atomic_op == MX_ATOMIC_OR);
                assert (dmem_bus.req.size == MX_SIZE_BYTE);
                assert (dmem_bus.req.ordered && dmem_bus.req.lock);
                assert ($onehot(dmem_bus.req.wstrb));
                assert (dmem_bus.req.wdata[
                    dmem_bus.req.addr[3:0]*8 +: 8] == 8'h80);
                atomic_accesses <= atomic_accesses + 1;
            end
            if (cycles > 2000)
                $fatal(1, "MX68K TAS test timed out");
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
            assert (!stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0100);
        data_ram.storage[10'h200] = 8'h00;
        data_ram.storage[10'h220] = 8'h01;
        data_ram.storage[10'h23f] = 8'h80;
        data_ram.storage[10'h255] = 8'h7f;
        data_ram.storage[10'h26a] = 8'hff;
        data_ram.storage[10'h280] = 8'h55;
        data_ram.storage[10'h290] = 8'h80;
        data_ram.storage[10'h2fe] = 8'h01;

        set_word(16'h100, 16'h44fc); // MOVE.W #$1f,CCR
        set_word(16'h102, 16'h001f);
        set_word(16'h104, 16'h203c); // MOVE.L #$12345600,D0
        set_word(16'h106, 16'h1234);
        set_word(16'h108, 16'h5600);
        set_word(16'h10a, 16'h4ac0); // TAS D0: flags test original zero
        set_word(16'h10c, 16'h207c); // MOVEA.L #$0200,A0
        set_word(16'h10e, 16'h0000);
        set_word(16'h110, 16'h0200);
        set_word(16'h112, 16'h4ad0); // TAS (A0)
        set_word(16'h114, 16'h227c); // MOVEA.L #$0220,A1
        set_word(16'h116, 16'h0000);
        set_word(16'h118, 16'h0220);
        set_word(16'h11a, 16'h4ad9); // TAS (A1)+
        set_word(16'h11c, 16'h247c); // MOVEA.L #$0240,A2
        set_word(16'h11e, 16'h0000);
        set_word(16'h120, 16'h0240);
        set_word(16'h122, 16'h4ae2); // TAS -(A2)
        set_word(16'h124, 16'h267c); // MOVEA.L #$0250,A3
        set_word(16'h126, 16'h0000);
        set_word(16'h128, 16'h0250);
        set_word(16'h12a, 16'h4aeb); // TAS 5(A3)
        set_word(16'h12c, 16'h0005);
        set_word(16'h12e, 16'h287c); // MOVEA.L #$0260,A4
        set_word(16'h130, 16'h0000);
        set_word(16'h132, 16'h0260);
        set_word(16'h134, 16'h2a3c); // MOVE.L #4,D5
        set_word(16'h136, 16'h0000);
        set_word(16'h138, 16'h0004);
        set_word(16'h13a, 16'h4af4); // TAS 6(A4,D5.W)
        set_word(16'h13c, 16'h5006);
        set_word(16'h13e, 16'h4af8); // TAS $0280.W
        set_word(16'h140, 16'h0280);
        set_word(16'h142, 16'h4af9); // TAS $00000290.L
        set_word(16'h144, 16'h0000);
        set_word(16'h146, 16'h0290);
        set_word(16'h148, 16'h4ae7); // TAS -(A7): byte step is two
        set_word(16'h14a, 16'h60fe);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_010a);
        assert (debug_data_registers[31:0] == 32'h1234_5680);
        assert (debug_sr[4:0] == 5'b1_0100); // X=1, original Z=1

        wait_retire(32'h0000_0112);
        assert (data_ram.storage[10'h200] == 8'h80);
        assert (debug_sr[4:0] == 5'b1_0100); // X=1, original Z=1

        wait_retire(32'h0000_011a);
        assert (data_ram.storage[10'h220] == 8'h81);
        assert (debug_address_registers[1*32 +: 32] == 32'h0000_0221);
        assert (debug_sr[4:0] == 5'b1_0000);

        wait_retire(32'h0000_0122);
        assert (data_ram.storage[10'h23f] == 8'h80);
        assert (debug_address_registers[2*32 +: 32] == 32'h0000_023f);
        assert (debug_sr[4:0] == 5'b1_1000);

        wait_retire(32'h0000_012a);
        assert (data_ram.storage[10'h255] == 8'hff);
        assert (debug_sr[4:0] == 5'b1_0000);

        wait_retire(32'h0000_013a);
        assert (data_ram.storage[10'h26a] == 8'hff);
        assert (debug_sr[4:0] == 5'b1_1000);

        wait_retire(32'h0000_013e);
        assert (data_ram.storage[10'h280] == 8'hd5);
        assert (debug_sr[4:0] == 5'b1_0000);

        wait_retire(32'h0000_0142);
        assert (data_ram.storage[10'h290] == 8'h80);
        assert (debug_sr[4:0] == 5'b1_1000);

        wait_retire(32'h0000_0148);
        assert (data_ram.storage[10'h2fe] == 8'h81);
        assert (debug_ssp == 32'h0000_02fe);
        assert (debug_sr[4:0] == 5'b1_0000); // original positive/nonzero
        assert (atomic_accesses == 8);

        // A faulting postincrement TAS must be classified as a write-side
        // group-0 access fault, must not update An or CCR, and must not retire.
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        set_data_long(0, 32'h0000_0300);
        set_data_long(4, 32'h0000_0180);
        set_data_long(MX_VECTOR_ACCESS_FAULT * 4, 32'h0000_01e0);
        set_word(16'h180, 16'h44fc); // MOVE.W #$1f,CCR
        set_word(16'h182, 16'h001f);
        set_word(16'h184, 16'h207c); // MOVEA.L #$0500,A0
        set_word(16'h186, 16'h0000);
        set_word(16'h188, 16'h0500);
        set_word(16'h18a, 16'h4ad8); // TAS (A0)+: outside the RAM
        set_word(16'h18c, 16'h4e72); // must not execute
        set_word(16'h18e, 16'h2700);
        set_word(16'h1e0, 16'h4e72); // vector-2 handler
        set_word(16'h1e2, 16'h271f);
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_01e4 && debug_sr == 16'h271f);
        assert (debug_address_registers[31:0] == 32'h0000_0500);
        assert (debug_ssp == 32'h0000_02f2);
        assert ({data_ram.storage[10'h2f2], data_ram.storage[10'h2f3]} ==
                16'h000d); // M00 group-0 data/write cycle status
        assert ({data_ram.storage[10'h2f4], data_ram.storage[10'h2f5],
                 data_ram.storage[10'h2f6], data_ram.storage[10'h2f7]} ==
                32'h0000_0500);
        assert ({data_ram.storage[10'h2f8], data_ram.storage[10'h2f9]} ==
                16'h4ad8);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_018c);
        assert (atomic_accesses == 1);

        $display("PASS: M00 TAS flags, all legal EA classes, atomic memory, A7 byte step, and access fault");
        $finish;
    end
endmodule
