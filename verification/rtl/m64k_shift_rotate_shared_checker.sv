// External protocol properties for the unified shift/rotate candidate.
// Production synthesis intentionally excludes this verification-only file.
module m64k_shift_rotate_shared_checker (
    input logic clock,
    input logic reset,
    input logic request_valid,
    input logic request_ready,
    input m64k_execute_backend_pkg::m64k_execute_tag_t request_tag,
    input m64k_shift_rotate_pkg::m64k_shift_operation_t request_operation,
    input logic squash_valid,
    input m64k_shift_rotate_shared_pkg::m64k_shift_rotate_shared_squash_t squash,
    input logic response_valid,
    input logic response_ready,
    input m64k_shift_rotate_shared_pkg::m64k_shift_rotate_shared_response_t response
);
    import m64k_shift_rotate_pkg::*;

    logic request_is_rox;
    logic exact_accept_squash;
    logic accepts_ordinary;
    logic accepts_rox;

    always_comb begin
        request_is_rox = request_operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR};
        exact_accept_squash = squash_valid && squash.tag == request_tag;
        accepts_ordinary = request_valid && request_ready && !exact_accept_squash && !request_is_rox;
        accepts_rox = request_valid && request_ready && !exact_accept_squash && request_is_rox;
    end

    property held_response_is_stable;
        @(posedge clock) disable iff (reset)
        response_valid && !response_ready |=> response_valid && $stable(response);
    endproperty

    property published_response_is_irrevocable;
        @(posedge clock) disable iff (reset)
        response_valid && !response_ready && squash_valid && squash.tag == response.tag
            |=> response_valid && $stable(response);
    endproperty

    property ordinary_request_has_one_cycle_response;
        @(posedge clock) disable iff (reset)
        accepts_ordinary |=> response_valid && response.tag == $past(request_tag);
    endproperty

    property ordinary_stream_remains_ready;
        @(posedge clock) disable iff (reset)
        accepts_ordinary && response_ready |=> request_ready;
    endproperty

    property rox_uses_an_internal_second_pass;
        @(posedge clock) disable iff (reset)
        accepts_rox |=> !response_valid && !request_ready;
    endproperty

    property accept_time_squash_produces_no_response;
        @(posedge clock) disable iff (reset)
        request_valid && request_ready && exact_accept_squash |=> !response_valid;
    endproperty

    property second_pass_exact_squash_cancels;
        @(posedge clock) disable iff (reset)
        $past(accepts_rox) && squash_valid && squash.tag == $past(request_tag)
            |=> !response_valid && request_ready;
    endproperty

    assert property (held_response_is_stable);
    assert property (published_response_is_irrevocable);
    assert property (ordinary_request_has_one_cycle_response);
    assert property (ordinary_stream_remains_ready);
    assert property (rox_uses_an_internal_second_pass);
    assert property (accept_time_squash_produces_no_response);
    assert property (second_pass_exact_squash_cancels);
endmodule

bind m64k_shift_rotate_shared m64k_shift_rotate_shared_checker m64k_shift_rotate_shared_protocol_checker (
    .clock,
    .reset,
    .request_valid,
    .request_ready,
    .request_tag(request.tag),
    .request_operation(request.operation),
    .squash_valid,
    .squash,
    .response_valid,
    .response_ready,
    .response
);
