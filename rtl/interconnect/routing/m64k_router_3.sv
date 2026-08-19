module m64k_router_3 #(
    parameter bit PORT0_ENABLE = 1'b1,
    parameter logic [31:0] PORT0_BASE = 32'h0000_0000,
    parameter logic [31:0] PORT0_MASK = 32'h8000_0000,
    parameter bit PORT1_ENABLE = 1'b1,
    parameter logic [31:0] PORT1_BASE = 32'h8000_0000,
    parameter logic [31:0] PORT1_MASK = 32'hf000_0000,
    parameter bit PORT2_ENABLE = 1'b1,
    parameter logic [31:0] PORT2_BASE = 32'hf000_0000,
    parameter logic [31:0] PORT2_MASK = 32'hf000_0000
) (
    input logic clk,
    input logic rst_n,
    m64k_mem_if.slave upstream,
    m64k_mem_if.master port0,
    m64k_mem_if.master port1,
    m64k_mem_if.master port2
);
    import m64k_pkg::*;

    typedef enum logic [2:0] {
        ROUTER_IDLE,
        ROUTER_WAIT0,
        ROUTER_WAIT1,
        ROUTER_WAIT2,
        ROUTER_LOCAL_RESPONSE
    } router_state_t;

    router_state_t state_q;
    m64k_mem_rsp_t local_response_q;

    wire match0 = PORT0_ENABLE &&
                  ((upstream.req.addr & PORT0_MASK) == PORT0_BASE);
    wire match1 = PORT1_ENABLE &&
                  ((upstream.req.addr & PORT1_MASK) == PORT1_BASE);
    wire match2 = PORT2_ENABLE &&
                  ((upstream.req.addr & PORT2_MASK) == PORT2_BASE);

    function automatic logic regions_overlap(
        input logic [31:0] base_a,
        input logic [31:0] mask_a,
        input logic [31:0] base_b,
        input logic [31:0] mask_b
    );
        return (((base_a ^ base_b) & mask_a & mask_b) == 32'd0);
    endfunction

    function automatic logic mask_is_prefix(input logic [31:0] mask);
        logic [31:0] inverse;
        begin
            inverse = ~mask;
            return ((inverse & (inverse + 1'b1)) == 32'd0);
        end
    endfunction

    initial begin
        if (PORT0_ENABLE && ((PORT0_BASE & ~PORT0_MASK) != 32'd0))
            $fatal(1, "m64k_router_3 PORT0_BASE is not canonical for its mask");
        if (PORT1_ENABLE && ((PORT1_BASE & ~PORT1_MASK) != 32'd0))
            $fatal(1, "m64k_router_3 PORT1_BASE is not canonical for its mask");
        if (PORT2_ENABLE && ((PORT2_BASE & ~PORT2_MASK) != 32'd0))
            $fatal(1, "m64k_router_3 PORT2_BASE is not canonical for its mask");
        if (PORT0_ENABLE && !mask_is_prefix(PORT0_MASK))
            $fatal(1, "m64k_router_3 PORT0_MASK is not a contiguous prefix");
        if (PORT1_ENABLE && !mask_is_prefix(PORT1_MASK))
            $fatal(1, "m64k_router_3 PORT1_MASK is not a contiguous prefix");
        if (PORT2_ENABLE && !mask_is_prefix(PORT2_MASK))
            $fatal(1, "m64k_router_3 PORT2_MASK is not a contiguous prefix");
        if (PORT0_ENABLE && PORT1_ENABLE &&
            regions_overlap(PORT0_BASE, PORT0_MASK, PORT1_BASE, PORT1_MASK))
            $fatal(1, "m64k_router_3 PORT0 and PORT1 overlap");
        if (PORT0_ENABLE && PORT2_ENABLE &&
            regions_overlap(PORT0_BASE, PORT0_MASK, PORT2_BASE, PORT2_MASK))
            $fatal(1, "m64k_router_3 PORT0 and PORT2 overlap");
        if (PORT1_ENABLE && PORT2_ENABLE &&
            regions_overlap(PORT1_BASE, PORT1_MASK, PORT2_BASE, PORT2_MASK))
            $fatal(1, "m64k_router_3 PORT1 and PORT2 overlap");
    end

    always_comb begin
        port0.req_valid = 1'b0;
        port1.req_valid = 1'b0;
        port2.req_valid = 1'b0;
        port0.req = upstream.req;
        port1.req = upstream.req;
        port2.req = upstream.req;
        port0.rsp_ready = 1'b0;
        port1.rsp_ready = 1'b0;
        port2.rsp_ready = 1'b0;

        upstream.req_ready = 1'b0;
        upstream.rsp_valid = 1'b0;
        upstream.rsp = '0;

        case (state_q)
            ROUTER_IDLE: begin
                if (match0) begin
                    port0.req_valid = upstream.req_valid;
                    upstream.req_ready = port0.req_ready;
                end else if (match1) begin
                    port1.req_valid = upstream.req_valid;
                    upstream.req_ready = port1.req_ready;
                end else if (match2) begin
                    port2.req_valid = upstream.req_valid;
                    upstream.req_ready = port2.req_ready;
                end else begin
                    // Unmapped requests are accepted and completed locally.
                    upstream.req_ready = 1'b1;
                end
            end

            ROUTER_WAIT0: begin
                upstream.rsp_valid = port0.rsp_valid;
                upstream.rsp = port0.rsp;
                port0.rsp_ready = upstream.rsp_ready;
            end

            ROUTER_WAIT1: begin
                upstream.rsp_valid = port1.rsp_valid;
                upstream.rsp = port1.rsp;
                port1.rsp_ready = upstream.rsp_ready;
            end

            ROUTER_WAIT2: begin
                upstream.rsp_valid = port2.rsp_valid;
                upstream.rsp = port2.rsp;
                port2.rsp_ready = upstream.rsp_ready;
            end

            ROUTER_LOCAL_RESPONSE: begin
                upstream.rsp_valid = 1'b1;
                upstream.rsp = local_response_q;
            end

            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ROUTER_IDLE;
            local_response_q <= '0;
        end else begin
            case (state_q)
                ROUTER_IDLE: begin
                    if (upstream.req_valid && upstream.req_ready) begin
                        if (match0)
                            state_q <= ROUTER_WAIT0;
                        else if (match1)
                            state_q <= ROUTER_WAIT1;
                        else if (match2)
                            state_q <= ROUTER_WAIT2;
                        else begin
                            local_response_q <= '0;
                            local_response_q.txn_id <= upstream.req.txn_id;
                            local_response_q.source <= upstream.req.source;
                            local_response_q.fault <= M64K_FAULT_ACCESS;
                            state_q <= ROUTER_LOCAL_RESPONSE;
                        end
                    end
                end

                ROUTER_WAIT0: begin
                    if (port0.rsp_valid && port0.rsp_ready)
                        state_q <= ROUTER_IDLE;
                end

                ROUTER_WAIT1: begin
                    if (port1.rsp_valid && port1.rsp_ready)
                        state_q <= ROUTER_IDLE;
                end

                ROUTER_WAIT2: begin
                    if (port2.rsp_valid && port2.rsp_ready)
                        state_q <= ROUTER_IDLE;
                end

                ROUTER_LOCAL_RESPONSE: begin
                    if (upstream.rsp_ready)
                        state_q <= ROUTER_IDLE;
                end

                default: state_q <= ROUTER_IDLE;
            endcase
        end
    end
endmodule
