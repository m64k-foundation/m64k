// Registered, exactly tagged execution wrapper for the scalar integer ALU.
module m64k_integer_execute (
    input  logic clock,
    input  logic reset,
    input  logic request_valid,
    output logic request_ready,
    input  m64k_integer_execute_pkg::m64k_integer_execute_request_t request,
    output logic response_valid,
    input  logic response_ready,
    output m64k_integer_execute_pkg::m64k_integer_execute_response_t response,
    output logic integrity_error,
    input  logic squash_valid,
    input  m64k_integer_execute_pkg::m64k_integer_execute_squash_t squash
);
    import m64k_execute_backend_pkg::*;
    import m64k_integer_alu_pkg::*;
    import m64k_integer_execute_pkg::*;

    logic [63:0] alu_result;
    logic alu_result_valid;
    logic alu_negative;
    logic alu_zero;
    logic alu_overflow;
    logic alu_carry_or_borrow;
    logic alu_flags_valid;
    logic alu_extend;
    logic alu_extend_valid;

    logic response_register_valid;
    m64k_integer_execute_response_t response_register;
    m64k_integer_execute_response_t calculated_response;
    logic response_slot_available;
    logic accepted_request_is_squashed;
    logic request_accepted;
    logic request_operation_is_legal;

    m64k_integer_alu integer_alu (
        .source_left(request.source_left),
        .source_right(request.source_right),
        .operand_size(request.operand_size),
        .operation(request.operation),
        .extend_in(request.extend_in),
        .update_flags(request.update_flags),
        .result(alu_result),
        .result_valid(alu_result_valid),
        .negative(alu_negative),
        .zero(alu_zero),
        .overflow(alu_overflow),
        .carry_or_borrow(alu_carry_or_borrow),
        .flags_valid(alu_flags_valid),
        .extend_out(alu_extend),
        .extend_valid(alu_extend_valid)
    );

    always_comb begin
        response_slot_available = !response_register_valid || response_ready;
        request_operation_is_legal = m64k_integer_operation_is_legal(request.operation);
        request_ready = response_slot_available && request_operation_is_legal;
        integrity_error = request_valid && !request_operation_is_legal;
        response_valid = response_register_valid;
        response = response_register;

        accepted_request_is_squashed = squash_valid && request.tag == squash.tag;
        request_accepted = request_valid && request_ready && !accepted_request_is_squashed;

        calculated_response = '0;
        calculated_response.tag = request.tag;
        calculated_response.result_valid = alu_result_valid;
        calculated_response.result.valid = alu_result_valid;
        calculated_response.result.role = M64K_EXECUTE_RESULT_LOW;
        calculated_response.result.value = alu_result;
        calculated_response.flags_valid = alu_flags_valid;
        calculated_response.negative = alu_negative;
        calculated_response.zero = alu_zero;
        calculated_response.overflow = alu_overflow;
        calculated_response.carry_or_borrow = alu_carry_or_borrow;
        calculated_response.extend_valid = alu_extend_valid;
        calculated_response.extend = alu_extend;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            response_register_valid <= 1'b0;
        end else if (response_slot_available) begin
            response_register_valid <= request_accepted;

            if (request_accepted) begin
                response_register <= calculated_response;
            end
        end
    end

endmodule
