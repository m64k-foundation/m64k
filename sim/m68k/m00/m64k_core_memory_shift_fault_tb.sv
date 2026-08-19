module m64k_core_memory_shift_fault_tb;
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
    m64k_ram #(
        .MEM_BYTES(1024),
        .INJECT_FAULT_ENABLE(1'b1),
        .INJECT_FAULT_ADDR(32'h0000_0200),
        .INJECT_FAULT_WRITE(1'b1)
    ) data_ram (
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
            if (cycles > 3000)
                $fatal(1, "memory shift write-fault test timed out");
        end
    end

    task automatic set_instruction_word(input integer address,
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

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        set_data_long(0, 32'h0000_0380);
        set_data_long(4, 32'h0000_0100);
        set_data_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);

        set_instruction_word(16'h100, 16'h44fc); // MOVE.W #$001f,CCR
        set_instruction_word(16'h102, 16'h001f);
        set_instruction_word(16'h104, 16'h207c); // MOVEA.L #$0200,A0
        set_instruction_word(16'h106, 16'h0000);
        set_instruction_word(16'h108, 16'h0200);
        set_instruction_word(16'h10a, 16'he0d8); // ASR.W (A0)+
        set_instruction_word(16'h10c, 16'h4e72); // must not execute
        set_instruction_word(16'h10e, 16'h2700);
        set_instruction_word(16'h180, 16'h4e72); // vector-2 handler
        set_instruction_word(16'h182, 16'h271f);
        data_ram.storage[16'h200] = 8'h80;
        data_ram.storage[16'h201] = 8'h01;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        wait (stopped || faulted);
        repeat (2) @(negedge clk);

        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0184);
        assert (debug_address_registers[0*32 +: 32] == 32'h0000_0200);
        assert ({data_ram.storage[16'h200], data_ram.storage[16'h201]} ==
                16'h8001);

        // MC68000 group-0 frame: SSW, fault address, IR, SR and PC.  The
        // write fault occurs before postincrement, CCR and memory commit.
        assert (debug_ssp == 32'h0000_0372);
        assert ({data_ram.storage[16'h372], data_ram.storage[16'h373]} ==
                16'h000d); // data/write cycle status
        assert ({data_ram.storage[16'h374], data_ram.storage[16'h375],
                 data_ram.storage[16'h376], data_ram.storage[16'h377]} ==
                32'h0000_0200);
        assert ({data_ram.storage[16'h378], data_ram.storage[16'h379]} ==
                16'he0d8);
        assert ({data_ram.storage[16'h37a], data_ram.storage[16'h37b]} ==
                16'h271f); // pre-shift SR: computed CCR was not committed
        assert ({data_ram.storage[16'h37c], data_ram.storage[16'h37d],
                 data_ram.storage[16'h37e], data_ram.storage[16'h37f]} ==
                32'h0000_010c);

        $display("PASS: memory shift write fault suppresses RMW/address/flags commit");
        $finish;
    end
endmodule
