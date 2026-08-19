module mx68k_firmware_sim_top (
    input  logic clk,
    input  logic rst_n,
    input  logic [31:0] timer_time_scale,

    input  logic       uart_rx_valid,
    input  logic [7:0] uart_rx_data,
    output logic       uart_rx_ready,
    output logic       uart_tx_valid,
    output logic [7:0] uart_tx_data,

    output logic        stopped,
    output logic        faulted,
    output logic [31:0] debug_pc,
    output logic [15:0] debug_sr,
    output logic [31:0] debug_ssp,
    output logic [31:0] debug_d0,
    output logic [31:0] debug_d1,
    output logic [31:0] debug_d2,
    output logic [31:0] debug_d7,
    output logic [31:0] debug_a0,
    output logic [31:0] debug_a1,
    output logic [31:0] debug_a2,
    output logic [31:0] debug_a3,
    output logic [31:0] debug_a4,
    output logic [31:0] debug_a5,
    output logic [31:0] debug_a6,
    output logic [31:0] debug_a7,
    output logic [7:0]  fault_vector,
    output logic [15:0] fault_opcode,
    output logic [31:0] fault_address,

    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [7:0]  retire_instruction_id,
    output logic        data_bus_valid,
    output logic [31:0] data_bus_address,
    output logic [1:0]  data_bus_command,
    output logic        exception_event_valid,
    output logic [7:0]  exception_event_vector,
    output logic [15:0] exception_event_opcode,
    output logic [31:0] exception_event_pc,
    output logic [31:0] exception_event_address
);
    import mx68k_arch_pkg::*;

    string firmware_hex;
    string image_bin;
    string rom_bin;
    integer image_fd;
    integer image_bytes;
    integer image_load_address;
    integer rom_fd;
    integer rom_bytes;
    integer rom_load_address;
    mx_exception_t terminal_exception;
    logic [31:0] debug_usp;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    logic uart_irq;
    logic timer_irq;
    logic high_uart_rx_ready;
    logic high_uart_tx_valid;
    logic [7:0] high_uart_tx_data;
    logic m08_uart_tx_valid;
    logic [7:0] m08_uart_tx_data;
    logic m08_uart_rx_ready;
    logic m08_compat_enable;
    logic m08_console_active;
    logic m08_irq;
    logic [7:0] m08_irq_vector;
    logic reset_devices_n;

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if main_imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if high_imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if unused_imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if core_dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if main_ram_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if high_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if unused_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = m08_irq || timer_irq || uart_irq;
    assign irq_bus.level = m08_irq ? 3'd1 :
                           timer_irq ? 3'd6 : uart_irq ? 3'd5 : 3'd0;
    assign irq_bus.vector_valid = m08_irq;
    assign irq_bus.vector = m08_irq_vector;

    mx68k_core_m00 #(.QUEUE_WORDS(16)) core (
        .clk, .rst_n, .reset_devices_n,
        .stopped, .faulted, .terminal_exception,
        .retire_valid, .retire_pc, .retire_instruction_id,
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp,
        .debug_data_registers, .debug_address_registers,
        .irq(irq_bus),
        .imem(imem_bus), .dmem(core_dmem_bus)
    );

    mx68k_router_3 #(
        .PORT0_BASE(32'h0000_0000), .PORT0_MASK(32'hff80_0000),
        .PORT1_BASE(32'h00ff_0000), .PORT1_MASK(32'hffff_0000),
        .PORT2_ENABLE(1'b0)
    ) instruction_map (
        .clk, .rst_n, .upstream(imem_bus),
        .port0(main_imem_bus), .port1(high_imem_bus),
        .port2(unused_imem_bus)
    );

    mx68k_ram #(
        .BASE_ADDR(32'h00ff_0000),
        .MEM_BYTES(65536),
        .CLEAR_ON_INIT(1'b0)
    ) instruction_memory (
        .clk, .rst_n, .mem(high_imem_bus)
    );

    mx68k_router_3 #(
        .PORT0_BASE(32'h0000_0000), .PORT0_MASK(32'hff80_0000),
        .PORT1_BASE(32'h00ff_0000), .PORT1_MASK(32'hffff_0000),
        .PORT2_ENABLE(1'b0)
    ) data_map (
        .clk, .rst_n, .upstream(core_dmem_bus),
        .port0(main_ram_bus), .port1(high_bus), .port2(unused_bus)
    );

    // This executable models the current Mackerel-F population. The MX68K
    // fabric and architectural addresses remain 32-bit; a future board top
    // can replace this instance with a larger DDR adapter without changing
    // the CPU contract.
    mx68k_linux_workload_memory #(
        .MEM_BYTES(8 * 1024 * 1024),
        .CLEAR_ON_INIT(1'b0),
        // Direct image preload bypasses the Mackerel-08 ROM, whose
        // uart_init() leaves channel B receiver enabled before Linux entry.
        .RX_ENABLED_ON_RESET(1'b1)
    ) main_memory (
        .clk, .rst_n, .m08_compat_enable,
        .rx_valid(uart_rx_valid && m08_console_active),
        .rx_data(uart_rx_data), .rx_ready(m08_uart_rx_ready),
        .tx_valid(m08_uart_tx_valid), .tx_data(m08_uart_tx_data),
        .irq(m08_irq), .irq_vector(m08_irq_vector),
        .imem(main_imem_bus), .dmem(main_ram_bus)
    );

    mx68k_mackerel_f_high_model #(.PRINT_TX(1'b0)) high_memory (
        .clk, .rst_n, .timer_time_scale,
        .rx_valid(uart_rx_valid && !m08_console_active),
        .rx_data(uart_rx_data),
        .rx_ready(high_uart_rx_ready),
        .tx_valid(high_uart_tx_valid), .tx_data(high_uart_tx_data),
        .uart_irq, .timer_irq,
        .mem(high_bus)
    );

    // A preloaded Mackerel-08 image is launched by the bootloader through the
    // Mackerel-F high UART. Once execution enters low RAM, console input must
    // follow output to the compatibility DUART used by that image.
    assign m08_console_active = m08_compat_enable &&
                                (debug_pc < 32'h0080_0000);
    assign uart_rx_ready = m08_console_active ? m08_uart_rx_ready :
                                               high_uart_rx_ready;
    assign uart_tx_valid = high_uart_tx_valid || m08_uart_tx_valid;
    assign uart_tx_data = m08_uart_tx_valid ? m08_uart_tx_data :
                                             high_uart_tx_data;

    mx68k_ram #(
        .BASE_ADDR(32'hdead_0000), .MEM_BYTES(16)
    ) unused_target (
        .clk, .rst_n, .mem(unused_bus)
    );

    mx68k_ram #(
        .BASE_ADDR(32'hdead_0010), .MEM_BYTES(16)
    ) unused_instruction_target (
        .clk, .rst_n, .mem(unused_imem_bus)
    );

    assign fault_vector = terminal_exception.vector;
    assign fault_opcode = terminal_exception.opcode;
    assign fault_address = terminal_exception.logical_address;
    assign data_bus_valid = core_dmem_bus.req_valid &&
                            core_dmem_bus.req_ready;
    assign data_bus_address = core_dmem_bus.req.addr;
    assign data_bus_command = core_dmem_bus.req.command;
    assign debug_d0 = debug_data_registers[0*32 +: 32];
    assign debug_d1 = debug_data_registers[1*32 +: 32];
    assign debug_d2 = debug_data_registers[2*32 +: 32];
    assign debug_d7 = debug_data_registers[7*32 +: 32];
    assign debug_a0 = debug_address_registers[0*32 +: 32];
    assign debug_a1 = debug_address_registers[1*32 +: 32];
    assign debug_a2 = debug_address_registers[2*32 +: 32];
    assign debug_a3 = debug_address_registers[3*32 +: 32];
    assign debug_a4 = debug_address_registers[4*32 +: 32];
    assign debug_a5 = debug_address_registers[5*32 +: 32];
    assign debug_a6 = debug_address_registers[6*32 +: 32];
    assign debug_a7 = debug_address_registers[7*32 +: 32];

    // Register the entry event because pending_exception_q is cleared on the
    // same edge that installs the handler PC.  This preserves precise fault
    // metadata for the external harness even when firmware handles the trap.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            exception_event_valid <= 1'b0;
            exception_event_vector <= '0;
            exception_event_opcode <= '0;
            exception_event_pc <= '0;
            exception_event_address <= '0;
        end else begin
            exception_event_valid <= core.exception_entry_commit_valid;
            if (core.exception_entry_commit_valid) begin
                exception_event_vector <= core.pending_exception_q.vector;
                exception_event_opcode <= core.pending_exception_q.opcode;
                exception_event_pc <=
                    core.pending_exception_q.instruction_pc;
                exception_event_address <=
                    core.pending_exception_q.logical_address;
            end
        end
    end

    initial begin
        m08_compat_enable = $test$plusargs("M08_COMPAT");
        if (!$value$plusargs("FIRMWARE_HEX=%s", firmware_hex))
            $fatal(1, "use +FIRMWARE_HEX=/path/to/bootloader.byte.hex");

        $readmemh(firmware_hex, instruction_memory.storage);
        $readmemh(firmware_hex, high_memory.storage);

        // Reset vectors are shadowed at zero on Mackerel-F. Data writes at
        // zero still go to main RAM after the reset-vector fetch.
        for (int index = 0; index < 16; index = index + 1)
            main_memory.storage[index] = high_memory.storage[index];

        if ($value$plusargs("IMAGE_BIN=%s", image_bin)) begin
            image_load_address = 32'h0000_0400;
            void'($value$plusargs("IMAGE_ADDR=%d", image_load_address));
            if ((image_load_address < 0) ||
                (image_load_address >= (8 * 1024 * 1024)))
                $fatal(1, "IMAGE_ADDR is outside populated RAM: %0d",
                       image_load_address);
            image_fd = $fopen(image_bin, "rb");
            if (image_fd == 0)
                $fatal(1, "cannot open IMAGE_BIN=%s", image_bin);
            image_bytes = $fread(main_memory.storage, image_fd,
                                 image_load_address,
                                 (8 * 1024 * 1024) - image_load_address);
            $fclose(image_fd);
            if (image_bytes <= 0)
                $fatal(1, "IMAGE_BIN is empty or could not be read: %s", image_bin);
            $display("[mx68k-sim] preloaded %0d bytes at 0x%08x from %s",
                     image_bytes, image_load_address, image_bin);
        end

        // New Mackerel-08 releases keep their XIP ROMfs in the physical
        // 512-KiB boot-ROM window at $380000.  Model it as preinitialized
        // storage; the DUART overlay still wins for $3fc000-$3fdfff.
        if ($value$plusargs("ROM_BIN=%s", rom_bin)) begin
            rom_load_address = 32'h0038_0000;
            void'($value$plusargs("ROM_ADDR=%d", rom_load_address));
            if ((rom_load_address < 0) ||
                (rom_load_address >= (8 * 1024 * 1024)))
                $fatal(1, "ROM_ADDR is outside populated memory: %0d",
                       rom_load_address);
            rom_fd = $fopen(rom_bin, "rb");
            if (rom_fd == 0)
                $fatal(1, "cannot open ROM_BIN=%s", rom_bin);
            rom_bytes = $fread(main_memory.storage, rom_fd,
                               rom_load_address,
                               (8 * 1024 * 1024) - rom_load_address);
            $fclose(rom_fd);
            if (rom_bytes <= 0)
                $fatal(1, "ROM_BIN is empty or could not be read: %s", rom_bin);
            $display("[mx68k-sim] preloaded %0d ROM bytes at 0x%08x from %s",
                     rom_bytes, rom_load_address, rom_bin);
        end
    end
endmodule
