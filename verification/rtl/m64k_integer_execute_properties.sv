module m64k_integer_execute_properties (
    input logic clock,
    input logic reset,
    input logic response_valid,
    input logic response_ready,
    input m64k_integer_execute_pkg::m64k_integer_execute_response_t response,
    input logic request_valid,
    input logic request_ready,
    input logic integrity_error,
    input logic squash_valid
);
    property response_stays_stable_while_blocked;
        @(posedge clock) disable iff (reset)
            response_valid && !response_ready |=> response_valid && $stable(response);
    endproperty

    property squash_does_not_retract_published_response;
        @(posedge clock) disable iff (reset)
            response_valid && !response_ready && squash_valid |=> response_valid;
    endproperty

    property response_result_validity_is_consistent;
        @(posedge clock) disable iff (reset)
            response_valid |-> response.result_valid == response.result.valid;
    endproperty

    property integrity_error_rejects_request;
        @(posedge clock) disable iff (reset)
            integrity_error |-> request_valid && !request_ready;
    endproperty

    assert property (response_stays_stable_while_blocked);
    assert property (squash_does_not_retract_published_response);
    assert property (response_result_validity_is_consistent);
    assert property (integrity_error_rejects_request);
endmodule

bind m64k_integer_execute m64k_integer_execute_properties integer_execute_properties (
    .clock(clock),
    .reset(reset),
    .response_valid(response_valid),
    .response_ready(response_ready),
    .response(response),
    .request_valid(request_valid),
    .request_ready(request_ready),
    .integrity_error(integrity_error),
    .squash_valid(squash_valid)
);
