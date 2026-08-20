module m64k_scalar_multiply_properties (
    input logic clock,
    input logic reset,
    input logic response_valid,
    input logic response_ready,
    input m64k_scalar_multiply_pkg::m64k_multiply_response_t response
);
    import m64k_execute_backend_pkg::*;

    assert property (@(posedge clock) disable iff (reset) response_valid && !response_ready |=> response_valid && $stable(response));
    assert property (@(posedge clock) disable iff (reset) response_valid |-> response.result_count inside {2'd1, 2'd2});
    assert property (@(posedge clock) disable iff (reset) response_valid && response.result_count == 2'd2 |-> response.results[0].valid && response.results[1].valid && response.results[0].role == M64K_EXECUTE_RESULT_LOW && response.results[1].role == M64K_EXECUTE_RESULT_HIGH);
endmodule

bind m64k_scalar_multiply m64k_scalar_multiply_properties scalar_multiply_properties (
    .clock(clock),
    .reset(reset),
    .response_valid(response_valid),
    .response_ready(response_ready),
    .response(response)
);
