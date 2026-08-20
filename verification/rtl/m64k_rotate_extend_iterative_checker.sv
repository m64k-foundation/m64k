// External protocol checker for m64k_rotate_extend_iterative. Production RTL
// contains no verification compile switches; warning-fatal simulation and
// formal targets must compile and bind this checker explicitly with assertions
// enabled. Synthesis manifests intentionally omit this verification-only file.
module m64k_rotate_extend_iterative_checker (
    input logic clock,
    input logic reset,
    input logic request_valid,
    input logic request_ready,
    input m64k_execute_backend_pkg::m64k_execute_tag_t request_tag,
    input logic squash_valid,
    input m64k_rotate_extend_iterative_pkg::m64k_rotate_extend_squash_t squash,
    input logic response_valid,
    input logic response_ready,
    input m64k_rotate_extend_iterative_pkg::m64k_rotate_extend_response_t response
);
    import m64k_execute_backend_pkg::*;

    logic outstanding;
    logic cancelled;
    logic [2:0] elapsed_cycles;
    m64k_execute_tag_t accepted_tag;

    logic accepts_request;
    logic exact_accept_squash;
    logic exact_active_squash;

    always_comb begin
        exact_accept_squash = squash_valid && squash.tag == request_tag;
        accepts_request = request_valid && request_ready && !exact_accept_squash;
        exact_active_squash = squash_valid && outstanding && squash.tag == accepted_tag;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            outstanding <= 1'b0;
            cancelled <= 1'b0;
            elapsed_cycles <= 3'd0;
            accepted_tag <= '0;
        end else begin
            if (accepts_request) begin
                outstanding <= 1'b1;
                cancelled <= 1'b0;
                elapsed_cycles <= 3'd0;
                accepted_tag <= request_tag;
            end else if (outstanding && !response_valid) begin
                elapsed_cycles <= elapsed_cycles + 3'd1;
            end

            if (exact_active_squash && !response_valid) begin
                outstanding <= 1'b0;
                cancelled <= 1'b1;
            end

            if (response_valid && response_ready) begin
                outstanding <= 1'b0;
            end
        end
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

    property x_and_result_are_published_together;
        @(posedge clock) disable iff (reset)
        response_valid |-> response.extend_valid;
    endproperty

    property carry_matches_x;
        @(posedge clock) disable iff (reset)
        response_valid |-> response.carry == response.extend_out;
    endproperty

    property no_unsolicited_response;
        @(posedge clock) disable iff (reset)
        response_valid |-> outstanding && !cancelled && response.tag == accepted_tag;
    endproperty

    property fixed_execution_latency;
        @(posedge clock) disable iff (reset)
        response_valid && !$past(response_valid) |-> elapsed_cycles == 3'd6;
    endproperty

    property unpublished_squash_cancels;
        @(posedge clock) disable iff (reset)
        exact_active_squash && !response_valid |=> !response_valid && request_ready;
    endproperty

    assert property (held_response_is_stable);
    assert property (published_response_is_irrevocable);
    assert property (x_and_result_are_published_together);
    assert property (carry_matches_x);
    assert property (no_unsolicited_response);
    assert property (fixed_execution_latency);
    assert property (unpublished_squash_cancels);
endmodule

bind m64k_rotate_extend_iterative m64k_rotate_extend_iterative_checker m64k_rotate_extend_iterative_protocol_checker (
    .clock,
    .reset,
    .request_valid,
    .request_ready,
    .request_tag(request.tag),
    .squash_valid,
    .squash,
    .response_valid,
    .response_ready,
    .response
);
