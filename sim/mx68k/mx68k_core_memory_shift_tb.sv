module mx68k_core_memory_shift_tb;
    import mx68k_arch_pkg::*;

    logic clk, rst_n, reset_devices_n, stopped, faulted, retire_valid;
    logic [31:0] retire_pc, debug_pc, debug_usp, debug_ssp;
    logic [7:0] retire_instruction_id;
    logic [15:0] debug_sr;
    logic [8*32-1:0] debug_data_registers, debug_address_registers;
    mx_exception_t terminal_exception;
    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    mx68k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n, .stopped, .faulted,
        .terminal_exception, .retire_valid, .retire_pc,
        .retire_instruction_id, .debug_pc, .debug_sr, .debug_usp,
        .debug_ssp, .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );
    mx68k_ram #(.MEM_BYTES(512)) instruction_ram(.clk, .rst_n, .mem(imem_bus));
    mx68k_ram #(.MEM_BYTES(1024)) data_ram(.clk, .rst_n, .mem(dmem_bus));

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    task automatic word_i(input integer address, input logic [15:0] value);
        instruction_ram.storage[address] = value[15:8];
        instruction_ram.storage[address + 1] = value[7:0];
    endtask
    task automatic word_d(input integer address, input logic [15:0] value);
        data_ram.storage[address] = value[15:8];
        data_ram.storage[address + 1] = value[7:0];
    endtask
    task automatic long_d(input integer address, input logic [31:0] value);
        data_ram.storage[address] = value[31:24];
        data_ram.storage[address + 1] = value[23:16];
        data_ram.storage[address + 2] = value[15:8];
        data_ram.storage[address + 3] = value[7:0];
    endtask
    task automatic wait_retire(input logic [31:0] pc,
                               input logic [15:0] value,
                               input logic [15:0] sr,
                               input logic [31:0] address);
        while (!(retire_valid && retire_pc == pc)) @(negedge clk);
        assert ({data_ram.storage[address], data_ram.storage[address + 1]} ==
                value);
        assert (debug_sr == sr);
    endtask

    integer cycles;
    always_ff @(posedge clk) begin
        if (!rst_n) cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 3000) $fatal(1, "memory shift timeout");
        end
    end

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);
        long_d(0, 32'h0000_0380);
        long_d(4, 32'h0000_0100);
        word_d('h200, 16'h8001); // ASR -> c000
        word_d('h202, 16'h4001); // ASL -> 8002
        word_d('h204, 16'h0001); // LSR -> 0000
        word_d('h206, 16'h8000); // LSL -> 0000
        word_d('h208, 16'h0000); // ROXR with X=1 -> 8000
        word_d('h20a, 16'h8000); // ROXL with X=0 -> 0000
        word_d('h20c, 16'h0001); // ROR -> 8000
        word_d('h20e, 16'h8000); // ROL -> 0001

        word_i('h100, 16'h207c); word_i('h102, 16'h0000);
        word_i('h104, 16'h0200); // MOVEA.L #$200,A0
        word_i('h106, 16'he0d8); // ASR.W (A0)+
        word_i('h108, 16'he1d8); // ASL.W (A0)+
        word_i('h10a, 16'he2d8); // LSR.W (A0)+
        word_i('h10c, 16'he3d8); // LSL.W (A0)+
        word_i('h10e, 16'he4d8); // ROXR.W (A0)+
        word_i('h110, 16'he5d8); // ROXL.W (A0)+
        word_i('h112, 16'he6d8); // ROR.W (A0)+
        word_i('h114, 16'he7d8); // ROL.W (A0)+
        word_i('h116, 16'h4e72); word_i('h118, 16'h2700);
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire('h106, 16'hc000, 16'h2719, 'h200);
        wait_retire('h108, 16'h8002, 16'h270a, 'h202);
        wait_retire('h10a, 16'h0000, 16'h2715, 'h204);
        wait_retire('h10c, 16'h0000, 16'h2715, 'h206);
        wait_retire('h10e, 16'h8000, 16'h2708, 'h208);
        wait_retire('h110, 16'h0000, 16'h2715, 'h20a);
        wait_retire('h112, 16'h8000, 16'h2719, 'h20c);
        wait_retire('h114, 16'h0001, 16'h2711, 'h20e);
        assert (debug_address_registers[31:0] == 32'h0000_0210);
        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);
        $display("PASS: all M00 word memory shifts/rotates use ordered RMW");
        $finish;
    end
endmodule
