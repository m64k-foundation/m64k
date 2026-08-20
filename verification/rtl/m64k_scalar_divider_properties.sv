module m64k_scalar_divider_properties (
    input logic clock,
    input logic reset,
    input logic response_valid,
    input logic response_ready,
    input m64k_scalar_divider_pkg::m64k_divide_response_t response,
    input logic squash_valid,
    input logic iteration_active,
    input logic squash_matches_operation,
    input logic [7:0] iterations_remaining
);
    import m64k_execute_backend_pkg::*;

    property response_remains_valid_until_accepted;
        @(posedge clock) disable iff (reset)
        response_valid && !response_ready |=> response_valid;
    endproperty

    property held_response_is_stable;
        @(posedge clock) disable iff (reset)
        response_valid && !response_ready |=> response_valid && $stable(response);
    endproperty

    property squash_cannot_retract_published_response;
        @(posedge clock) disable iff (reset)
        response_valid && !response_ready && squash_valid |=> response_valid;
    endproperty

    property fault_response_has_no_effects;
        @(posedge clock) disable iff (reset)
        response_valid && response.fault_valid |-> response.result_count == 2'd0
            && !response.results[0].valid
            && !response.results[1].valid
            && response.results[0].value == 64'd0
            && response.results[1].value == 64'd0
            && !response.flags_valid
            && !response.negative
            && !response.zero
            && !response.overflow
            && !response.carry;
    endproperty

    property iteration_counter_is_bounded;
        @(posedge clock) disable iff (reset)
        iteration_active |-> iterations_remaining inside {[8'd1:8'd64]};
    endproperty

    property nonterminal_iteration_makes_progress;
        @(posedge clock) disable iff (reset)
        iteration_active && !squash_matches_operation && iterations_remaining > 8'd1
            |=> iteration_active && iterations_remaining == $past(iterations_remaining) - 8'd1;
    endproperty

    property terminal_iteration_publishes_response;
        @(posedge clock) disable iff (reset)
        iteration_active && !squash_matches_operation && iterations_remaining == 8'd1
            |=> response_valid;
    endproperty

    property single_result_response_is_compact;
        @(posedge clock) disable iff (reset)
        response_valid && !response.fault_valid && response.result_count == 2'd1
            |-> response.results[0].valid
                && !response.results[1].valid
                && response.results[0].role inside {M64K_EXECUTE_RESULT_QUOTIENT, M64K_EXECUTE_RESULT_REMAINDER};
    endproperty

    property fused_result_response_has_ordered_roles;
        @(posedge clock) disable iff (reset)
        response_valid && !response.fault_valid && response.result_count == 2'd2
            |-> response.results[0].valid
                && response.results[1].valid
                && response.results[0].role == M64K_EXECUTE_RESULT_QUOTIENT
                && response.results[1].role == M64K_EXECUTE_RESULT_REMAINDER;
    endproperty

    property successful_response_has_results;
        @(posedge clock) disable iff (reset)
        response_valid && !response.fault_valid |-> response.result_count inside {2'd1, 2'd2};
    endproperty

    assert property (response_remains_valid_until_accepted);
    assert property (held_response_is_stable);
    assert property (squash_cannot_retract_published_response);
    assert property (fault_response_has_no_effects);
    assert property (iteration_counter_is_bounded);
    assert property (nonterminal_iteration_makes_progress);
    assert property (terminal_iteration_publishes_response);
    assert property (single_result_response_is_compact);
    assert property (fused_result_response_has_ordered_roles);
    assert property (successful_response_has_results);
endmodule

bind m64k_scalar_divider m64k_scalar_divider_properties scalar_divider_properties (
    .clock(clock),
    .reset(reset),
    .response_valid(response_valid),
    .response_ready(response_ready),
    .response(response),
    .squash_valid(squash_valid),
    .iteration_active(state == DIVIDER_ITERATE),
    .squash_matches_operation(squash_matches_operation),
    .iterations_remaining(iterations_remaining)
);
