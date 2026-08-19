module m64k_timer #(
    parameter logic [31:0] BASE_ADDR = 32'h00f0_1000
) (
    input logic clk,
    input logic rst_n,
    output logic irq_pending,
    m64k_mem_if.slave mem
);
    import m64k_pkg::*;

    logic response_valid_q;
    m64k_mem_rsp_t response_q;
    logic [31:0] cycle_counter_q;
    logic [31:0] interval_q;
    logic [31:0] remaining_q;
    logic enabled_q;
    logic periodic_q;
    logic interrupt_enable_q;
    logic pending_q;
    m64k_mem_rsp_t response_for_request;
    logic request_in_range;
    logic [31:0] request_line;
    logic request_access_valid;

    function automatic logic [31:0] read_be32(
        input logic [M64K_LINE_BITS-1:0] data,
        input int unsigned lane
    );
        return {data[(lane + 0)*8 +: 8], data[(lane + 1)*8 +: 8],
                data[(lane + 2)*8 +: 8], data[(lane + 3)*8 +: 8]};
    endfunction

    task automatic write_be32_to_line(
        inout m64k_mem_rsp_t response,
        input int unsigned lane,
        input logic [31:0] value
    );
        begin
            response.rdata[(lane + 0)*8 +: 8] = value[31:24];
            response.rdata[(lane + 1)*8 +: 8] = value[23:16];
            response.rdata[(lane + 2)*8 +: 8] = value[15:8];
            response.rdata[(lane + 3)*8 +: 8] = value[7:0];
        end
    endtask

    always_comb begin
        request_line = m64k_line_base(mem.req.addr);
        request_in_range = (request_line >= BASE_ADDR) &&
                           (request_line < (BASE_ADDR + 32'h1000));
        request_access_valid = 1'b0;
        if (request_in_range) begin
            case (mem.req.command)
                M64K_MEM_READ: begin
                    request_access_valid =
                        (((mem.req.addr == BASE_ADDR) ||
                          (mem.req.addr == (BASE_ADDR + 32'd4))) &&
                         (mem.req.size == M64K_SIZE_LONG)) ||
                        (((mem.req.addr == (BASE_ADDR + 32'd8)) ||
                          (mem.req.addr == (BASE_ADDR + 32'd12))) &&
                         (mem.req.size == M64K_SIZE_BYTE));
                end
                M64K_MEM_WRITE: begin
                    request_access_valid =
                        ((mem.req.addr == (BASE_ADDR + 32'd4)) &&
                         (mem.req.size == M64K_SIZE_LONG) &&
                         (mem.req.wstrb == 16'h00f0)) ||
                        ((mem.req.addr == (BASE_ADDR + 32'd8)) &&
                         (mem.req.size == M64K_SIZE_BYTE) &&
                         (mem.req.wstrb == 16'h0100)) ||
                        ((mem.req.addr == (BASE_ADDR + 32'd12)) &&
                         (mem.req.size == M64K_SIZE_BYTE) &&
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
        if (request_access_valid && (mem.req.command == M64K_MEM_READ)) begin
            write_be32_to_line(response_for_request, 0, cycle_counter_q);
            write_be32_to_line(response_for_request, 4, interval_q);
            response_for_request.rdata[8*8 +: 8] =
                {5'd0, interrupt_enable_q, periodic_q, enabled_q};
            response_for_request.rdata[12*8 +: 8] = {7'd0, pending_q};
        end else if (request_in_range &&
                     (mem.req.command == M64K_MEM_ATOMIC)) begin
            response_for_request.fault = M64K_FAULT_UNSUPPORTED;
        end
    end

    assign mem.req_ready = !response_valid_q;
    assign mem.rsp_valid = response_valid_q;
    assign mem.rsp = response_q;
    assign irq_pending = pending_q && interrupt_enable_q;

    initial begin
        if (BASE_ADDR[11:0] != 12'd0)
            $fatal(1, "m64k_timer BASE_ADDR must be 4-KiB aligned");
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            response_valid_q <= 1'b0;
            response_q <= '0;
            cycle_counter_q <= 32'd0;
            interval_q <= 32'd0;
            remaining_q <= 32'd0;
            enabled_q <= 1'b0;
            periodic_q <= 1'b0;
            interrupt_enable_q <= 1'b0;
            pending_q <= 1'b0;
        end else begin
            cycle_counter_q <= cycle_counter_q + 1'b1;
            if (response_valid_q && mem.rsp_ready)
                response_valid_q <= 1'b0;

            if (enabled_q && (interval_q != 32'd0)) begin
                if (remaining_q <= 32'd1) begin
                    pending_q <= 1'b1;
                    if (periodic_q)
                        remaining_q <= interval_q;
                    else begin
                        remaining_q <= 32'd0;
                        enabled_q <= 1'b0;
                    end
                end else begin
                    remaining_q <= remaining_q - 1'b1;
                end
            end

            if (mem.req_valid && mem.req_ready) begin
                response_q <= response_for_request;
                response_valid_q <= 1'b1;
                if (request_access_valid &&
                    (mem.req.command == M64K_MEM_WRITE)) begin
                    if (&mem.req.wstrb[7:4]) begin
                        interval_q <= read_be32(mem.req.wdata, 4);
                        if (enabled_q)
                            remaining_q <= read_be32(mem.req.wdata, 4);
                    end
                    if (mem.req.wstrb[8]) begin
                        enabled_q <= mem.req.wdata[8*8 + 0];
                        periodic_q <= mem.req.wdata[8*8 + 1];
                        interrupt_enable_q <= mem.req.wdata[8*8 + 2];
                        if (mem.req.wdata[8*8 + 0])
                            remaining_q <= interval_q;
                    end
                    if (mem.req.wstrb[12] && mem.req.wdata[12*8])
                        pending_q <= 1'b0;
                end
            end
        end
    end
endmodule
