module m64k_sysinfo #(
    parameter logic [31:0] BASE_ADDR = 32'h00f0_2000,
    parameter int unsigned CORE_COUNT = 1,
    parameter int unsigned CORE_ID = 0,
    parameter int unsigned THREAD_ID = 0,
    parameter int unsigned PHYS_ADDR_WIDTH = 32,
    parameter int unsigned RAM_BYTES = 4 * 1024 * 1024
) (
    input logic clk,
    input logic rst_n,
    m64k_mem_if.slave mem
);
    import m64k_pkg::*;

    logic response_valid_q;
    m64k_mem_rsp_t response_q;
    m64k_mem_rsp_t response_for_request;
    logic request_in_range;
    logic [31:0] request_line;
    logic request_access_valid;

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
                          (mem.req.addr == (BASE_ADDR + 32'h08)) ||
                          (mem.req.addr == (BASE_ADDR + 32'h0c)) ||
                          (mem.req.addr == (BASE_ADDR + 32'h10)) ||
                          (mem.req.addr == (BASE_ADDR + 32'h14)) ||
                          (mem.req.addr == (BASE_ADDR + 32'h18)) ||
                          (mem.req.addr == (BASE_ADDR + 32'h1c))) &&
                         (mem.req.size == M64K_SIZE_LONG)) ||
                        (((mem.req.addr == (BASE_ADDR + 32'h04)) ||
                          (mem.req.addr == (BASE_ADDR + 32'h06))) &&
                         (mem.req.size == M64K_SIZE_WORD));
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
            case (request_line - BASE_ADDR)
                32'h00: begin
                    write_be32_to_line(response_for_request, 0, 32'h4d36_344b);
                    response_for_request.rdata[4*8 +: 8] = 8'h00;
                    response_for_request.rdata[5*8 +: 8] = 8'h01;
                    response_for_request.rdata[6*8 +: 8] = 8'h00;
                    response_for_request.rdata[7*8 +: 8] = 8'h00;
                    write_be32_to_line(response_for_request, 8, 32'h0000_0001);
                    write_be32_to_line(response_for_request, 12, 32'(CORE_COUNT));
                end
                32'h10: begin
                    write_be32_to_line(response_for_request, 0, 32'(CORE_ID));
                    write_be32_to_line(response_for_request, 4, 32'(THREAD_ID));
                    write_be32_to_line(response_for_request, 8,
                                       32'(PHYS_ADDR_WIDTH));
                    write_be32_to_line(response_for_request, 12, 32'(RAM_BYTES));
                end
                default: begin end
            endcase
        end
    end

    assign mem.req_ready = !response_valid_q;
    assign mem.rsp_valid = response_valid_q;
    assign mem.rsp = response_q;

    initial begin
        if (BASE_ADDR[11:0] != 12'd0)
            $fatal(1, "m64k_sysinfo BASE_ADDR must be 4-KiB aligned");
        if ((CORE_COUNT == 0) || (CORE_ID >= CORE_COUNT))
            $fatal(1, "m64k_sysinfo CORE_ID must identify a populated core");
        if (PHYS_ADDR_WIDTH != M64K_ADDR_WIDTH)
            $fatal(1, "m64k_sysinfo cannot advertise an address width different from the v0 fabric");
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            response_valid_q <= 1'b0;
            response_q <= '0;
        end else begin
            if (response_valid_q && mem.rsp_ready)
                response_valid_q <= 1'b0;
            if (mem.req_valid && mem.req_ready) begin
                response_q <= response_for_request;
                response_valid_q <= 1'b1;
            end
        end
    end
endmodule
