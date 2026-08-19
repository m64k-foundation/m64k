interface m64k_mem_if (
    input logic clk,
    input logic rst_n
);
    import m64k_pkg::*;

    logic req_valid;
    logic req_ready;
    m64k_mem_req_t req;

    logic rsp_valid;
    logic rsp_ready;
    m64k_mem_rsp_t rsp;

    // A sender owns its payload until the receiver accepts it. Keeping these
    // assertions at the interface boundary makes every future master/slave
    // inherit the same protocol contract in simulation and formal runs.
    property request_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            req_valid && !req_ready |=> req_valid && $stable(req);
    endproperty
    assert property (request_stable_while_blocked);

    property response_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            rsp_valid && !rsp_ready |=> rsp_valid && $stable(rsp);
    endproperty
    assert property (response_stable_while_blocked);

    modport master (
        output req_valid,
        output req,
        input  req_ready,
        input  rsp_valid,
        input  rsp,
        output rsp_ready
    );

    modport slave (
        input  req_valid,
        input  req,
        output req_ready,
        output rsp_valid,
        output rsp,
        input  rsp_ready
    );

    modport monitor (
        input req_valid,
        input req_ready,
        input req,
        input rsp_valid,
        input rsp_ready,
        input rsp
    );
endinterface
