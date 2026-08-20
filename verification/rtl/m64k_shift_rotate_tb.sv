module m64k_shift_rotate_tb;
    import m64k_shift_rotate_pkg::*;

    logic [63:0] source;
    logic [5:0] count;
    m64k_shift_size_t operand_size;
    m64k_shift_operation_t operation;
    logic extend_in;
    logic update_flags;
    logic [63:0] result;
    logic result_valid;
    logic negative;
    logic zero;
    logic overflow;
    logic carry;
    logic flags_valid;
    logic extend_out;
    logic extend_valid;

    m64k_shift_rotate dut (
        .source,
        .count,
        .operand_size,
        .operation,
        .extend_in,
        .update_flags,
        .result,
        .result_valid,
        .negative,
        .zero,
        .overflow,
        .carry,
        .flags_valid,
        .extend_out,
        .extend_valid
    );

    task automatic fail_bit(input string field_name, input logic expected, input logic observed);
        $fatal(
            1,
            "%s mismatch: operation=%s size=%s source=%016x count=%0d X=%0b F=%0b expected=%0b observed=%0b",
            field_name,
            operation.name(),
            operand_size.name(),
            source,
            count,
            extend_in,
            update_flags,
            expected,
            observed
        );
    endtask

    task automatic fail_value(input logic [63:0] expected, input logic [63:0] observed);
        $fatal(
            1,
            "result mismatch: operation=%s size=%s source=%016x count=%0d X=%0b F=%0b expected=%016x observed=%016x",
            operation.name(),
            operand_size.name(),
            source,
            count,
            extend_in,
            update_flags,
            expected,
            observed
        );
    endtask

    task automatic check_bit(input string field_name, input logic expected, input logic observed);
        if (observed !== expected) begin
            fail_bit(field_name, expected, observed);
        end
    endtask

    task automatic reference_operation(
        input logic [63:0] selected_source,
        input logic [5:0] selected_count,
        input m64k_shift_size_t selected_size,
        input m64k_shift_operation_t selected_operation,
        input logic selected_extend,
        output logic [63:0] expected_result,
        output logic expected_negative,
        output logic expected_zero,
        output logic expected_overflow,
        output logic expected_carry,
        output logic expected_extend
    );
        integer unsigned iteration_count;
        logic [63:0] width_mask;
        logic [63:0] sign_mask;
        logic [63:0] working_value;
        logic shifted_bit;
        logic sign_before;
        logic sign_after;

        case (selected_size)
            M64K_SHIFT_SIZE_BYTE: begin
                width_mask = 64'h0000_0000_0000_00ff;
                sign_mask = 64'h0000_0000_0000_0080;
            end
            M64K_SHIFT_SIZE_WORD: begin
                width_mask = 64'h0000_0000_0000_ffff;
                sign_mask = 64'h0000_0000_0000_8000;
            end
            M64K_SHIFT_SIZE_LONG: begin
                width_mask = 64'h0000_0000_ffff_ffff;
                sign_mask = 64'h0000_0000_8000_0000;
            end
            M64K_SHIFT_SIZE_QUAD: begin
                width_mask = 64'hffff_ffff_ffff_ffff;
                sign_mask = 64'h8000_0000_0000_0000;
            end
        endcase

        iteration_count = 32'(selected_count);
        working_value = selected_source & width_mask;
        expected_extend = selected_extend;
        expected_overflow = 1'b0;
        expected_carry = 1'b0;

        for (integer unsigned step = 0; step < iteration_count; step++) begin
            case (selected_operation)
                M64K_SHIFT_ASL: begin
                    sign_before = (working_value & sign_mask) != 64'd0;
                    shifted_bit = sign_before;
                    working_value = (working_value << 1) & width_mask;
                    sign_after = (working_value & sign_mask) != 64'd0;
                    expected_overflow |= sign_before != sign_after;
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_LSL: begin
                    shifted_bit = (working_value & sign_mask) != 64'd0;
                    working_value = (working_value << 1) & width_mask;
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_ASR: begin
                    shifted_bit = working_value[0];
                    sign_before = (working_value & sign_mask) != 64'd0;
                    working_value = working_value >> 1;
                    if (sign_before) begin
                        working_value |= sign_mask;
                    end
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_LSR: begin
                    shifted_bit = working_value[0];
                    working_value = working_value >> 1;
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_ROL: begin
                    shifted_bit = (working_value & sign_mask) != 64'd0;
                    working_value = ((working_value << 1) & width_mask) | 64'(shifted_bit);
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_ROR: begin
                    shifted_bit = working_value[0];
                    working_value = (working_value >> 1) | (shifted_bit ? sign_mask : 64'd0);
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_ROXL: begin
                    shifted_bit = (working_value & sign_mask) != 64'd0;
                    working_value = ((working_value << 1) & width_mask) | 64'(expected_extend);
                    expected_extend = shifted_bit;
                    expected_carry = shifted_bit;
                end
                M64K_SHIFT_ROXR: begin
                    shifted_bit = working_value[0];
                    working_value = (working_value >> 1) | (expected_extend ? sign_mask : 64'd0);
                    expected_extend = shifted_bit;
                    expected_carry = shifted_bit;
                end
            endcase
        end

        if (iteration_count == 0) begin
            if (selected_operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR}) begin
                expected_carry = selected_extend;
            end else begin
                expected_carry = 1'b0;
            end
        end

        expected_result = working_value & width_mask;
        expected_negative = (expected_result & sign_mask) != 64'd0;
        expected_zero = expected_result == 64'd0;
    endtask

    task automatic check_case(
        input logic [63:0] selected_source,
        input logic [5:0] selected_count,
        input m64k_shift_size_t selected_size,
        input m64k_shift_operation_t selected_operation,
        input logic selected_extend,
        input logic selected_update_flags
    );
        logic [63:0] expected_result;
        logic expected_negative;
        logic expected_zero;
        logic expected_overflow;
        logic expected_carry;
        logic expected_extend;
        logic expected_extend_valid;

        source = selected_source;
        count = selected_count;
        operand_size = selected_size;
        operation = selected_operation;
        extend_in = selected_extend;
        update_flags = selected_update_flags;

        reference_operation(
            selected_source,
            selected_count,
            selected_size,
            selected_operation,
            selected_extend,
            expected_result,
            expected_negative,
            expected_zero,
            expected_overflow,
            expected_carry,
            expected_extend
        );

        #1;

        if (result !== expected_result) begin
            fail_value(expected_result, result);
        end

        expected_extend_valid = selected_operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR};
        check_bit("result-valid", 1'b1, result_valid);
        check_bit("flags-valid", selected_update_flags, flags_valid);
        check_bit("extend-valid", expected_extend_valid, extend_valid);

        if (expected_extend_valid) begin
            check_bit("extend", expected_extend, extend_out);
        end

        if (selected_update_flags) begin
            check_bit("negative", expected_negative, negative);
            check_bit("zero", expected_zero, zero);
            check_bit("overflow", expected_overflow, overflow);
            check_bit("carry", expected_carry, carry);
        end
    endtask

    task automatic check_byte_exhaustive;
        for (integer unsigned operation_index = 0; operation_index < 8; operation_index++) begin
            for (integer unsigned value = 0; value < 256; value++) begin
                for (integer unsigned selected_count = 0; selected_count < 64; selected_count++) begin
                    for (integer unsigned selected_extend = 0; selected_extend < 2; selected_extend++) begin
                        check_case(
                            64'(value),
                            6'(selected_count),
                            M64K_SHIFT_SIZE_BYTE,
                            m64k_shift_operation_t'(operation_index),
                            logic'(selected_extend),
                            1'b1
                        );
                        check_case(
                            64'(value),
                            6'(selected_count),
                            M64K_SHIFT_SIZE_BYTE,
                            m64k_shift_operation_t'(operation_index),
                            logic'(selected_extend),
                            1'b0
                        );
                    end
                end
            end
        end
    endtask

    task automatic check_wide_value(
        input m64k_shift_size_t selected_size,
        input logic [63:0] selected_value,
        input integer unsigned width
    );
        for (integer unsigned operation_index = 0; operation_index < 8; operation_index++) begin
            for (integer unsigned selected_extend = 0; selected_extend < 2; selected_extend++) begin
                check_case(selected_value, 6'd0, selected_size, m64k_shift_operation_t'(operation_index), logic'(selected_extend), 1'b1);
                check_case(selected_value, 6'd1, selected_size, m64k_shift_operation_t'(operation_index), logic'(selected_extend), 1'b1);
                check_case(selected_value, 6'(width - 1), selected_size, m64k_shift_operation_t'(operation_index), logic'(selected_extend), 1'b1);
                if (width < 64) begin
                    check_case(selected_value, 6'(width), selected_size, m64k_shift_operation_t'(operation_index), logic'(selected_extend), 1'b1);
                    check_case(selected_value, 6'(width + 1), selected_size, m64k_shift_operation_t'(operation_index), logic'(selected_extend), 1'b1);
                end
                check_case(selected_value, 6'd63, selected_size, m64k_shift_operation_t'(operation_index), logic'(selected_extend), 1'b1);
            end
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

    initial begin
        source = 64'd0;
        count = 6'd0;
        operand_size = M64K_SHIFT_SIZE_QUAD;
        operation = M64K_SHIFT_LSL;
        extend_in = 1'b0;
        update_flags = 1'b0;

        check_byte_exhaustive();
        check_wide_boundaries();

        $display("M64K shift/rotate RTL verification passed");
        $finish;
    end
endmodule
