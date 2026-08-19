`timescale 1ns/1ps
`default_nettype none

// Simulation-only Mackerel-F SoC.  This keeps the fx68k and the CPU-visible
// memory/peripheral contract, but replaces the FPGA PLL, physical SDRAM and
    // serial bit stream with fast behavioural models.
module mackerel_f_sim #(
    // Hardware-rate by default; may be overridden at Verilator build time.
    parameter integer TIMER_CLK_HZ = 75_600_000
) (
    input  wire        clk,
    input  wire        reset,

    input  wire        uart_rx_valid,
    input  wire [7:0]  uart_rx_data,
    output wire        uart_rx_ready,
    output reg         uart_tx_valid,
    output reg  [7:0]  uart_tx_data,

    output wire [23:0] debug_addr,
    output wire [15:0] debug_data_out,
    output wire [15:0] debug_data_in,
    output wire        debug_as_n,
    output wire        debug_rw_n,
    output wire        debug_uds_n,
    output wire        debug_lds_n,
    output wire [2:0]  debug_fc
);
    localparam integer RAM_BYTES = 8 * 1024 * 1024;
    localparam integer ROM_WORDS = 24 * 1024;
    localparam integer BSRAM_BYTES = 14 * 1024;

    reg [7:0] ram [0:RAM_BYTES-1];
    reg [15:0] rom [0:ROM_WORDS-1];
    reg [7:0] bsram [0:BSRAM_BYTES-1];

    string rom_file;
    string image_file;
    integer image_fd;
    integer image_size;
    integer init_i;
    integer patch_i;
    integer patch_j;
    reg direct_boot;

    initial begin
        direct_boot = $test$plusargs("DIRECT_BOOT");
        for (init_i = 0; init_i < RAM_BYTES; init_i = init_i + 1)
            ram[init_i] = 8'h00;
        for (init_i = 0; init_i < ROM_WORDS; init_i = init_i + 1)
            rom[init_i] = 16'hffff;
        for (init_i = 0; init_i < BSRAM_BYTES; init_i = init_i + 1)
            bsram[init_i] = 8'h00;

        if ($value$plusargs("ROM=%s", rom_file)) begin
            $display("[sim] loading boot ROM: %s", rom_file);
            $readmemh(rom_file, rom);
        end
        if ($value$plusargs("IMAGE_HEX=%s", image_file)) begin
            $readmemh(image_file, ram, 32'h000400);
            $display("[sim] loaded hexadecimal test image at 0x000400");
        end else if ($value$plusargs("IMAGE=%s", image_file)) begin
            image_fd = $fopen(image_file, "rb");
            if (image_fd == 0) begin
                $error("cannot open image: %s", image_file);
                $finish;
            end
            image_size = $fread(ram, image_fd, 32'h000400,
                                RAM_BYTES - 32'h000400);
            $fclose(image_fd);
            $display("[sim] loaded %0d image bytes at 0x000400", image_size);

            // Optional simulation-only edit of the ROMfs sdcard script.  There
            // is intentionally no SD model, so turn its 10/5-second sleeps into
            // zero-second sleeps and exit after the first failed probe.
            if ($test$plusargs("SKIP_SD_WAIT")) begin
                for (patch_i = 32'h000400;
                     patch_i < 32'h000400 + image_size - 22;
                     patch_i = patch_i + 1) begin
                    if (ram[patch_i+0]  == "W" && ram[patch_i+1]  == "a" &&
                        ram[patch_i+2]  == "i" && ram[patch_i+3]  == "t" &&
                        ram[patch_i+4]  == "i" && ram[patch_i+5]  == "n" &&
                        ram[patch_i+6]  == "g" && ram[patch_i+7]  == " " &&
                        ram[patch_i+8]  == "f" && ram[patch_i+9]  == "o" &&
                        ram[patch_i+10] == "r" && ram[patch_i+11] == " " &&
                        ram[patch_i+12] == "S" && ram[patch_i+13] == "D" &&
                        ram[patch_i+14] == " " && ram[patch_i+15] == "c" &&
                        ram[patch_i+16] == "a" && ram[patch_i+17] == "r" &&
                        ram[patch_i+18] == "d") begin
                        for (patch_j = patch_i;
                             patch_j < patch_i + 1024 &&
                             patch_j < 32'h000400 + image_size - 8;
                             patch_j = patch_j + 1) begin
                            if (ram[patch_j+0] == "s" && ram[patch_j+1] == "l" &&
                                ram[patch_j+2] == "e" && ram[patch_j+3] == "e" &&
                                ram[patch_j+4] == "p" && ram[patch_j+5] == " ") begin
                                if (ram[patch_j+6] == "5")
                                    ram[patch_j+6] = "0";
                                if (ram[patch_j+6] == "1" && ram[patch_j+7] == "0")
                                    ram[patch_j+6] = " ";
                            end
                            if (ram[patch_j+0] == "-" && ram[patch_j+1] == "g" &&
                                ram[patch_j+2] == "e" && ram[patch_j+3] == " " &&
                                ram[patch_j+4] == "2" && ram[patch_j+5] == "4") begin
                                ram[patch_j+4] = " ";
                                ram[patch_j+5] = "0";
                            end
                        end
                        $display("[sim] removed missing-SD waits from ROMfs init script");
                        patch_i = 32'h000400 + image_size;
                    end
                end
            end
        end
    end

    // The FPGA top alternates these enables, making the CPU run at clk/2.
    reg phase;
    always @(posedge clk) begin
        if (reset)
            phase <= 1'b0;
        else
            phase <= ~phase;
    end
    wire enPhi1 = (phase == 1'b1);
    wire enPhi2 = (phase == 1'b0);

    wire [23:1] addr_bus;
    wire [15:0] cpu_data_out;
    reg  [15:0] cpu_data_in;
    wire rw_n;
    wire as_n;
    wire lds_n;
    wire uds_n;
    wire fc0, fc1, fc2;
    wire dtack_n;
    wire berr_n;
    wire vpa_n;
    wire ipl0_n, ipl1_n, ipl2_n;

    fx68k cpu (
        .extReset(reset), .pwrUp(reset), .HALTn(1'b1),
        .clk(clk), .enPhi1(enPhi1), .enPhi2(enPhi2),
        .eab(addr_bus), .iEdb(cpu_data_in), .oEdb(cpu_data_out),
        .eRWn(rw_n), .ASn(as_n), .LDSn(lds_n), .UDSn(uds_n),
        .DTACKn(dtack_n), .FC0(fc0), .FC1(fc1), .FC2(fc2),
        .IPL0n(ipl0_n), .IPL1n(ipl1_n), .IPL2n(ipl2_n),
        .VPAn(vpa_n), .BERRn(berr_n), .BRn(1'b1), .BGACKn(1'b1),
        .E(), .VMAn(), .BGn(), .oRESETn(), .oHALTEDn()
    );

    wire [23:0] address = {addr_bus, 1'b0};
    wire [22:0] ram_index = address[22:0];
    wire [13:0] bsram_index = address[13:0];
    wire cpu_space = fc0 & fc1 & fc2;
    wire iack = cpu_space & ~as_n;

    // Normal mode exactly follows boot_signal.v.  Direct mode supplies reset
    // vectors from a tiny synthetic shadow then exposes the preloaded RAM.
    wire boot_normal;
    boot_signal boot_map(~reset, as_n, boot_normal);
    reg [2:0] direct_cycles;
    reg direct_shadow;
    always @(posedge as_n or posedge reset) begin
        if (reset) begin
            direct_cycles <= 3'd0;
            direct_shadow <= 1'b1;
        end else if (direct_boot && direct_shadow) begin
            if (direct_cycles == 3'd3)
                direct_shadow <= 1'b0;
            direct_cycles <= direct_cycles + 1'b1;
        end
    end
    wire boot = direct_boot ? ~direct_shadow : boot_normal;

    wire in_top = (address[23:16] == 8'hff);
    wire in_periph = &address[23:11];
    wire in_rom = in_top && (address[15:14] != 2'b11);
    wire in_bsram = in_top && (address[15:14] == 2'b11) && ~in_periph;
    wire in_ram = ~address[23];
    wire [2:0] periph_sel = address[10:8];

    wire cs_rom = ~as_n && (~boot || in_rom);
    wire cs_ram = ~as_n && boot && in_ram;
    wire cs_bsram = ~as_n && boot && in_bsram;
    wire cs_periph = ~as_n && boot && in_periph && ~cpu_space;
    wire cs_gpio = cs_periph && (periph_sel == 3'd0);
    wire cs_uart = cs_periph && (periph_sel == 3'd1);
    wire cs_timer = cs_periph && (periph_sel == 3'd2);
    wire cs_spi = cs_periph && ((periph_sel == 3'd3) ||
                                (periph_sel == 3'd4));
    wire cs_intc = cs_periph && (periph_sel == 3'd5);
    wire cs_ws2812 = cs_periph && (periph_sel == 3'd6);

    reg [7:0] gpio;
    reg [7:0] intc;
    reg bus_seen;

    // Minimal 16550-compatible register model.  THR is exported directly to
    // the C++ harness and RBR is filled from its nonblocking stdin queue.
    reg [7:0] uart_ier;
    reg [7:0] uart_lcr;
    reg [7:0] uart_mcr;
    reg [7:0] uart_scr;
    reg [7:0] uart_dll;
    reg [7:0] uart_dlm;
    reg [7:0] rx_byte;
    reg rx_full;
    wire uart_irq = rx_full && uart_ier[0];
    assign uart_rx_ready = ~rx_full;

    reg [7:0] uart_read;
    always @(*) begin
        case (addr_bus[3:1])
            3'd0: uart_read = uart_lcr[7] ? uart_dll : rx_byte;
            3'd1: uart_read = uart_lcr[7] ? uart_dlm : uart_ier;
            3'd2: uart_read = uart_irq ? 8'h04 : 8'h01;
            3'd3: uart_read = uart_lcr;
            3'd4: uart_read = uart_mcr;
            3'd5: uart_read = {1'b0, 2'b11, 4'b0000, rx_full}; // TEMT|THRE|DR
            3'd6: uart_read = 8'hb0; // DCD|DSR|CTS asserted
            default: uart_read = uart_scr;
        endcase
    end

    wire timer_irq;
    wire [7:0] timer_data;
    wire timer_dtack_n;
    timer #(.CLK_HZ(TIMER_CLK_HZ)) timer_model (
        .clk(clk), .rst_n(~reset), .cs_n(~cs_timer),
        .reg_addr(addr_bus[3:1]), .rwn(rw_n), .ds_n(uds_n),
        .data_in(cpu_data_out[15:8]), .data_out(timer_data),
        .dtack_n(timer_dtack_n), .irq(timer_irq)
    );

    irq_encoder irq_map (
        .irq1(1'b0), .irq2(1'b0), .irq3(1'b0), .irq4(1'b0),
        .irq5(uart_irq), .irq6(timer_irq), .irq7(1'b0),
        .ipl0_n(ipl0_n), .ipl1_n(ipl1_n), .ipl2_n(ipl2_n)
    );
    assign vpa_n = ~iack;

    // Complete each write once even though /AS spans several master clocks.
    always @(posedge clk) begin
        uart_tx_valid <= 1'b0;
        if (reset) begin
            bus_seen <= 1'b0;
            gpio <= 8'h00;
            intc <= 8'h00;
            uart_ier <= 8'h00;
            uart_lcr <= 8'h00;
            uart_mcr <= 8'h00;
            uart_scr <= 8'h00;
            uart_dll <= 8'h00;
            uart_dlm <= 8'h00;
            rx_byte <= 8'h00;
            rx_full <= 1'b0;
        end else begin
            if (as_n)
                bus_seen <= 1'b0;

            if (uart_rx_valid && !rx_full) begin
                rx_byte <= uart_rx_data;
                rx_full <= 1'b1;
            end

            if (!as_n && (!uds_n || !lds_n) && !bus_seen) begin
                bus_seen <= 1'b1;

                if (rw_n && cs_uart && !uds_n &&
                    addr_bus[3:1] == 3'd0 && !uart_lcr[7])
                    rx_full <= 1'b0;

                if (!rw_n) begin
                    if (cs_ram) begin
                        if (!uds_n) ram[ram_index] <= cpu_data_out[15:8];
                        if (!lds_n) ram[ram_index + 1'b1] <= cpu_data_out[7:0];
                    end
                    if (cs_bsram) begin
                        if (!uds_n) bsram[bsram_index] <= cpu_data_out[15:8];
                        if (!lds_n) bsram[bsram_index + 1'b1] <= cpu_data_out[7:0];
                    end
                    if (cs_gpio && !uds_n)
                        gpio <= cpu_data_out[15:8];
                    if (cs_intc && !uds_n)
                        intc <= cpu_data_out[15:8];
                    if (cs_uart && !uds_n) begin
                        case (addr_bus[3:1])
                            3'd0: if (uart_lcr[7])
                                      uart_dll <= cpu_data_out[15:8];
                                  else begin
                                      uart_tx_data <= cpu_data_out[15:8];
                                      uart_tx_valid <= 1'b1;
                                  end
                            3'd1: if (uart_lcr[7])
                                      uart_dlm <= cpu_data_out[15:8];
                                  else
                                      uart_ier <= cpu_data_out[15:8];
                            3'd2: begin end // FCR: FIFOs are effectively empty
                            3'd3: uart_lcr <= cpu_data_out[15:8];
                            3'd4: uart_mcr <= cpu_data_out[15:8];
                            3'd7: uart_scr <= cpu_data_out[15:8];
                            default: begin end
                        endcase
                    end
                end
            end
        end
    end

    // SD/NIC SPI are absent in simulation.  Returning an idle bus (0xff) and
    // TXE lets the real bootloader detect "no SD" without taking a bus error.
    reg [7:0] spi_read;
    always @(*) begin
        if (address[7:0] == 8'h08)
            spi_read = 8'h03; // STATUS.TXE | STATUS.TXR (idle/ready)
        else
            spi_read = 8'hff;
    end

    reg [15:0] rom_read;
    always @(*) begin
        if (direct_boot && direct_shadow) begin
            case (address)
                24'h000000: rom_read = 16'h0080;
                24'h000002: rom_read = 16'h0000;
                24'h000004: rom_read = 16'h0000;
                24'h000006: rom_read = 16'h0400;
                default: rom_read = 16'hffff;
            endcase
        end else begin
            rom_read = rom[addr_bus[15:1]];
        end
    end

    always @(*) begin
        if (cs_rom)
            cpu_data_in = rom_read;
        else if (cs_ram)
            cpu_data_in = {ram[ram_index], ram[ram_index + 1'b1]};
        else if (cs_bsram)
            cpu_data_in = {bsram[bsram_index], bsram[bsram_index + 1'b1]};
        else if (cs_gpio)
            cpu_data_in = {gpio, 8'h00};
        else if (cs_uart)
            cpu_data_in = {uart_read, 8'h00};
        else if (cs_timer)
            cpu_data_in = {timer_data, 8'h00};
        else if (cs_spi)
            cpu_data_in = {spi_read, 8'h00};
        else if (cs_intc)
            cpu_data_in = {intc, 8'h00};
        else if (cs_ws2812)
            cpu_data_in = 16'h0000;
        else
            cpu_data_in = 16'h0000;
    end

    assign dtack_n = iack ? 1'b1 :
                     (cs_rom || cs_ram || cs_bsram || cs_gpio || cs_uart ||
                      cs_spi || cs_intc || cs_ws2812) ? 1'b0 :
                     cs_timer ? timer_dtack_n : 1'b1;

    bus_watchdog #(.TIMEOUT(4096)) watchdog (
        .clk(clk), .rst_n(~reset), .as_n(as_n), .dtack_n(dtack_n),
        .vpa_n(vpa_n), .berr_n(berr_n)
    );

    assign debug_addr = address;
    assign debug_data_out = cpu_data_out;
    assign debug_data_in = cpu_data_in;
    assign debug_as_n = as_n;
    assign debug_rw_n = rw_n;
    assign debug_uds_n = uds_n;
    assign debug_lds_n = lds_n;
    assign debug_fc = {fc2, fc1, fc0};
endmodule

`default_nettype wire
