module m64k_shift_rotate_fast_tb;
    import m64k_shift_rotate_pkg::*;

    logic [63:0] source;
    logic [5:0] count;
    m64k_shift_size_t operand_size;
    m64k_shift_operation_t operation;
    logic update_flags;

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
        .extend_in(1'b0),
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

    task automatic fail(input string field_name, input logic [63:0] expected, input logic [63:0] observed);
        $fatal(
            1,
            "%s mismatch: operation=%s size=%s source=%016x count=%0d F=%0b expected=%016x observed=%016x",
            field_name,
            operation.name(),
            operand_size.name(),
            source,
            count,
            update_flags,
            expected,
            observed
        );
    endtask

    task automatic check_bit(input string field_name, input logic expected, input logic observed);
        if (observed !== expected) begin
            fail(field_name, 64'(expected), 64'(observed));
        end
    endtask

    task automatic check_supported_case(
        input logic [63:0] selected_source,
        input logic [5:0] selected_count,
        input m64k_shift_size_t selected_size,
        input m64k_shift_operation_t selected_operation,
        input logic selected_update_flags
    );
        source = selected_source;
        count = selected_count;
        operand_size = selected_size;
        operation = selected_operation;
        update_flags = selected_update_flags;
        #1;

        check_bit("operation-supported", 1'b1, candidate_supported);
        check_bit("reference-result-valid", 1'b1, reference_result_valid);
        check_bit("candidate-result-valid", reference_result_valid, candidate_result_valid);
        check_bit("reference-extend-valid", 1'b0, reference_extend_valid);
        check_bit("reference-extend-out", 1'b0, reference_extend_out);

        if (candidate_result !== reference_result) begin
            fail("result", reference_result, candidate_result);
        end

        check_bit("flags-valid", reference_flags_valid, candidate_flags_valid);
        if (selected_update_flags) begin
            check_bit("negative", reference_negative, candidate_negative);
            check_bit("zero", reference_zero, candidate_zero);
            check_bit("overflow", reference_overflow, candidate_overflow);
            check_bit("carry", reference_carry, candidate_carry);
        end
    endtask

    task automatic check_byte_exhaustive;
        for (integer unsigned operation_index = 0; operation_index < 6; operation_index++) begin
            for (integer unsigned value = 0; value < 256; value++) begin
                for (integer unsigned selected_count = 0; selected_count < 64; selected_count++) begin
                    check_supported_case(
                        64'(value),
                        6'(selected_count),
                        M64K_SHIFT_SIZE_BYTE,
                        m64k_shift_operation_t'(operation_index),
                        1'b0
                    );
                    check_supported_case(
                        64'(value),
                        6'(selected_count),
                        M64K_SHIFT_SIZE_BYTE,
                        m64k_shift_operation_t'(operation_index),
                        1'b1
                    );
                end
            end
        end
    endtask

    task automatic check_wide_value(
        input m64k_shift_size_t selected_size,
        input logic [63:0] selected_value,
        input integer unsigned width
    );
        for (integer unsigned operation_index = 0; operation_index < 6; operation_index++) begin
            for (integer unsigned flag_index = 0; flag_index < 2; flag_index++) begin
                check_supported_case(selected_value, 6'd0, selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                check_supported_case(selected_value, 6'd1, selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                check_supported_case(selected_value, 6'(width - 1), selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                if (width < 64) begin
                    check_supported_case(selected_value, 6'(width), selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                    check_supported_case(selected_value, 6'(width + 1), selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                end
                check_supported_case(selected_value, 6'd32, selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                check_supported_case(selected_value, 6'd33, selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
                check_supported_case(selected_value, 6'd63, selected_size, m64k_shift_operation_t'(operation_index), 1'(flag_index));
            end
        end
    endtask

    task automatic check_reproducible_random_cases;
        logic [63:0] random_state;
        logic [2:0] random_operation;

        random_state = 64'h6d64_4b73_c2a5_91e7;
        for (integer unsigned case_index = 0; case_index < 4096; case_index++) begin
            random_state = {random_state[62:0], random_state[63] ^ random_state[62] ^ random_state[60] ^ random_state[59]};
            random_operation = random_state[18:16];
            if (random_operation >= 3'd6) begin
                random_operation = random_operation - 3'd6;
            end
            check_supported_case(
                random_state,
                random_state[13:8],
                m64k_shift_size_t'(random_state[15:14]),
                m64k_shift_operation_t'(random_operation),
                random_state[19]
            );
        end
    endtask

    task automatic check_wide_boundaries;
        check_wide_value(M64K_SHIFT_SIZE_WORD, 64'd0, 16);
        check_wide_value(M64K_SHIFT_SIZE_WORD, 64'd1, 16);
        check_wide_value(M64K_SHIFT_SIZE_WORD, 64'h0000_0000_0000_7fff, 16);
        check_wide_value(M64K_SHIFT_SIZE_WORD, 64'h0000_0000_0000_8000, 16);
        check_wide_value(M64K_SHIFT_SIZE_WORD, 64'h0000_0000_0000_ffff, 16);
        check_wide_value(M64K_SHIFT_SIZE_WORD, 64'h0000_0000_0000_aa55, 16);

        check_wide_value(M64K_SHIFT_SIZE_LONG, 64'd0, 32);
        check_wide_value(M64K_SHIFT_SIZE_LONG, 64'd1, 32);
        check_wide_value(M64K_SHIFT_SIZE_LONG, 64'h0000_0000_7fff_ffff, 32);
        check_wide_value(M64K_SHIFT_SIZE_LONG, 64'h0000_0000_8000_0000, 32);
        check_wide_value(M64K_SHIFT_SIZE_LONG, 64'h0000_0000_ffff_ffff, 32);
        check_wide_value(M64K_SHIFT_SIZE_LONG, 64'h0000_0000_aa55_aa55, 32);

        check_wide_value(M64K_SHIFT_SIZE_QUAD, 64'd0, 64);
        check_wide_value(M64K_SHIFT_SIZE_QUAD, 64'd1, 64);
        check_wide_value(M64K_SHIFT_SIZE_QUAD, 64'h7fff_ffff_ffff_ffff, 64);
        check_wide_value(M64K_SHIFT_SIZE_QUAD, 64'h8000_0000_0000_0000, 64);
        check_wide_value(M64K_SHIFT_SIZE_QUAD, 64'hffff_ffff_ffff_ffff, 64);
        check_wide_value(M64K_SHIFT_SIZE_QUAD, 64'haa55_aa55_aa55_aa55, 64);

    endtask

    task automatic check_rox_is_not_claimed;
        source = 64'h0123_4567_89ab_cdef;
        count = 6'd17;
        operand_size = M64K_SHIFT_SIZE_QUAD;
        update_flags = 1'b1;

        operation = M64K_SHIFT_ROXL;
        #1;
        check_bit("ROXL-operation-supported", 1'b0, candidate_supported);
        check_bit("ROXL-result-valid", 1'b0, candidate_result_valid);
        check_bit("ROXL-flags-valid", 1'b0, candidate_flags_valid);
        check_bit("ROXL-negative", 1'b0, candidate_negative);
        check_bit("ROXL-zero", 1'b0, candidate_zero);
        check_bit("ROXL-overflow", 1'b0, candidate_overflow);
        check_bit("ROXL-carry", 1'b0, candidate_carry);
        if (candidate_result !== 64'd0) begin
            fail("ROXL-result", 64'd0, candidate_result);
        end

        operation = M64K_SHIFT_ROXR;
        #1;
        check_bit("ROXR-operation-supported", 1'b0, candidate_supported);
        check_bit("ROXR-result-valid", 1'b0, candidate_result_valid);
        check_bit("ROXR-flags-valid", 1'b0, candidate_flags_valid);
        check_bit("ROXR-negative", 1'b0, candidate_negative);
        check_bit("ROXR-zero", 1'b0, candidate_zero);
        check_bit("ROXR-overflow", 1'b0, candidate_overflow);
        check_bit("ROXR-carry", 1'b0, candidate_carry);
        if (candidate_result !== 64'd0) begin
            fail("ROXR-result", 64'd0, candidate_result);
        end
    endtask

    initial begin
        source = 64'd0;
        count = 6'd0;
        operand_size = M64K_SHIFT_SIZE_QUAD;
        operation = M64K_SHIFT_LSL;
        update_flags = 1'b0;

        check_byte_exhaustive();
        check_wide_boundaries();
        check_reproducible_random_cases();
        check_rox_is_not_claimed();

        $display("M64K fast shift/rotate candidate matches the complete architectural reference");
        $finish;
    end
endmodule
