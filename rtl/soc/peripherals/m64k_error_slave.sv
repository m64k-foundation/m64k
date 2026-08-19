module m64k_error_slave #(
    parameter m64k_pkg::m64k_mem_fault_t FAULT = m64k_pkg::M64K_FAULT_ACCESS
) (
    input logic clk,
    input logic rst_n,
    m64k_mem_if.slave mem
);
    import m64k_pkg::*;

    logic response_valid_q;
    m64k_mem_rsp_t response_q;

    assign mem.req_ready = !response_valid_q;
    assign mem.rsp_valid = response_valid_q;
    assign mem.rsp = response_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            response_valid_q <= 1'b0;
            response_q <= '0;
        end else begin
            if (response_valid_q && mem.rsp_ready)
                response_valid_q <= 1'b0;
            if (mem.req_valid && mem.req_ready) begin
                response_q <= '0;
                response_q.txn_id <= mem.req.txn_id;
                response_q.source <= mem.req.source;
                response_q.fault <= FAULT;
                response_valid_q <= 1'b1;
            end
        end
    end
endmodule
