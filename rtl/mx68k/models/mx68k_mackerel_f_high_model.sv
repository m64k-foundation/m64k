// Simulation-only 64 KiB high window: boot ROM/BSRAM plus the 16550 console.
// The byte array keeps the model fast while preserving the CPU-visible map.
module mx68k_mackerel_f_high_model #(
    parameter bit PRINT_TX = 1'b0,
    parameter int unsigned CLOCK_HZ = 37_800_000
) (
    input logic clk,
    input logic rst_n,
    input logic [31:0] timer_time_scale,
    input logic rx_valid,
    input logic [7:0] rx_data,
    output logic rx_ready,
    output logic tx_valid,
    output logic [7:0] tx_data,
    output logic uart_irq,
    output logic timer_irq,
    mx68k_mem_if.slave mem
);
    import mx68k_pkg::*;

    localparam logic [31:0] BASE_ADDR = 32'h00ff_0000;
    localparam logic [31:0] GPIO_BASE = 32'h00ff_f800;
    localparam logic [31:0] UART_BASE = 32'h00ff_f900;
    localparam logic [31:0] TIMER_BASE = 32'h00ff_fa00;
    localparam logic [31:0] SPI_BASE = 32'h00ff_fb00;
    localparam logic [31:0] SPI2_BASE = 32'h00ff_fc00;
    localparam logic [31:0] SPI_END = 32'h00ff_fd00;
    localparam logic [7:0] LSR_THRE_TEMT = 8'h60;

    logic [7:0] storage [0:65535];
    logic rsp_valid_q;
    mx_mem_rsp_t rsp_q;
    logic [7:0] divisor_low_q;
    logic [7:0] divisor_high_q;
    logic [7:0] interrupt_enable_q;
    logic [7:0] fifo_control_q;
    logic [7:0] line_control_q;
    logic rx_full_q;
    logic [7:0] rx_data_q;
    logic tx_irq_pending_q;
    logic tx_irq_rearm_q;
    logic [7:0] gpio_q;
    logic sd_transfer_valid;
    logic [7:0] sd_tx_data;
    logic [7:0] sd_rx_data;
    logic sd_card_present;
    logic [7:0] sd_shift_rx_q;
    logic [7:0] sd_buffer_rx_q;
    logic sd_response_pending_q;
    logic timer_enable_q;
    logic [1:0] timer_frequency_q;
    logic [31:0] timer_count_q;
    logic timer_pending_q;
    logic [31:0] timer_reload;
    logic [31:0] request_line;
    logic request_in_range;
    logic request_is_uart;
    logic request_is_timer;
    logic request_is_spi;
    logic request_is_sd_spi;
    logic request_is_gpio;
    mx_mem_rsp_t response_for_request;
    wire [31:0] timer_scale_safe = (timer_time_scale == 0) ? 32'd1 :
                                                                timer_time_scale;

    function automatic logic [7:0] read_uart(input logic [7:0] offset);
        case (offset)
            8'd0:  return line_control_q[7] ? divisor_low_q : rx_data_q;
            8'd2:  return line_control_q[7] ? divisor_high_q :
                                             interrupt_enable_q;
            // OpenCores uart_regs.v returns FIFO-present bits [7:6] plus
            // the 16550 IIR. RX data available has priority over THRE.
            8'd4:  return (rx_full_q && interrupt_enable_q[0]) ? 8'hc4 :
                          tx_irq_pending_q ? 8'hc2 : 8'hc1;
            8'd6:  return line_control_q;
            8'd10: return LSR_THRE_TEMT | {7'd0, rx_full_q};
            default: return 8'd0;
        endcase
    endfunction

    function automatic logic [7:0] read_timer(input logic [7:0] offset);
        case (offset)
            8'd0: return {2'b00, timer_frequency_q, 3'b000,
                          timer_enable_q};
            8'd2: return {7'd0, timer_pending_q};
            default: return 8'd0;
        endcase
    endfunction

    // Fast no-card model: the tiny-SPI engine is always idle/ready and every
    // received byte is 0xff.  This lets firmware detect an absent SD card
    // without simulating a physical serial engine.
    function automatic logic [7:0] read_spi(
        input logic [7:0] offset,
        input logic sd_slot
    );
        case (offset)
            // tiny_spi exposes the final received byte in its shift register
            // and the preceding byte in the read side of TXDATA.  Linux uses
            // the latter to pipeline all intermediate bytes of a transfer.
            8'd0: return sd_slot ? sd_shift_rx_q : 8'hff;
            8'd4: return sd_slot ? sd_buffer_rx_q : 8'hff;
            8'd8: return 8'h03;
            default: return 8'd0;
        endcase
    endfunction

    mx68k_sd_spi_model sd_card (
        .clk, .rst_n,
        .selected(gpio_q[6]),
        .transfer_valid(sd_transfer_valid),
        .tx_data(sd_tx_data),
        .rx_data(sd_rx_data),
        .card_present(sd_card_present)
    );

    always_comb begin
        request_line = mx68k_line_base(mem.req.addr);
        request_in_range = (request_line >= BASE_ADDR) &&
                           (request_line <= 32'h00ff_fff0);
        request_is_uart = (request_line >= UART_BASE) &&
                          (request_line < UART_BASE + 32'h100);
        request_is_timer = (request_line >= TIMER_BASE) &&
                           (request_line < TIMER_BASE + 32'h100);
        // Mackerel-F populates two identical tiny-SPI slots at $fffb00 and
        // $fffc00.  Their low-byte register offsets are the same.
        request_is_spi = (request_line >= SPI_BASE) &&
                         (request_line < SPI_END);
        request_is_sd_spi = (request_line >= SPI_BASE) &&
                            (request_line < SPI2_BASE);
        request_is_gpio = (request_line >= GPIO_BASE) &&
                          (request_line < GPIO_BASE + 32'h100);
        sd_transfer_valid = 1'b0;
        sd_tx_data = 8'hff;
        if (mem.req_valid && mem.req_ready && request_is_sd_spi &&
            (mem.req.command == MX_MEM_WRITE)) begin
            for (int lane = 0; lane < MX68K_LINE_BYTES; lane = lane + 1) begin
                if (mem.req.wstrb[lane] &&
                    (((request_line + lane) - SPI_BASE) == 32'd4)) begin
                    sd_transfer_valid = 1'b1;
                    sd_tx_data = mem.req.wdata[lane*8 +: 8];
                end
            end
        end
        response_for_request = '0;
        response_for_request.txn_id = mem.req.txn_id;
        response_for_request.source = mem.req.source;
        response_for_request.fault = request_in_range ? MX_FAULT_NONE :
                                                        MX_FAULT_ACCESS;

        if (request_in_range && (mem.req.command == MX_MEM_READ)) begin
            for (int lane = 0; lane < MX68K_LINE_BYTES; lane = lane + 1) begin
                if (request_is_uart)
                    response_for_request.rdata[lane*8 +: 8] =
                        read_uart((request_line + lane) - UART_BASE);
                else if (request_is_timer)
                    response_for_request.rdata[lane*8 +: 8] =
                        read_timer((request_line + lane) - TIMER_BASE);
                else if (request_is_spi)
                    response_for_request.rdata[lane*8 +: 8] =
                        read_spi((request_line + lane) -
                                     (request_is_sd_spi ? SPI_BASE : SPI2_BASE),
                                 request_is_sd_spi);
                else if (request_is_gpio)
                    response_for_request.rdata[lane*8 +: 8] = gpio_q;
                else
                    response_for_request.rdata[lane*8 +: 8] =
                        storage[(request_line - BASE_ADDR) + lane];
            end
        end else if (request_in_range &&
                     !(mem.req.command inside {MX_MEM_WRITE, MX_MEM_FENCE})) begin
            response_for_request.fault = MX_FAULT_UNSUPPORTED;
        end


        case (timer_frequency_q)
            2'd0: timer_reload = (CLOCK_HZ / 10 / timer_scale_safe) - 1;
            2'd1: timer_reload = (CLOCK_HZ / 25 / timer_scale_safe) - 1;
            2'd2: timer_reload = (CLOCK_HZ / 50 / timer_scale_safe) - 1;
            default: timer_reload = (CLOCK_HZ / 100 /
                                      timer_scale_safe) - 1;
        endcase
    end

    assign mem.req_ready = !rsp_valid_q;
    assign mem.rsp_valid = rsp_valid_q;
    assign mem.rsp = rsp_q;
    assign rx_ready = !rx_full_q;
    assign uart_irq = (rx_full_q && interrupt_enable_q[0]) ||
                      tx_irq_pending_q;
    assign timer_irq = timer_pending_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rsp_valid_q <= 1'b0;
            rsp_q <= '0;
            divisor_low_q <= 8'd1;
            divisor_high_q <= 8'd0;
            interrupt_enable_q <= 8'd0;
            fifo_control_q <= 8'd0;
            line_control_q <= 8'h03;
            rx_full_q <= 1'b0;
            rx_data_q <= '0;
            tx_irq_pending_q <= 1'b0;
            tx_irq_rearm_q <= 1'b0;
            gpio_q <= 8'd0;
            sd_shift_rx_q <= 8'hff;
            sd_buffer_rx_q <= 8'hff;
            sd_response_pending_q <= 1'b0;
            timer_enable_q <= 1'b0;
            timer_frequency_q <= 2'd3;
            timer_count_q <= '0;
            timer_pending_q <= 1'b0;
            tx_valid <= 1'b0;
            tx_data <= '0;
        end else begin
            tx_valid <= 1'b0;
            if (sd_response_pending_q) begin
                sd_buffer_rx_q <= sd_shift_rx_q;
                sd_shift_rx_q <= sd_rx_data;
                sd_response_pending_q <= 1'b0;
            end
            if (sd_transfer_valid)
                sd_response_pending_q <= 1'b1;
            if (tx_irq_rearm_q) begin
                tx_irq_pending_q <= interrupt_enable_q[1];
                tx_irq_rearm_q <= 1'b0;
            end
            if (rsp_valid_q && mem.rsp_ready)
                rsp_valid_q <= 1'b0;

            if (rx_valid && rx_ready) begin
                rx_full_q <= 1'b1;
                rx_data_q <= rx_data;
            end


            if (timer_enable_q) begin
                if (timer_count_q >= timer_reload) begin
                    timer_count_q <= '0;
                    timer_pending_q <= 1'b1;
                end else begin
                    timer_count_q <= timer_count_q + 1'b1;
                end
            end else begin
                timer_count_q <= '0;
            end

            if (mem.req_valid && mem.req_ready) begin
                rsp_q <= response_for_request;
                rsp_valid_q <= 1'b1;
                if (request_is_uart &&
                    (mem.req.command == MX_MEM_READ) &&
                    (mem.req.addr == UART_BASE) && !line_control_q[7])
                    rx_full_q <= 1'b0;
                if (request_is_uart &&
                    (mem.req.command == MX_MEM_READ) &&
                    (mem.req.addr == UART_BASE + 32'd4) &&
                    tx_irq_pending_q &&
                    !(rx_full_q && interrupt_enable_q[0]))
                    tx_irq_pending_q <= 1'b0;
                if (request_in_range && (mem.req.command == MX_MEM_WRITE)) begin
                    for (int lane = 0; lane < MX68K_LINE_BYTES;
                         lane = lane + 1) begin
                        if (mem.req.wstrb[lane]) begin
                            if (request_is_uart) begin
                                case ((request_line + lane) - UART_BASE)
                                    32'd0: begin
                                        if (line_control_q[7]) begin
                                            divisor_low_q <=
                                                mem.req.wdata[lane*8 +: 8];
                                        end else begin
                                            tx_valid <= 1'b1;
                                            tx_data <= mem.req.wdata[lane*8 +: 8];
                                            tx_irq_pending_q <= 1'b0;
                                            tx_irq_rearm_q <= 1'b1;
                                            if (PRINT_TX)
                                                $write("%c", mem.req.wdata[lane*8 +: 8]);
                                        end
                                    end
                                    32'd2: begin
                                        if (line_control_q[7])
                                            divisor_high_q <=
                                                mem.req.wdata[lane*8 +: 8];
                                        else begin
                                            interrupt_enable_q <=
                                                mem.req.wdata[lane*8 +: 8];
                                            if (!mem.req.wdata[lane*8 + 1]) begin
                                                tx_irq_pending_q <= 1'b0;
                                                tx_irq_rearm_q <= 1'b0;
                                            end else if (!interrupt_enable_q[1])
                                                tx_irq_pending_q <= 1'b1;
                                        end
                                    end
                                    32'd4: begin
                                        fifo_control_q <=
                                            mem.req.wdata[lane*8 +: 8];
                                        if (mem.req.wdata[lane*8 + 1])
                                            rx_full_q <= 1'b0;
                                    end
                                    32'd6: line_control_q <=
                                                mem.req.wdata[lane*8 +: 8];
                                    default: begin end
                                endcase
                            end else if (request_is_timer) begin
                                case ((request_line + lane) - TIMER_BASE)
                                    32'd0: begin
                                        timer_enable_q <=
                                            mem.req.wdata[lane*8];
                                        timer_frequency_q <=
                                            mem.req.wdata[lane*8 + 4 +: 2];
                                        if (!mem.req.wdata[lane*8]) begin
                                            timer_count_q <= '0;
                                            timer_pending_q <= 1'b0;
                                        end
                                    end
                                    32'd2: timer_pending_q <= 1'b0;
                                    default: begin end
                                endcase
                            end else if (request_is_gpio &&
                                         (((request_line + lane) -
                                           GPIO_BASE) == 32'd0)) begin
                                gpio_q <= mem.req.wdata[lane*8 +: 8];
                            end else begin
                                storage[(request_line - BASE_ADDR) + lane] <=
                                    mem.req.wdata[lane*8 +: 8];
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
