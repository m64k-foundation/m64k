module m64k_integer_alu_tb;
    import m64k_integer_alu_pkg::*;

    logic [63:0] source_left;
    logic [63:0] source_right;
    m64k_integer_size_t operand_size;
    m64k_integer_operation_t operation;
    logic extend_in;
    logic update_flags;
    logic [63:0] result;
    logic result_valid;
    logic negative;
    logic zero;
    logic overflow;
    logic carry_or_borrow;
    logic flags_valid;
    logic extend_out;
    logic extend_valid;

    m64k_integer_alu dut (
        .source_left,
        .source_right,
        .operand_size,
        .operation,
        .extend_in,
        .update_flags,
        .result,
        .result_valid,
        .negative,
        .zero,
        .overflow,
        .carry_or_borrow,
        .flags_valid,
        .extend_out,
        .extend_valid
    );

    function automatic integer signed byte_as_signed(input integer unsigned value);
        if ((value & 32'h0000_0080) != 0) begin
            byte_as_signed = integer'(value) - 256;
        end else begin
            byte_as_signed = integer'(value);
        end
    endfunction

    task automatic fail(input string field_name, input logic [64:0] expected, input logic [64:0] observed);
        $error(
            "%s mismatch: operation=%s left=%016x right=%016x X=%0b expected=%017x observed=%017x",
            field_name,
            operation.name(),
            source_left,
            source_right,
            extend_in,
            expected,
            observed
        );
    endtask

    task automatic check_bit(input string field_name, input logic expected, input logic observed);
        if (observed !== expected) begin
            fail(field_name, 65'(expected), 65'(observed));
        end
    endtask

    task automatic check_value(input logic [63:0] expected);
        if (result !== expected) begin
            fail("result", {1'b0, expected}, {1'b0, result});
        end
    endtask

    task automatic check_byte_nz(input logic [7:0] expected_result);
        check_bit("negative", expected_result[7], negative);
        check_bit("zero", expected_result == 8'd0, zero);
    endtask

    task automatic drive_byte_binary(
        input m64k_integer_operation_t selected_operation,
        input integer unsigned left_operand,
        input integer unsigned right_operand,
        input logic selected_extend
    );
        operation = selected_operation;
        source_left = 64'(left_operand);
        source_right = 64'(right_operand);
        operand_size = M64K_INTEGER_SIZE_BYTE;
        extend_in = selected_extend;
        update_flags = 1'b1;
        #1;
    endtask

    task automatic check_byte_arithmetic_matrix;
        integer unsigned left_operand;
        integer unsigned right_operand;
        integer unsigned extend_value;
        integer unsigned unsigned_result;
        integer unsigned subtrahend;
        logic [31:0] expected_narrow_result;
        integer signed signed_result;
        logic expected_overflow;

        for (left_operand = 0; left_operand < 256; left_operand++) begin
            for (right_operand = 0; right_operand < 256; right_operand++) begin
                drive_byte_binary(M64K_INTEGER_ADD, left_operand, right_operand, 1'b0);
                unsigned_result = left_operand + right_operand;
                signed_result = byte_as_signed(left_operand) + byte_as_signed(right_operand);
                expected_overflow = (signed_result < -128) || (signed_result > 127);
                check_value(64'(unsigned_result & 8'hff));
                check_byte_nz(8'(unsigned_result));
                check_bit("carry", unsigned_result > 255, carry_or_borrow);
                check_bit("overflow", expected_overflow, overflow);
                check_bit("result-valid", 1'b1, result_valid);
                check_bit("flags-valid", 1'b1, flags_valid);
                check_bit("extend-valid", 1'b0, extend_valid);

                drive_byte_binary(M64K_INTEGER_SUB, left_operand, right_operand, 1'b0);
                signed_result = byte_as_signed(left_operand) - byte_as_signed(right_operand);
                expected_overflow = (signed_result < -128) || (signed_result > 127);
                expected_narrow_result = (left_operand - right_operand) & 32'h0000_00ff;
                check_value({32'd0, expected_narrow_result});
                check_byte_nz(expected_narrow_result[7:0]);
                check_bit("borrow", left_operand < right_operand, carry_or_borrow);
                check_bit("overflow", expected_overflow, overflow);
                check_bit("result-valid", 1'b1, result_valid);
                check_bit("flags-valid", 1'b1, flags_valid);
                check_bit("extend-valid", 1'b0, extend_valid);

                drive_byte_binary(M64K_INTEGER_CMP, left_operand, right_operand, 1'b0);
                check_bit("result-valid", 1'b0, result_valid);
                check_bit("flags-valid", 1'b1, flags_valid);
                check_bit("borrow", left_operand < right_operand, carry_or_borrow);
                check_bit("overflow", expected_overflow, overflow);
                check_byte_nz(expected_narrow_result[7:0]);

                drive_byte_binary(M64K_INTEGER_AND, left_operand, right_operand, 1'b0);
                expected_narrow_result = left_operand & right_operand;
                check_value({32'd0, expected_narrow_result});
                check_byte_nz(expected_narrow_result[7:0]);
                check_bit("logical-overflow", 1'b0, overflow);
                check_bit("logical-carry", 1'b0, carry_or_borrow);

                drive_byte_binary(M64K_INTEGER_OR, left_operand, right_operand, 1'b0);
                expected_narrow_result = (left_operand | right_operand) & 32'h0000_00ff;
                check_value({32'd0, expected_narrow_result});
                check_byte_nz(expected_narrow_result[7:0]);
                check_bit("logical-overflow", 1'b0, overflow);
                check_bit("logical-carry", 1'b0, carry_or_borrow);

                drive_byte_binary(M64K_INTEGER_XOR, left_operand, right_operand, 1'b0);
                expected_narrow_result = (left_operand ^ right_operand) & 32'h0000_00ff;
                check_value({32'd0, expected_narrow_result});
                check_byte_nz(expected_narrow_result[7:0]);
                check_bit("logical-overflow", 1'b0, overflow);
                check_bit("logical-carry", 1'b0, carry_or_borrow);

                for (extend_value = 0; extend_value < 2; extend_value++) begin
                    drive_byte_binary(M64K_INTEGER_ADCX, left_operand, right_operand, logic'(extend_value));
                    unsigned_result = left_operand + right_operand + extend_value;
                    signed_result = byte_as_signed(left_operand) + byte_as_signed(right_operand) + integer'(extend_value);
                    expected_overflow = (signed_result < -128) || (signed_result > 127);
                    check_value(64'(unsigned_result & 8'hff));
                    check_byte_nz(8'(unsigned_result));
                    check_bit("carry", unsigned_result > 255, carry_or_borrow);
                    check_bit("extend", unsigned_result > 255, extend_out);
                    check_bit("overflow", expected_overflow, overflow);
                    check_bit("extend-valid", 1'b1, extend_valid);

                    drive_byte_binary(M64K_INTEGER_SBCX, left_operand, right_operand, logic'(extend_value));
                    subtrahend = right_operand + extend_value;
                    signed_result = byte_as_signed(left_operand) - byte_as_signed(right_operand) - integer'(extend_value);
                    expected_overflow = (signed_result < -128) || (signed_result > 127);
                    expected_narrow_result = (left_operand - subtrahend) & 32'h0000_00ff;
                    check_value({32'd0, expected_narrow_result});
                    check_byte_nz(expected_narrow_result[7:0]);
                    check_bit("borrow", left_operand < subtrahend, carry_or_borrow);
                    check_bit("extend", left_operand < subtrahend, extend_out);
                    check_bit("overflow", expected_overflow, overflow);
                    check_bit("extend-valid", 1'b1, extend_valid);
                end
            end
        end
    endtask

    task automatic check_byte_logical_and_unary_matrix;
        integer unsigned value;
        integer unsigned extend_value;
        integer unsigned subtrahend;
        logic [31:0] expected_narrow_result;
        integer signed signed_result;
        logic expected_overflow;

        for (value = 0; value < 256; value++) begin
            drive_byte_binary(M64K_INTEGER_NOT, 0, value, 1'b0);
            expected_narrow_result = (~value) & 32'h0000_00ff;
            check_value({32'd0, expected_narrow_result});
            check_byte_nz(expected_narrow_result[7:0]);
            check_bit("logical-overflow", 1'b0, overflow);
            check_bit("logical-carry", 1'b0, carry_or_borrow);

            drive_byte_binary(M64K_INTEGER_NEG, 0, value, 1'b0);
            expected_narrow_result = (-value) & 32'h0000_00ff;
            check_value({32'd0, expected_narrow_result});
            check_byte_nz(expected_narrow_result[7:0]);
            check_bit("borrow", value != 0, carry_or_borrow);
            check_bit("overflow", value == 32'h0000_0080, overflow);

            drive_byte_binary(M64K_INTEGER_TST, 0, value, 1'b0);
            check_bit("result-valid", 1'b0, result_valid);
            check_bit("negative", (value & 32'h0000_0080) != 0, negative);
            check_bit("zero", value == 0, zero);
            check_bit("logical-overflow", 1'b0, overflow);
            check_bit("logical-carry", 1'b0, carry_or_borrow);

            for (extend_value = 0; extend_value < 2; extend_value++) begin
                drive_byte_binary(M64K_INTEGER_NEGX, 0, value, logic'(extend_value));
                subtrahend = value + extend_value;
                signed_result = -byte_as_signed(value) - integer'(extend_value);
                expected_overflow = (signed_result < -128) || (signed_result > 127);
                expected_narrow_result = (-subtrahend) & 32'h0000_00ff;
                check_value({32'd0, expected_narrow_result});
                check_byte_nz(expected_narrow_result[7:0]);
                check_bit("borrow", subtrahend != 0, carry_or_borrow);
                check_bit("extend", subtrahend != 0, extend_out);
                check_bit("overflow", expected_overflow, overflow);
            end
        end
    endtask

    task automatic check_wide_boundaries;
        operand_size = M64K_INTEGER_SIZE_WORD;
        operation = M64K_INTEGER_ADCX;
        source_left = 64'hffff;
        source_right = 64'd0;
        extend_in = 1'b1;
        update_flags = 1'b1;
        #1;
        check_value(64'd0);
        check_bit("word-carry", 1'b1, carry_or_borrow);

        operand_size = M64K_INTEGER_SIZE_LONG;
        operation = M64K_INTEGER_SBCX;
        source_left = 64'h0000_0000_8000_0000;
        source_right = 64'h0000_0000_7fff_ffff;
        extend_in = 1'b1;
        #1;
        check_value(64'd0);
        check_bit("long-overflow", 1'b1, overflow);

        operand_size = M64K_INTEGER_SIZE_QUAD;
        operation = M64K_INTEGER_ADD;
        source_left = 64'h7fff_ffff_ffff_ffff;
        source_right = 64'd1;
        extend_in = 1'b0;
        #1;
        check_value(64'h8000_0000_0000_0000);
        check_bit("quad-overflow", 1'b1, overflow);
        check_bit("quad-carry", 1'b0, carry_or_borrow);

        source_left = 64'hffff_ffff_ffff_ffff;
        source_right = 64'd1;
        #1;
        check_value(64'd0);
        check_bit("quad-overflow", 1'b0, overflow);
        check_bit("quad-carry", 1'b1, carry_or_borrow);
    endtask

    task automatic check_write_controls;
        drive_byte_binary(M64K_INTEGER_ADD, 32'h0000_00ff, 1, 1'b0);
        update_flags = 1'b0;
        #1;
        check_bit("flags-valid", 1'b0, flags_valid);
        check_bit("extend-valid", 1'b0, extend_valid);

        operation = M64K_INTEGER_ADCX;
        #1;
        check_bit("flags-valid", 1'b0, flags_valid);
        check_bit("extend-valid", 1'b1, extend_valid);
        check_bit("extend", 1'b1, extend_out);
    endtask

    task automatic check_unallocated_operations_are_invalid;
        for (int unsigned operation_index = 12; operation_index < 16; operation_index++) begin
            for (int unsigned policy_index = 0; policy_index < 2; policy_index++) begin
                operation = m64k_integer_operation_t'(operation_index);
                source_left = 64'hffff_ffff_ffff_ffff;
                source_right = 64'h8000_0000_0000_0001;
                extend_in = 1'b1;
                update_flags = policy_index[0];
                #1;

                if (result_valid || flags_valid || extend_valid) begin
                    $fatal(1, "unallocated integer operation exposed a valid architectural output");
                end
                if ((result != 64'd0) || negative || !zero || overflow || carry_or_borrow || extend_out) begin
                    $fatal(1, "unallocated integer operation did not produce benign invalid outputs");
                end
            end
        end
    endtask

    initial begin
        source_left = 64'd0;
        source_right = 64'd0;
        operand_size = M64K_INTEGER_SIZE_QUAD;
        operation = M64K_INTEGER_ADD;
        extend_in = 1'b0;
        update_flags = 1'b0;

        check_byte_arithmetic_matrix();
        check_byte_logical_and_unary_matrix();
        check_wide_boundaries();
        check_write_controls();
        check_unallocated_operations_are_invalid();

        $display("M64K integer ALU RTL verification passed");
        $finish;
    end
endmodule
