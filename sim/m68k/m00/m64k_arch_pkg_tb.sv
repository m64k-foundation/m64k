module m64k_arch_pkg_tb;
    import m64k_arch_pkg::*;

    m64k_alu_result_t alu_value;
    m64k_condition_flags_t condition_flags;
    integer lhs;
    integer rhs;
    integer carry;
    integer arithmetic;
    integer signed_arithmetic;
    integer flag_bits;
    integer condition;
    integer lhs_decimal;
    integer rhs_decimal;
    integer expected_decimal;
    logic [7:0] packed_lhs;
    logic [7:0] packed_rhs;
    logic [7:0] packed_result;
    logic expected_overflow;
    logic expected_condition;

    initial begin
        assert (M64K_SR_M00_DEFINED_MASK == 16'ha71f);
        assert (M64K_SR_M20_DEFINED_MASK == 16'hf71f);
        assert (M64K_SR_CCR_MASK == 16'h001f);
        assert (M64K_SR_TRACE_MASK == 16'hc000);
        assert (M64K_SR_SUPERVISOR_MASK == 16'h3000);
        assert (M64K_SR_INTERRUPT_MASK == 16'h0700);
        assert (M64K_SR_T1 == 15 && M64K_SR_T0 == 14);
        assert (M64K_SR_S == 13 && M64K_SR_M == 12);
        assert (M64K_SR_I2 == 10 && M64K_SR_I1 == 9 && M64K_SR_I0 == 8);
        assert (M64K_SR_X == 4 && M64K_SR_N == 3 && M64K_SR_Z == 2);
        assert (M64K_SR_V == 1 && M64K_SR_C == 0);
        assert (M64K_VECTOR_RESET_SSP == 8'd0);
        assert (M64K_VECTOR_RESET_PC == 8'd1);
        assert (M64K_VECTOR_ACCESS_FAULT == 8'd2);
        assert (M64K_VECTOR_ADDRESS_ERROR == 8'd3);
        assert (M64K_VECTOR_ILLEGAL == 8'd4);
        assert (M64K_VECTOR_ZERO_DIVIDE == 8'd5);
        assert (m64k_m00_function_code(1'b0, 1'b0) == 3'b001);
        assert (m64k_m00_function_code(1'b0, 1'b1) == 3'b010);
        assert (m64k_m00_function_code(1'b1, 1'b0) == 3'b101);
        assert (m64k_m00_function_code(1'b1, 1'b1) == 3'b110);
        assert (m64k_m00_special_status_word(1'b1, 1'b0, 1'b1) ==
                16'h000d);
        assert (m64k_m00_special_status_word(1'b0, 1'b1, 1'b0) ==
                16'h0012);
        assert (M64K_VECTOR_CHK == 8'd6);
        assert (M64K_VECTOR_TRAPCC == 8'd7);
        assert (M64K_VECTOR_PRIVILEGE == 8'd8);
        assert (M64K_VECTOR_TRACE == 8'd9);
        assert (M64K_VECTOR_LINE_A == 8'd10);
        assert (M64K_VECTOR_LINE_F == 8'd11);
        assert (M64K_VECTOR_COPROTOCOL == 8'd13);
        assert (M64K_VECTOR_FORMAT_ERROR == 8'd14);
        assert (M64K_VECTOR_UNINITIALIZED_IRQ == 8'd15);
        assert (M64K_VECTOR_SPURIOUS == 8'd24);
        assert (M64K_VECTOR_TRAP_BASE == 8'd32);
        assert (M64K_VECTOR_FP_BASE == 8'd48);
        assert (M64K_VECTOR_MMU_CONFIG == 8'd56);
        assert (m64k_sr_sanitize(16'hffff, M64K_PROFILE_M00) == 16'ha71f);
        assert (m64k_sr_sanitize(16'hffff, M64K_PROFILE_M10) == 16'ha71f);
        assert (m64k_sr_sanitize(16'hffff, M64K_PROFILE_M20) == 16'hf71f);
        assert (m64k_sr_sanitize(16'hffff, M64K_PROFILE_M40) == 16'hf71f);
        assert (M64K_VECTOR_AUTOVECTOR_BASE + 8'd7 == 8'd31);

        assert (!m64k_interrupt_accepted(3'd0, 3'd0, 1'b0));
        assert (!m64k_interrupt_accepted(3'd4, 3'd4, 1'b0));
        assert (m64k_interrupt_accepted(3'd5, 3'd4, 1'b0));
        assert (m64k_interrupt_accepted(3'd7, 3'd7, 1'b1));

        // Exhaustive byte ADD/ADDX/SUB/SUBX flag verification: 262144 ops.
        for (lhs = 0; lhs < 256; lhs = lhs + 1) begin
            for (rhs = 0; rhs < 256; rhs = rhs + 1) begin
                for (carry = 0; carry < 2; carry = carry + 1) begin
                    alu_value = m64k_add(lhs, rhs, M64K_OP_BYTE, carry[0], 1'b1);
                    arithmetic = lhs + rhs + carry;
                    signed_arithmetic = (lhs < 128 ? lhs : lhs - 256) +
                                        (rhs < 128 ? rhs : rhs - 256) + carry;
                    expected_overflow = (signed_arithmetic > 127) ||
                                        (signed_arithmetic < -128);
                    assert (alu_value.result[7:0] == arithmetic[7:0]);
                    assert (alu_value.flags.c == (arithmetic > 255));
                    assert (alu_value.flags.x == alu_value.flags.c);
                    assert (alu_value.flags.n == alu_value.result[7]);
                    assert (alu_value.flags.z == (arithmetic[7:0] == 0));
                    assert (alu_value.flags.v == expected_overflow);

                    alu_value = m64k_subtract(lhs, rhs, M64K_OP_BYTE, carry[0], 1'b1);
                    arithmetic = (lhs - rhs - carry) & 255;
                    signed_arithmetic = (lhs < 128 ? lhs : lhs - 256) -
                                        (rhs < 128 ? rhs : rhs - 256) - carry;
                    expected_overflow = (signed_arithmetic > 127) ||
                                        (signed_arithmetic < -128);
                    assert (alu_value.result[7:0] == arithmetic[7:0]);
                    assert (alu_value.flags.c == (lhs < (rhs + carry)));
                    assert (alu_value.flags.x == alu_value.flags.c);
                    assert (alu_value.flags.n == alu_value.result[7]);
                    assert (alu_value.flags.z == (arithmetic == 0));
                    assert (alu_value.flags.v == expected_overflow);
                end
            end
        end

        // ADDX/SUBX preserve a cleared cumulative Z across a zero result.
        alu_value = m64k_add(32'd0, 32'd0, M64K_OP_LONG, 1'b0, 1'b0);
        assert (!alu_value.flags.z);
        alu_value = m64k_subtract(32'd0, 32'd0, M64K_OP_LONG, 1'b0, 1'b0);
        assert (!alu_value.flags.z);

        // PRM 4-1 and 4-169: exhaust every valid packed-BCD byte pair and
        // both X inputs. N/V are undefined and intentionally not asserted.
        for (lhs_decimal = 0; lhs_decimal < 100;
             lhs_decimal = lhs_decimal + 1) begin
            packed_lhs = 8'(((lhs_decimal / 10) << 4) |
                            (lhs_decimal % 10));
            for (rhs_decimal = 0; rhs_decimal < 100;
                 rhs_decimal = rhs_decimal + 1) begin
                packed_rhs = 8'(((rhs_decimal / 10) << 4) |
                                (rhs_decimal % 10));
                for (carry = 0; carry < 2; carry = carry + 1) begin
                    expected_decimal = lhs_decimal + rhs_decimal + carry;
                    alu_value = m64k_add_decimal_byte(
                        packed_lhs[7:0], packed_rhs[7:0], carry[0], 1'b1);
                    assert (alu_value.flags.c == (expected_decimal >= 100));
                    if (expected_decimal >= 100)
                        expected_decimal = expected_decimal - 100;
                    packed_result = 8'(((expected_decimal / 10) << 4) |
                                       (expected_decimal % 10));
                    assert (alu_value.result[7:0] == packed_result[7:0]);
                    assert (alu_value.flags.x == alu_value.flags.c);
                    assert (alu_value.flags.z == (expected_decimal == 0));

                    expected_decimal = lhs_decimal - rhs_decimal - carry;
                    alu_value = m64k_subtract_decimal_byte(
                        packed_lhs[7:0], packed_rhs[7:0], carry[0], 1'b1);
                    assert (alu_value.flags.c == (expected_decimal < 0));
                    if (expected_decimal < 0)
                        expected_decimal = expected_decimal + 100;
                    packed_result = 8'(((expected_decimal / 10) << 4) |
                                       (expected_decimal % 10));
                    assert (alu_value.result[7:0] == packed_result[7:0]);
                    assert (alu_value.flags.x == alu_value.flags.c);
                    assert (alu_value.flags.z == (expected_decimal == 0));
                end
            end
        end

        alu_value = m64k_add_decimal_byte(8'h00, 8'h00, 1'b0, 1'b0);
        assert (!alu_value.flags.z);
        alu_value = m64k_subtract_decimal_byte(8'h00, 8'h00, 1'b0, 1'b0);
        assert (!alu_value.flags.z);

        // M68000PRM table 3-19: all 16 integer conditions over every NZVC
        // combination.  X is deliberately absent from conditional testing.
        for (flag_bits = 0; flag_bits < 16; flag_bits = flag_bits + 1) begin
            condition_flags = '{n: flag_bits[3], z: flag_bits[2],
                                v: flag_bits[1], c: flag_bits[0]};
            for (condition = 0; condition < 16;
                 condition = condition + 1) begin
                case (condition[3:0])
                    4'h0: expected_condition = 1'b1;
                    4'h1: expected_condition = 1'b0;
                    4'h2: expected_condition = !condition_flags.c &&
                                                       !condition_flags.z;
                    4'h3: expected_condition = condition_flags.c ||
                                                        condition_flags.z;
                    4'h4: expected_condition = !condition_flags.c;
                    4'h5: expected_condition = condition_flags.c;
                    4'h6: expected_condition = !condition_flags.z;
                    4'h7: expected_condition = condition_flags.z;
                    4'h8: expected_condition = !condition_flags.v;
                    4'h9: expected_condition = condition_flags.v;
                    4'ha: expected_condition = !condition_flags.n;
                    4'hb: expected_condition = condition_flags.n;
                    4'hc: expected_condition = condition_flags.n ==
                                                        condition_flags.v;
                    4'hd: expected_condition = condition_flags.n !=
                                                        condition_flags.v;
                    4'he: expected_condition = !condition_flags.z &&
                                           (condition_flags.n ==
                                            condition_flags.v);
                    default: expected_condition = condition_flags.z ||
                                           (condition_flags.n !=
                                            condition_flags.v);
                endcase
                assert (m64k_condition_true(condition[3:0], condition_flags) ==
                        expected_condition);
            end
        end

        $display("PASS: M64K SR/vectors, conditions, binary and packed-BCD ALU");
        $finish;
    end
endmodule
