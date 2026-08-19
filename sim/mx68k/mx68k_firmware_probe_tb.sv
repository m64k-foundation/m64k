module mx68k_firmware_probe_tb;
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
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic uart_rx_valid;
    logic [7:0] uart_rx_data;
    logic uart_rx_ready;
    logic uart_irq;
    logic timer_irq;
    logic reset_devices_n;

    string firmware_hex;
    integer cycles;
    integer retired;
    logic bus_trace;
    logic line_start;
    logic prompt_marker;
    logic firmware_ready;
    integer prompt_count;
    integer help_match;
    logic help_seen;

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if core_dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if main_ram_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if high_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if unused_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = timer_irq || uart_irq;
    assign irq_bus.level = timer_irq ? 3'd6 : uart_irq ? 3'd5 : 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    mx68k_core_m00 #(.QUEUE_WORDS(16)) core (
        .clk, .rst_n,
        .stopped, .faulted, .terminal_exception,
        .retire_valid, .retire_pc, .retire_instruction_id,
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp,
        .debug_data_registers, .debug_address_registers,
        .reset_devices_n,
        .irq(irq_bus),
        .imem(imem_bus), .dmem(core_dmem_bus)
    );

    // The bootloader executes from the 64 KiB high window. A separate copy is
    // intentional: instruction and data ports remain independent as they will
    // be with private L1 caches.
    mx68k_ram #(
        .BASE_ADDR(32'h00ff_0000), .MEM_BYTES(65536), .CLEAR_ON_INIT(1'b0)
    ) instruction_memory (
        .clk, .rst_n, .mem(imem_bus)
    );

    mx68k_router_3 #(
        .PORT0_BASE(32'h0000_0000), .PORT0_MASK(32'hff80_0000),
        .PORT1_BASE(32'h00ff_0000), .PORT1_MASK(32'hffff_0000),
        .PORT2_ENABLE(1'b0)
    ) data_map (
        .clk, .rst_n, .upstream(core_dmem_bus),
        .port0(main_ram_bus), .port1(high_bus), .port2(unused_bus)
    );

    // The current board ABI starts SSP at 0x00800000. Model the complete
    // 8 MiB RAM here so the first predecrement stack access lands at
    // 0x007ffffc. The architectural fabric remains 32-bit/4-GiB capable;
    // this is only the populated-memory profile used by this firmware.
    mx68k_ram #(.MEM_BYTES(8 * 1024 * 1024), .CLEAR_ON_INIT(1'b0)) main_memory (
        .clk, .rst_n, .mem(main_ram_bus)
    );
    mx68k_mackerel_f_high_model #(.PRINT_TX(1'b1)) high_memory (
        .clk, .rst_n, .timer_time_scale(32'd1),
        .rx_valid(uart_rx_valid), .rx_data(uart_rx_data),
        .rx_ready(uart_rx_ready),
        .tx_valid(uart_tx_valid), .tx_data(uart_tx_data),
        .uart_irq, .timer_irq,
        .mem(high_bus)
    );
    mx68k_ram #(.BASE_ADDR(32'hdead_0000), .MEM_BYTES(16)) unused_target (
        .clk, .rst_n, .mem(unused_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic send_uart_byte(input logic [7:0] value);
        begin
            while (!uart_rx_ready)
                @(negedge clk);
            uart_rx_data = value;
            uart_rx_valid = 1'b1;
            @(negedge clk);
            uart_rx_valid = 1'b0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retired <= 0;
            line_start <= 1'b1;
            prompt_marker <= 1'b0;
            firmware_ready <= 1'b0;
            prompt_count <= 0;
            help_match <= 0;
            help_seen <= 1'b0;
        end else begin
            cycles <= cycles + 1;
            if (retire_valid)
                retired <= retired + 1;
            if (uart_tx_valid) begin
                if (prompt_marker && (uart_tx_data == 8'h20)) begin
                    firmware_ready <= 1'b1;
                    prompt_count <= prompt_count + 1;
                end
                prompt_marker <= line_start && (uart_tx_data == 8'h3e);
                if ((uart_tx_data == 8'h0d) || (uart_tx_data == 8'h0a))
                    line_start <= 1'b1;
                else
                    line_start <= 1'b0;
                case (help_match)
                    0: help_match <= (uart_tx_data == "S") ? 1 : 0;
                    1: help_match <= (uart_tx_data == "h") ? 2 : 0;
                    2: help_match <= (uart_tx_data == "o") ? 3 : 0;
                    3: help_match <= (uart_tx_data == "w") ? 4 : 0;
                    4: help_match <= (uart_tx_data == " ") ? 5 : 0;
                    5: help_match <= (uart_tx_data == "t") ? 6 : 0;
                    6: help_match <= (uart_tx_data == "h") ? 7 : 0;
                    7: help_match <= (uart_tx_data == "i") ? 8 : 0;
                    8: help_match <= (uart_tx_data == "s") ? 9 : 0;
                    9: help_match <= (uart_tx_data == " ") ? 10 : 0;
                    10: help_match <= (uart_tx_data == "h") ? 11 : 0;
                    11: help_match <= (uart_tx_data == "e") ? 12 : 0;
                    12: help_match <= (uart_tx_data == "l") ? 13 : 0;
                    13: begin
                        if (uart_tx_data == "p")
                            help_seen <= 1'b1;
                        help_match <= 0;
                    end
                    default: help_match <= 0;
                endcase
            end
            if (bus_trace) begin
                if (imem_bus.req_valid && imem_bus.req_ready)
                    $display("I REQ addr=%08x txn=%x src=%x",
                             imem_bus.req.addr, imem_bus.req.txn_id,
                             imem_bus.req.source);
                if (imem_bus.rsp_valid && imem_bus.rsp_ready)
                    $display("I RSP fault=%x txn=%x src=%x data0=%04x",
                             imem_bus.rsp.fault, imem_bus.rsp.txn_id,
                             imem_bus.rsp.source,
                             {imem_bus.rsp.rdata[7:0],
                              imem_bus.rsp.rdata[15:8]});
                if (core_dmem_bus.req_valid && core_dmem_bus.req_ready)
                    $display("D REQ addr=%08x command=%x txn=%x src=%x D0=%08x D1=%08x A1=%08x A2=%08x",
                             core_dmem_bus.req.addr,
                             core_dmem_bus.req.command,
                             core_dmem_bus.req.txn_id,
                             core_dmem_bus.req.source,
                             debug_data_registers[0*32 +: 32],
                             debug_data_registers[1*32 +: 32],
                             debug_address_registers[1*32 +: 32],
                             debug_address_registers[2*32 +: 32]);
                if (core_dmem_bus.rsp_valid && core_dmem_bus.rsp_ready)
                    $display("D RSP fault=%x txn=%x src=%x",
                             core_dmem_bus.rsp.fault,
                             core_dmem_bus.rsp.txn_id,
                             core_dmem_bus.rsp.source);
                if (retire_valid)
                    $display("RETIRE pc=%08x id=%0d next=%08x sp=%08x D0=%08x D1=%08x D2=%08x D3=%08x D4=%08x D5=%08x D6=%08x D7=%08x A0=%08x A1=%08x A2=%08x A3=%08x A4=%08x A5=%08x A6=%08x",
                             retire_pc, retire_instruction_id,
                             debug_pc, debug_ssp,
                             debug_data_registers[0*32 +: 32],
                             debug_data_registers[1*32 +: 32],
                             debug_data_registers[2*32 +: 32],
                             debug_data_registers[3*32 +: 32],
                             debug_data_registers[4*32 +: 32],
                             debug_data_registers[5*32 +: 32],
                             debug_data_registers[6*32 +: 32],
                             debug_data_registers[7*32 +: 32],
                             debug_address_registers[0*32 +: 32],
                             debug_address_registers[1*32 +: 32],
                             debug_address_registers[2*32 +: 32],
                             debug_address_registers[3*32 +: 32],
                             debug_address_registers[4*32 +: 32],
                             debug_address_registers[5*32 +: 32],
                             debug_address_registers[6*32 +: 32]);
            end
            if ((cycles > 1_000_000) && !firmware_ready)
                $fatal(1, "firmware probe timed out at PC=%08x D1=%08x A0=%08x retired=%0d",
                       debug_pc, debug_data_registers[1*32 +: 32],
                       debug_address_registers[0*32 +: 32], retired);
        end
    end

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        retired = 0;
        bus_trace = $test$plusargs("BUS_TRACE");
        line_start = 1'b1;
        prompt_marker = 1'b0;
        firmware_ready = 1'b0;
        prompt_count = 0;
        help_match = 0;
        help_seen = 1'b0;
        uart_rx_valid = 1'b0;
        uart_rx_data = '0;
        if (!$value$plusargs("FIRMWARE_HEX=%s", firmware_hex))
            $fatal(1, "use +FIRMWARE_HEX=/path/to/bootloader.byte.hex");

        $readmemh(firmware_hex, instruction_memory.storage);
        $readmemh(firmware_hex, high_memory.storage);
        // Model the reset ROM shadow for the first vector-line fetch. Later
        // writes to address zero naturally target main RAM.
        for (int index = 0; index < 16; index = index + 1)
            main_memory.storage[index] = high_memory.storage[index];

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        while (!stopped && !faulted && !firmware_ready)
            @(negedge clk);

        if (firmware_ready) begin
            send_uart_byte("h");
            send_uart_byte("e");
            send_uart_byte("l");
            send_uart_byte("p");
            send_uart_byte(8'h0d);
            while (!stopped && !faulted &&
                   !(help_seen && (prompt_count >= 2)) &&
                   (cycles < 2_000_000))
                @(negedge clk);
        end
        repeat (2) @(negedge clk);

        if (help_seen && (prompt_count >= 2)) begin
            $display("MX68K_FIRMWARE_COMMAND_READY pc=%08x retired=%0d command=help",
                     debug_pc, retired);
        end else if (faulted) begin
            $fatal(1, "firmware fault pc=%08x vector=%0d opcode=%04x address=%08x retired=%0d sp=%08x",
                     terminal_exception.instruction_pc,
                     terminal_exception.vector,
                     terminal_exception.opcode,
                     terminal_exception.logical_address,
                     retired, debug_ssp);
        end else if (firmware_ready) begin
            $fatal(1, "firmware accepted boot but not scripted help command at PC=%08x retired=%0d",
                   debug_pc, retired);
        end else begin
            $display("MX68K_FIRMWARE_STOP pc=%08x retired=%0d", debug_pc,
                     retired);
        end
        $finish;
    end
endmodule
