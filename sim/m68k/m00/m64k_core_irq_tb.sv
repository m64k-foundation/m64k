module m64k_core_irq_tb;
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
    integer acknowledge_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            acknowledge_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (irq_bus.acknowledge)
                acknowledge_count <= acknowledge_count + 1;
            if (cycles > 3000)
                $fatal(1, "M64K interrupt test timed out");
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

    initial begin
        rst_n = 1'b0;
        irq_bus.request = 1'b0;
        irq_bus.level = 3'd0;
        irq_bus.vector_valid = 1'b0;
        irq_bus.vector = 8'd0;
        cycles = 0;
        acknowledge_count = 0;
        repeat (2) @(negedge clk);

        // SSP=$300, PC=$100, autovector 30 (level 6) -> $180.
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0100);
        set_long(30 * 4, 32'h0000_0180);

        // $100: ANDI.W #$f8ff,SR lowers I from 7 to 0.
        // $104: MOVEQ #1,D1; STOP #$2700.
        instruction_ram.storage[9'h100] = 8'h02;
        instruction_ram.storage[9'h101] = 8'h7c;
        instruction_ram.storage[9'h102] = 8'hf8;
        instruction_ram.storage[9'h103] = 8'hff;
        instruction_ram.storage[9'h104] = 8'h72;
        instruction_ram.storage[9'h105] = 8'h01;
        instruction_ram.storage[9'h106] = 8'h4e;
        instruction_ram.storage[9'h107] = 8'h72;
        instruction_ram.storage[9'h108] = 8'h27;
        instruction_ram.storage[9'h109] = 8'h00;

        // $180: MOVEQ #6,D0; RTE.
        instruction_ram.storage[9'h180] = 8'h70;
        instruction_ram.storage[9'h181] = 8'h06;
        instruction_ram.storage[9'h182] = 8'h4e;
        instruction_ram.storage[9'h183] = 8'h73;

        // Level 6 is present from reset, but must remain masked until ANDI.
        irq_bus.request = 1'b1;
        irq_bus.level = 3'd6;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!irq_bus.acknowledge)
            @(negedge clk);
        assert (irq_bus.acknowledged_level == 3'd6);
        assert (debug_pc == 32'h0000_0104);
        irq_bus.request = 1'b0;

        while (debug_pc != 32'h0000_0180)
            @(negedge clk);
        assert (debug_sr == 16'h2600);
        while (!stopped && !faulted)
            @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (acknowledge_count == 1);
        assert (debug_ssp == 32'h0000_0300);
        assert (debug_data_registers[0*32 +: 32] == 32'd6);
        assert (debug_data_registers[1*32 +: 32] == 32'd1);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2000);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0104);

        // Level 7 uses edge semantics, bypasses mask 7 and wakes STOP.
        rst_n = 1'b0;
        irq_bus.request = 1'b0;
        irq_bus.level = 3'd0;
        repeat (2) @(negedge clk);
        set_long(0, 32'h0000_0300);
        set_long(4, 32'h0000_0120);
        set_long(31 * 4, 32'h0000_01a0);

        // First STOP waits for IRQ7. RTE returns to the second STOP.
        instruction_ram.storage[9'h120] = 8'h4e;
        instruction_ram.storage[9'h121] = 8'h72;
        instruction_ram.storage[9'h122] = 8'h27;
        instruction_ram.storage[9'h123] = 8'h00;
        instruction_ram.storage[9'h124] = 8'h4e;
        instruction_ram.storage[9'h125] = 8'h72;
        instruction_ram.storage[9'h126] = 8'h27;
        instruction_ram.storage[9'h127] = 8'h00;
        instruction_ram.storage[9'h1a0] = 8'h74;
        instruction_ram.storage[9'h1a1] = 8'h07;
        instruction_ram.storage[9'h1a2] = 8'h4e;
        instruction_ram.storage[9'h1a3] = 8'h73;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted)
            @(negedge clk);
        assert (stopped && debug_pc == 32'h0000_0124);
        irq_bus.request = 1'b1;
        irq_bus.level = 3'd7;
        while (!irq_bus.acknowledge)
            @(negedge clk);
        assert (irq_bus.acknowledged_level == 3'd7);
        irq_bus.request = 1'b0;
        while (!stopped && !faulted)
            @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0128);
        assert (debug_data_registers[2*32 +: 32] == 32'd7);
        assert (acknowledge_count == 1);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2700);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0124);

        $display("PASS: M00 masked/autovectored IRQ, level-7 edge and STOP wake");
        $finish;
    end
endmodule
