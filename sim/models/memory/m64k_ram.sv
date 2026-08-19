module m64k_ram #(
    parameter logic [31:0] BASE_ADDR = 32'h0000_0000,
    parameter int unsigned MEM_BYTES = 4096,
    parameter bit CLEAR_ON_INIT = 1'b1,
    parameter int unsigned REQUEST_STALL_CYCLES = 0,
    parameter bit INJECT_FAULT_ENABLE = 1'b0,
    parameter logic [31:0] INJECT_FAULT_ADDR = 32'd0,
    parameter bit INJECT_FAULT_READ = 1'b0,
    parameter bit INJECT_FAULT_WRITE = 1'b0,
    parameter logic [31:0] INJECT_FAULT_READ_ADDR = INJECT_FAULT_ADDR,
    parameter logic [31:0] INJECT_FAULT_WRITE_ADDR = INJECT_FAULT_ADDR,
    parameter m64k_pkg::m64k_mem_fault_t INJECT_FAULT_KIND =
        m64k_pkg::M64K_FAULT_ACCESS
) (
    input logic clk,
    input logic rst_n,
    m64k_mem_if.slave mem
);
    import m64k_pkg::*;

    logic [7:0] storage [0:MEM_BYTES-1];
    logic rsp_valid_q;
    m64k_mem_rsp_t rsp_q;
    logic [31:0] stall_count_q;

    wire [31:0] request_line = m64k_line_base(mem.req.addr);
    wire [32:0] request_delta = {1'b0, request_line} - {1'b0, BASE_ADDR};
    wire [32:0] request_end_offset = request_delta + 33'd16;
    wire request_in_range = !request_delta[32] &&
                            (request_end_offset <= {1'b0, MEM_BYTES});
    wire [31:0] request_offset = request_delta[31:0];
    wire inject_request_fault = INJECT_FAULT_ENABLE &&
        (((mem.req.command == M64K_MEM_READ) && INJECT_FAULT_READ &&
          (mem.req.addr == INJECT_FAULT_READ_ADDR)) ||
         (((mem.req.command == M64K_MEM_WRITE) ||
           (mem.req.command == M64K_MEM_ATOMIC)) && INJECT_FAULT_WRITE &&
          (mem.req.addr == INJECT_FAULT_WRITE_ADDR)));

    m64k_mem_rsp_t response_for_request;
    integer init_index;

    initial begin
        if ((MEM_BYTES == 0) || ((MEM_BYTES % M64K_LINE_BYTES) != 0))
            $fatal(1, "m64k_ram MEM_BYTES must be a non-zero multiple of 16");
        if (BASE_ADDR[3:0] != 4'b0000)
            $fatal(1, "m64k_ram BASE_ADDR must be 16-byte aligned");
        if (CLEAR_ON_INIT)
            for (init_index = 0; init_index < MEM_BYTES; init_index = init_index + 1)
                storage[init_index] = 8'h00;
    end

    always_comb begin
        response_for_request = '0;
        response_for_request.txn_id = mem.req.txn_id;
        response_for_request.source = mem.req.source;
        response_for_request.fault = M64K_FAULT_NONE;

        if (inject_request_fault) begin
            response_for_request.fault = INJECT_FAULT_KIND;
        end else if (!request_in_range) begin
            response_for_request.fault = M64K_FAULT_ACCESS;
        end else begin
            case (mem.req.command)
                M64K_MEM_READ: begin
                    for (int unsigned read_lane = 0;
                         read_lane < M64K_LINE_BYTES; read_lane = read_lane + 1)
                        response_for_request.rdata[read_lane*8 +: 8] =
                            storage[request_offset + read_lane];
                end
                M64K_MEM_WRITE,
                M64K_MEM_FENCE: begin
                    response_for_request.fault = M64K_FAULT_NONE;
                end
                M64K_MEM_ATOMIC: begin
                    // Atomic responders return the complete line as it was
                    // before the indivisible update.  TAS uses byte-wide OR;
                    // unsupported operations fail without modifying storage.
                    if (mem.req.atomic_op == M64K_ATOMIC_OR) begin
                        for (int unsigned read_lane = 0;
                             read_lane < M64K_LINE_BYTES;
                             read_lane = read_lane + 1)
                            response_for_request.rdata[read_lane*8 +: 8] =
                                storage[request_offset + read_lane];
                        response_for_request.atomic_success = 1'b1;
                    end else begin
                        response_for_request.fault = M64K_FAULT_UNSUPPORTED;
                    end
                end
                default: begin
                    response_for_request.fault = M64K_FAULT_UNSUPPORTED;
                end
            endcase
        end
    end

    generate
        if (REQUEST_STALL_CYCLES == 0) begin : g_no_request_stall
            assign mem.req_ready = !rsp_valid_q;
        end else begin : g_request_stall
            assign mem.req_ready = !rsp_valid_q &&
                                   (stall_count_q >= REQUEST_STALL_CYCLES);
        end
    endgenerate
    assign mem.rsp_valid = rsp_valid_q;
    assign mem.rsp = rsp_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rsp_valid_q <= 1'b0;
            rsp_q <= '0;
            stall_count_q <= '0;
        end else begin
            if (!mem.req_valid || rsp_valid_q)
                stall_count_q <= '0;
            else if (!mem.req_ready)
                stall_count_q <= stall_count_q + 1'b1;

            if (rsp_valid_q && mem.rsp_ready)
                rsp_valid_q <= 1'b0;

            if (mem.req_valid && mem.req_ready) begin
                rsp_q <= response_for_request;
                rsp_valid_q <= 1'b1;
                stall_count_q <= '0;

                if (request_in_range && !inject_request_fault &&
                    (mem.req.command == M64K_MEM_WRITE)) begin
                    for (int unsigned write_lane = 0;
                         write_lane < M64K_LINE_BYTES; write_lane = write_lane + 1)
                        if (mem.req.wstrb[write_lane])
                            storage[request_offset + write_lane] <=
                                mem.req.wdata[write_lane*8 +: 8];
                end else if (request_in_range && !inject_request_fault &&
                             (mem.req.command == M64K_MEM_ATOMIC) &&
                             (mem.req.atomic_op == M64K_ATOMIC_OR)) begin
                    for (int unsigned atomic_lane = 0;
                         atomic_lane < M64K_LINE_BYTES;
                         atomic_lane = atomic_lane + 1)
                        if (mem.req.wstrb[atomic_lane])
                            storage[request_offset + atomic_lane] <=
                                storage[request_offset + atomic_lane] |
                                mem.req.wdata[atomic_lane*8 +: 8];
                end
            end
        end
    end
endmodule
