module mx68k_core_cmpm_fault_tb;
    import mx68k_arch_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
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
    integer cycles;

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
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 3000)
                $fatal(1, "MX68K CMPM fault checkpoint test timed out");
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

    task automatic prepare_case(
        input logic [31:0] source_address,
        input logic [31:0] destination_address,
        input logic [15:0] cmpm_opcode
    );
        begin
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);
            set_data_long(MX_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);
            set_data_long(MX_VECTOR_ADDRESS_ERROR * 4, 32'h0000_0180);
            set_instruction_word('h100, 16'h207c);
            set_instruction_word('h102, source_address[31:16]);
            set_instruction_word('h104, source_address[15:0]);
            set_instruction_word('h106, 16'h227c);
            set_instruction_word('h108, destination_address[31:16]);
            set_instruction_word('h10a, destination_address[15:0]);
            set_instruction_word('h10c, cmpm_opcode);
            set_instruction_word('h10e, 16'h4e72);
            set_instruction_word('h110, 16'h2700);
            set_instruction_word('h180, 16'h4e72);
            set_instruction_word('h182, 16'h2700);
            data_ram.storage['h200] = 8'h12;
            data_ram.storage['h201] = 8'h34;
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            while (!stopped && !faulted)
                @(negedge clk);
            repeat (2) @(negedge clk);
            assert (stopped && !faulted && !terminal_exception.valid);
            assert (debug_pc == 32'h0000_0184);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;

        // Source bus fault: neither postincrement checkpoint has completed.
        prepare_case(32'h0000_0400, 32'h0000_0200, 16'hb308);
        assert (debug_address_registers[0*32 +: 32] == 32'h400);
        assert (debug_address_registers[1*32 +: 32] == 32'h200);

        // Destination bus fault: source read/checkpoint completed, destination
        // postincrement and condition-code commit did not.
        prepare_case(32'h0000_0200, 32'h0000_0400, 16'hb308);
        assert (debug_address_registers[0*32 +: 32] == 32'h201);
        assert (debug_address_registers[1*32 +: 32] == 32'h400);

        // Odd word source is rejected before its read and before checkpoint.
        prepare_case(32'h0000_0201, 32'h0000_0220, 16'hb348);
        assert (debug_address_registers[0*32 +: 32] == 32'h201);
        assert (debug_address_registers[1*32 +: 32] == 32'h220);

        // Odd word destination is diagnosed only after the successful source
        // word and its visible postincrement.
        prepare_case(32'h0000_0200, 32'h0000_0221, 16'hb348);
        assert (debug_address_registers[0*32 +: 32] == 32'h202);
        assert (debug_address_registers[1*32 +: 32] == 32'h221);

        $display("PASS: M00 CMPM source/destination bus and alignment checkpoints");
        $finish;
    end
endmodule
