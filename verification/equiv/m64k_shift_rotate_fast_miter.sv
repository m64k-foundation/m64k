module m64k_shift_rotate_fast_miter (
    input logic [63:0] source,
    input logic [5:0] count,
    input logic [1:0] operand_size,
    input logic [2:0] operation,
    input logic extend_in,
    input logic update_flags,
    output logic supported_operation,
    output logic support_contract_match,
    output logic supported_outputs_match,
    output logic unsupported_outputs_benign,
    output logic reference_extend_contract_match,
    output logic miter_pass
);
    logic [63:0] reference_result;
    logic reference_result_valid;
    logic reference_negative;
    logic reference_zero;
    logic reference_overflow;
    logic reference_carry;
    logic reference_flags_valid;
    logic reference_extend_out;
    logic reference_extend_valid;

    logic candidate_supported;
    logic [63:0] candidate_result;
    logic candidate_result_valid;
    logic candidate_negative;
    logic candidate_zero;
    logic candidate_overflow;
    logic candidate_carry;
    logic candidate_flags_valid;

    m64k_shift_rotate reference_dut (
        .source,
        .count,
        .operand_size,
        .operation,
        .extend_in,
        .update_flags,
        .result(reference_result),
        .result_valid(reference_result_valid),
        .negative(reference_negative),
        .zero(reference_zero),
        .overflow(reference_overflow),
        .carry(reference_carry),
        .flags_valid(reference_flags_valid),
        .extend_out(reference_extend_out),
        .extend_valid(reference_extend_valid)
    );

    m64k_shift_rotate_fast candidate_dut (
        .source,
        .count,
        .operand_size,
        .operation,
        .update_flags,
        .operation_supported(candidate_supported),
        .result(candidate_result),
        .result_valid(candidate_result_valid),
        .negative(candidate_negative),
        .zero(candidate_zero),
        .overflow(candidate_overflow),
        .carry(candidate_carry),
        .flags_valid(candidate_flags_valid)
    );

    always_comb begin
        supported_operation = operation <= 3'd5;
        support_contract_match = candidate_supported == supported_operation;

        supported_outputs_match =
            (candidate_result == reference_result) &&
            (candidate_result_valid == reference_result_valid) &&
            (candidate_negative == reference_negative) &&
            (candidate_zero == reference_zero) &&
            (candidate_overflow == reference_overflow) &&
            (candidate_carry == reference_carry) &&
            (candidate_flags_valid == reference_flags_valid);

        reference_extend_contract_match = !reference_extend_valid && (reference_extend_out == extend_in);

        unsupported_outputs_benign =
            !candidate_supported &&
            !candidate_result_valid &&
            (candidate_result == 64'd0) &&
            !candidate_negative &&
            !candidate_zero &&
            !candidate_overflow &&
            !candidate_carry &&
            !candidate_flags_valid;

        miter_pass =
            support_contract_match &&
            (supported_operation ? (supported_outputs_match && reference_extend_contract_match) : unsupported_outputs_benign);
    end
endmodule
