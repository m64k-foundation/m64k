// Simulation-only coherent RAM with an optional Mackerel-08 DUART overlay.
//
// The historical Linux image kept in the repository is valuable as a large
// M68000 ISA workload, but it was linked for the XR68C681 at 0x003fc000.  This
// model preserves ordinary RAM when compatibility is disabled and overlays
// only the console registers when enabled.  It is not part of the MX68K SoC
// contract and must not leak into synthesizable board tops.
module mx68k_linux_workload_memory #(
    parameter int unsigned MEM_BYTES = 8 * 1024 * 1024,
    parameter bit CLEAR_ON_INIT = 1'b0,
    parameter int unsigned TIMER_CYCLES = 120_000,
    parameter bit RX_ENABLED_ON_RESET = 1'b0
) (
    input logic clk,
    input logic rst_n,
    input logic m08_compat_enable,
    input logic rx_valid,
    input logic [7:0] rx_data,
    output logic rx_ready,
    output logic tx_valid,
    output logic [7:0] tx_data,
    output logic irq,
    output logic [7:0] irq_vector,
    mx68k_mem_if.slave imem,
    mx68k_mem_if.slave dmem
);
    import mx68k_pkg::*;

    localparam logic [31:0] DUART_BASE = 32'h003f_c000;
    localparam logic [31:0] DUART_END = 32'h003f_e000;
    localparam logic [4:0] DUART_SRB = 5'h13;
    localparam logic [4:0] DUART_MRB = 5'h11;
    localparam logic [4:0] DUART_CRB = 5'h15;
    localparam logic [4:0] DUART_RBB = 5'h17;
    localparam logic [4:0] DUART_TBB = 5'h17;

    logic [7:0] storage [0:MEM_BYTES-1];
    logic imem_rsp_valid_q;
    logic dmem_rsp_valid_q;
    mx_mem_rsp_t imem_rsp_q;
    mx_mem_rsp_t dmem_rsp_q;
    logic [7:0] interrupt_mask_q;
    logic [7:0] vector_q;
    logic [15:0] counter_reload_q;
    logic [31:0] timer_count_q;
    logic timer_running_q;
    logic timer_pending_q;
    logic receiver_enabled_q;
    logic receiver_irq_full_q;
    logic mode_pointer_mr1_q;
    logic [7:0] receive_fifo_q [0:2];
    logic [1:0] receive_count_q;
    logic [1:0] receive_read_pointer_q;
    logic [1:0] receive_write_pointer_q;

    wire [31:0] imem_line = mx68k_line_base(imem.req.addr);
    wire [32:0] imem_end_offset = {1'b0, imem_line} + 33'd16;
    wire imem_in_range = imem_end_offset <= {1'b0, MEM_BYTES};

    wire [31:0] dmem_line = mx68k_line_base(dmem.req.addr);
    wire [32:0] dmem_end_offset = {1'b0, dmem_line} + 33'd16;
    wire dmem_in_range = dmem_end_offset <= {1'b0, MEM_BYTES};
    wire request_is_duart = m08_compat_enable &&
                            (dmem_line >= DUART_BASE) &&
                            (dmem_line < DUART_END);
    wire receiver_irq_source = receiver_irq_full_q ?
                               (receive_count_q == 2'd3) :
                               (receive_count_q != 2'd0);
    wire receive_push = rx_valid && rx_ready;
    wire receive_pop = dmem.req_valid && dmem.req_ready &&
                       request_is_duart &&
                       (dmem.req.command == MX_MEM_READ) &&
                       ((dmem.req.addr & 32'h1f) == DUART_RBB) &&
                       (receive_count_q != 2'd0);

    mx_mem_rsp_t imem_response_for_request;
    mx_mem_rsp_t dmem_response_for_request;
    integer init_index;

    initial begin
        if ((MEM_BYTES == 0) || ((MEM_BYTES % MX68K_LINE_BYTES) != 0))
            $fatal(1, "mx68k_linux_workload_memory MEM_BYTES must be a non-zero multiple of 16");
        if (CLEAR_ON_INIT)
            for (init_index = 0; init_index < MEM_BYTES;
                 init_index = init_index + 1)
                storage[init_index] = 8'h00;
    end

    always_comb begin
        imem_response_for_request = '0;
        imem_response_for_request.txn_id = imem.req.txn_id;
        imem_response_for_request.source = imem.req.source;
        if (!imem_in_range)
            imem_response_for_request.fault = MX_FAULT_ACCESS;
        else if (imem.req.command != MX_MEM_READ)
            imem_response_for_request.fault = MX_FAULT_UNSUPPORTED;
        else
            for (int unsigned lane = 0; lane < MX68K_LINE_BYTES;
                 lane = lane + 1)
                imem_response_for_request.rdata[lane*8 +: 8] =
                    storage[imem_line + lane];
    end

    always_comb begin
        dmem_response_for_request = '0;
        dmem_response_for_request.txn_id = dmem.req.txn_id;
        dmem_response_for_request.source = dmem.req.source;
        if (!dmem_in_range) begin
            dmem_response_for_request.fault = MX_FAULT_ACCESS;
        end else begin
            case (dmem.req.command)
                MX_MEM_READ: begin
                    for (int unsigned lane = 0; lane < MX68K_LINE_BYTES;
                         lane = lane + 1) begin
                        if (request_is_duart) begin
                            case ((dmem_line + lane) & 32'h1f)
                                5'h05:
                                    dmem_response_for_request.
                                        rdata[lane*8 +: 8] =
                                        // MC68681UM section 4.3.15.5 defines
                                        // ISR[3] as Counter/Timer Ready.  The
                                        // historical kernel copies this byte
                                        // to CCR, so ISR[3] becomes CCR.N and
                                        // selects logical IRQ 2.
                                        (receiver_irq_source ? 8'h20 : 8'h00) |
                                        (timer_pending_q ? 8'h08 : 8'h00);
                                DUART_SRB:
                                    // SRB[2] is TxRDY. SRB[1:0] reflect the
                                    // documented three-entry receive FIFO.
                                    dmem_response_for_request.
                                        rdata[lane*8 +: 8] =
                                        8'h04 |
                                        ((receive_count_q == 2'd3) ?
                                         8'h02 : 8'h00) |
                                        ((receive_count_q != 2'd0) ?
                                         8'h01 : 8'h00);
                                DUART_RBB:
                                    dmem_response_for_request.
                                        rdata[lane*8 +: 8] =
                                        (receive_count_q != 2'd0) ?
                                        receive_fifo_q[
                                            receive_read_pointer_q] : 8'h00;
                                5'h19:
                                    dmem_response_for_request.
                                        rdata[lane*8 +: 8] = vector_q;
                                default:
                                    dmem_response_for_request.
                                        rdata[lane*8 +: 8] = 8'h00;
                            endcase
                        end else
                            dmem_response_for_request.rdata[lane*8 +: 8] =
                                storage[dmem_line + lane];
                    end
                end
                MX_MEM_WRITE,
                MX_MEM_FENCE: dmem_response_for_request.fault = MX_FAULT_NONE;
                MX_MEM_ATOMIC: begin
                    if (!request_is_duart &&
                        (dmem.req.atomic_op == MX_ATOMIC_OR)) begin
                        for (int unsigned lane = 0;
                             lane < MX68K_LINE_BYTES; lane = lane + 1)
                            dmem_response_for_request.rdata[lane*8 +: 8] =
                                storage[dmem_line + lane];
                        dmem_response_for_request.atomic_success = 1'b1;
                    end else begin
                        dmem_response_for_request.fault =
                            MX_FAULT_UNSUPPORTED;
                    end
                end
                default:
                    dmem_response_for_request.fault = MX_FAULT_UNSUPPORTED;
            endcase
        end
    end

    assign imem.req_ready = !imem_rsp_valid_q;
    assign imem.rsp_valid = imem_rsp_valid_q;
    assign imem.rsp = imem_rsp_q;
    assign dmem.req_ready = !dmem_rsp_valid_q;
    assign dmem.rsp_valid = dmem_rsp_valid_q;
    assign dmem.rsp = dmem_rsp_q;
    assign rx_ready = m08_compat_enable && receiver_enabled_q &&
                      (receive_count_q != 2'd3);
    assign irq = m08_compat_enable &&
                 ((timer_pending_q && interrupt_mask_q[3]) ||
                  (receiver_irq_source && interrupt_mask_q[5]));
    assign irq_vector = vector_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_rsp_valid_q <= 1'b0;
            dmem_rsp_valid_q <= 1'b0;
            imem_rsp_q <= '0;
            dmem_rsp_q <= '0;
            tx_valid <= 1'b0;
            tx_data <= '0;
            interrupt_mask_q <= '0;
            vector_q <= 8'h41;
            counter_reload_q <= '0;
            timer_count_q <= '0;
            timer_running_q <= 1'b0;
            timer_pending_q <= 1'b0;
            receiver_enabled_q <= RX_ENABLED_ON_RESET;
            receiver_irq_full_q <= 1'b0;
            mode_pointer_mr1_q <= 1'b1;
            receive_count_q <= '0;
            receive_read_pointer_q <= '0;
            receive_write_pointer_q <= '0;
        end else begin
            tx_valid <= 1'b0;
            if (receive_push) begin
                receive_fifo_q[receive_write_pointer_q] <= rx_data;
                receive_write_pointer_q <=
                    (receive_write_pointer_q == 2'd2) ?
                    2'd0 : receive_write_pointer_q + 1'b1;
            end
            if (receive_pop)
                receive_read_pointer_q <=
                    (receive_read_pointer_q == 2'd2) ?
                    2'd0 : receive_read_pointer_q + 1'b1;
            case ({receive_push, receive_pop})
                2'b10: receive_count_q <= receive_count_q + 1'b1;
                2'b01: receive_count_q <= receive_count_q - 1'b1;
                default: begin end
            endcase
            if (timer_running_q) begin
                if (timer_count_q == TIMER_CYCLES - 1) begin
                    timer_count_q <= '0;
                    timer_pending_q <= 1'b1;
                end else begin
                    timer_count_q <= timer_count_q + 1'b1;
                end
            end
            if (imem_rsp_valid_q && imem.rsp_ready)
                imem_rsp_valid_q <= 1'b0;
            if (dmem_rsp_valid_q && dmem.rsp_ready)
                dmem_rsp_valid_q <= 1'b0;

            if (imem.req_valid && imem.req_ready) begin
                imem_rsp_q <= imem_response_for_request;
                imem_rsp_valid_q <= 1'b1;
            end

            if (dmem.req_valid && dmem.req_ready) begin
                dmem_rsp_q <= dmem_response_for_request;
                dmem_rsp_valid_q <= 1'b1;
                if (request_is_duart &&
                    (dmem.req.command == MX_MEM_READ)) begin
                    // XR68C681 read commands: start and stop/ack the counter.
                    if ((dmem.req.addr & 32'h1f) == 5'h1d) begin
                        timer_running_q <= 1'b1;
                        timer_count_q <= '0;
                    end else if ((dmem.req.addr & 32'h1f) == 5'h1f) begin
                        // MC68681UM section 4.3.15.5: Counter/Timer Ready is
                        // cleared by the stop-counter command, not by reading
                        // ISR.  In timer mode the counter keeps operating; the
                        // historical handler performs this read to ack a tick.
                        timer_pending_q <= 1'b0;
                    end
                end
                if (dmem_in_range && (dmem.req.command == MX_MEM_WRITE)) begin
                    for (int unsigned lane = 0; lane < MX68K_LINE_BYTES;
                         lane = lane + 1) begin
                        if (dmem.req.wstrb[lane]) begin
                            if (request_is_duart &&
                                (((dmem_line + lane) & 32'h1f) == DUART_TBB)) begin
                                tx_valid <= 1'b1;
                                tx_data <= dmem.req.wdata[lane*8 +: 8];
                            end else if (request_is_duart) begin
                                case ((dmem_line + lane) & 32'h1f)
                                    DUART_MRB: begin
                                        if (mode_pointer_mr1_q) begin
                                            receiver_irq_full_q <=
                                                dmem.req.wdata[lane*8 + 6];
                                            mode_pointer_mr1_q <= 1'b0;
                                        end
                                    end
                                    5'h0b: interrupt_mask_q <=
                                        dmem.req.wdata[lane*8 +: 8];
                                    5'h0d: counter_reload_q[15:8] <=
                                        dmem.req.wdata[lane*8 +: 8];
                                    5'h0f: counter_reload_q[7:0] <=
                                        dmem.req.wdata[lane*8 +: 8];
                                    5'h19: vector_q <=
                                        dmem.req.wdata[lane*8 +: 8];
                                    DUART_CRB: begin
                                        // XR68C681 extends the MC68681
                                        // miscellaneous command field with
                                        // bit 7. Commands 8..B select the
                                        // extended Rx/Tx baud-rate tables and
                                        // must not alias commands 0..3.
                                        case (dmem.req.wdata[
                                              lane*8 + 4 +: 4])
                                            4'h1:
                                                mode_pointer_mr1_q <= 1'b1;
                                            4'h2: begin
                                                receiver_enabled_q <= 1'b0;
                                                receive_count_q <= '0;
                                                receive_read_pointer_q <= '0;
                                                receive_write_pointer_q <= '0;
                                            end
                                            default: begin end
                                        endcase
                                        if (dmem.req.wdata[lane*8 +: 2] ==
                                            2'b01)
                                            receiver_enabled_q <= 1'b1;
                                        else if (dmem.req.wdata[
                                                 lane*8 +: 2] == 2'b10)
                                            receiver_enabled_q <= 1'b0;
                                    end
                                    default: begin end
                                endcase
                            end else if (!request_is_duart) begin
                                storage[dmem_line + lane] <=
                                    dmem.req.wdata[lane*8 +: 8];
                            end
                        end
                    end
                end else if (dmem_in_range && !request_is_duart &&
                             (dmem.req.command == MX_MEM_ATOMIC) &&
                             (dmem.req.atomic_op == MX_ATOMIC_OR)) begin
                    for (int unsigned lane = 0;
                         lane < MX68K_LINE_BYTES; lane = lane + 1)
                        if (dmem.req.wstrb[lane])
                            storage[dmem_line + lane] <=
                                storage[dmem_line + lane] |
                                dmem.req.wdata[lane*8 +: 8];
                end
            end
        end
    end
endmodule
