module m64k_uart #(
    parameter logic [31:0] BASE_ADDR = 32'h00f0_0000
) (
    input logic clk,
    input logic rst_n,
    output logic tx_valid,
    output logic [7:0] tx_data,
    input logic tx_ready,
    input logic rx_valid,
    input logic [7:0] rx_data,
    output logic rx_ready,
    output logic irq_pending,
    m64k_mem_if.slave mem
);
    import m64k_pkg::*;

    logic response_valid_q;
    m64k_mem_rsp_t response_q;
    logic rx_pending_q;
    logic [7:0] rx_data_q;
    logic control_rx_irq_q;
    logic tx_pending_q;
    logic [7:0] tx_data_q;
    m64k_mem_rsp_t response_for_request;
    logic request_in_range;
    logic [31:0] request_line;
    logic request_is_tx_write;
    logic request_access_valid;

    always_comb begin
        request_line = m64k_line_base(mem.req.addr);
        request_in_range = (request_line >= BASE_ADDR) &&
                           (request_line < (BASE_ADDR + 32'h1000));
        request_is_tx_write = request_in_range &&
                              (mem.req.command == M64K_MEM_WRITE) &&
                              (mem.req.size == M64K_SIZE_BYTE) &&
                              (mem.req.addr == BASE_ADDR) &&
                              (mem.req.wstrb == 16'h0001);
        request_access_valid = 1'b0;
        if (request_in_range) begin
            case (mem.req.command)
                M64K_MEM_READ: begin
                    request_access_valid =
                        (mem.req.size == M64K_SIZE_BYTE) &&
                        ((mem.req.addr == (BASE_ADDR + 32'd4)) ||
                         (mem.req.addr == (BASE_ADDR + 32'd8)) ||
                         (mem.req.addr == (BASE_ADDR + 32'd12)));
                end
                M64K_MEM_WRITE: begin
                    request_access_valid = request_is_tx_write ||
                        ((mem.req.size == M64K_SIZE_BYTE) &&
                         (mem.req.addr == (BASE_ADDR + 32'd12)) &&
                         (mem.req.wstrb == 16'h1000));
                end
                M64K_MEM_FENCE: request_access_valid = 1'b1;
                default: request_access_valid = 1'b0;
            endcase
        end
        response_for_request = '0;
        response_for_request.txn_id = mem.req.txn_id;
        response_for_request.source = mem.req.source;
        response_for_request.fault = request_access_valid ? M64K_FAULT_NONE :
                                                           M64K_FAULT_ACCESS;
        if (request_in_range && (mem.req.command == M64K_MEM_ATOMIC))
            response_for_request.fault = M64K_FAULT_UNSUPPORTED;
        if (request_access_valid && (mem.req.command == M64K_MEM_READ)) begin
            response_for_request.rdata[4*8 +: 8] = rx_data_q;
            response_for_request.rdata[8*8 +: 8] =
                {6'd0, rx_pending_q, !tx_pending_q};
            response_for_request.rdata[12*8 +: 8] =
                {7'd0, control_rx_irq_q};
        end
    end

    assign mem.req_ready = !response_valid_q &&
                           (!request_is_tx_write || !tx_pending_q || tx_ready);
    assign mem.rsp_valid = response_valid_q;
    assign mem.rsp = response_q;
    assign rx_ready = !rx_pending_q;
    assign irq_pending = rx_pending_q && control_rx_irq_q;
    assign tx_valid = tx_pending_q;
    assign tx_data = tx_data_q;

    initial begin
        if (BASE_ADDR[11:0] != 12'd0)
            $fatal(1, "m64k_uart BASE_ADDR must be 4-KiB aligned");
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            response_valid_q <= 1'b0;
            response_q <= '0;
            tx_pending_q <= 1'b0;
            tx_data_q <= '0;
            rx_pending_q <= 1'b0;
            rx_data_q <= '0;
            control_rx_irq_q <= 1'b0;
        end else begin
            if (response_valid_q && mem.rsp_ready)
                response_valid_q <= 1'b0;
            if (tx_pending_q && tx_ready)
                tx_pending_q <= 1'b0;
            if (rx_valid && rx_ready) begin
                rx_pending_q <= 1'b1;
                rx_data_q <= rx_data;
            end
            if (mem.req_valid && mem.req_ready) begin
                response_q <= response_for_request;
                response_valid_q <= 1'b1;
                if (request_access_valid &&
                    (mem.req.command == M64K_MEM_READ) &&
                    (mem.req.addr == (BASE_ADDR + 32'd4)) && rx_pending_q)
                    rx_pending_q <= 1'b0;
                if (request_access_valid &&
                    (mem.req.command == M64K_MEM_WRITE)) begin
                    if (request_is_tx_write) begin
                        tx_pending_q <= 1'b1;
                        tx_data_q <= mem.req.wdata[7:0];
                    end
                    if (mem.req.wstrb[12])
                        control_rx_irq_q <= mem.req.wdata[12*8];
                end
            end
        end
    end
endmodule
