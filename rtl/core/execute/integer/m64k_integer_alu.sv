module m64k_integer_alu (
    input  logic [63:0] source_left,
    input  logic [63:0] source_right,
    input  m64k_integer_alu_pkg::m64k_integer_size_t operand_size,
    input  m64k_integer_alu_pkg::m64k_integer_operation_t operation,
    input  logic extend_in,
    input  logic update_flags,
    output logic [63:0] result,
    output logic result_valid,
    output logic negative,
    output logic zero,
    output logic overflow,
    output logic carry_or_borrow,
    output logic flags_valid,
    output logic extend_out,
    output logic extend_valid
);
    import m64k_integer_alu_pkg::*;

    logic [63:0] operand_mask;
    logic [63:0] left_value;
    logic [63:0] right_value;
    logic [63:0] arithmetic_result;
    logic [63:0] adder_left;
    logic [63:0] adder_right;
    logic adder_carry_in;
    logic adder_carry_out;
    logic use_adder;
    logic subtraction_operation;
    logic [64:0] extended_result;
    logic left_sign;
    logic right_sign;
    logic result_sign;
    logic arithmetic_carry_or_borrow;
    logic arithmetic_overflow;
    logic operation_always_writes_flags;
    logic operation_is_legal;

    always_comb begin
        case (operand_size)
            M64K_INTEGER_SIZE_BYTE: operand_mask = 64'h0000_0000_0000_00ff;
            M64K_INTEGER_SIZE_WORD: operand_mask = 64'h0000_0000_0000_ffff;
            M64K_INTEGER_SIZE_LONG: operand_mask = 64'h0000_0000_ffff_ffff;
            M64K_INTEGER_SIZE_QUAD: operand_mask = 64'hffff_ffff_ffff_ffff;
            default: operand_mask = 64'hffff_ffff_ffff_ffff;
        endcase

        left_value = source_left & operand_mask;
        right_value = source_right & operand_mask;
        adder_left = left_value;
        adder_right = right_value;
        adder_carry_in = 1'b0;
        use_adder = 1'b1;
        subtraction_operation = 1'b0;

        case (operation)
            M64K_INTEGER_ADD: begin
                adder_carry_in = 1'b0;
            end
            M64K_INTEGER_ADCX: begin
                adder_carry_in = extend_in;
            end
            M64K_INTEGER_SUB,
            M64K_INTEGER_CMP,
            M64K_INTEGER_NEG: begin
                adder_right = (~right_value) & operand_mask;
                adder_carry_in = 1'b1;
                subtraction_operation = 1'b1;
            end
            M64K_INTEGER_SBCX,
            M64K_INTEGER_NEGX: begin
                adder_right = (~right_value) & operand_mask;
                adder_carry_in = ~extend_in;
                subtraction_operation = 1'b1;
            end
            default: begin
                use_adder = 1'b0;
            end
        endcase

        if ((operation == M64K_INTEGER_NEG) || (operation == M64K_INTEGER_NEGX)) begin
            adder_left = 64'd0;
        end

        extended_result = {1'b0, adder_left} + {1'b0, adder_right} + 65'(adder_carry_in);

        case (operand_size)
            M64K_INTEGER_SIZE_BYTE: adder_carry_out = extended_result[8];
            M64K_INTEGER_SIZE_WORD: adder_carry_out = extended_result[16];
            M64K_INTEGER_SIZE_LONG: adder_carry_out = extended_result[32];
            M64K_INTEGER_SIZE_QUAD: adder_carry_out = extended_result[64];
            default: adder_carry_out = extended_result[64];
        endcase

        arithmetic_result = 64'd0;
        arithmetic_carry_or_borrow = 1'b0;

        if (use_adder) begin
            arithmetic_result = extended_result[63:0] & operand_mask;
            arithmetic_carry_or_borrow = subtraction_operation ? ~adder_carry_out : adder_carry_out;
        end else begin
            case (operation)
                M64K_INTEGER_AND: arithmetic_result = left_value & right_value;
                M64K_INTEGER_OR: arithmetic_result = left_value | right_value;
                M64K_INTEGER_XOR: arithmetic_result = left_value ^ right_value;
                M64K_INTEGER_NOT: arithmetic_result = (~right_value) & operand_mask;
                M64K_INTEGER_TST: arithmetic_result = right_value;
                default: arithmetic_result = 64'd0;
            endcase
        end

        case (operand_size)
            M64K_INTEGER_SIZE_BYTE: begin
                left_sign = left_value[7];
                right_sign = right_value[7];
                result_sign = arithmetic_result[7];
            end
            M64K_INTEGER_SIZE_WORD: begin
                left_sign = left_value[15];
                right_sign = right_value[15];
                result_sign = arithmetic_result[15];
            end
            M64K_INTEGER_SIZE_LONG: begin
                left_sign = left_value[31];
                right_sign = right_value[31];
                result_sign = arithmetic_result[31];
            end
            M64K_INTEGER_SIZE_QUAD: begin
                left_sign = left_value[63];
                right_sign = right_value[63];
                result_sign = arithmetic_result[63];
            end
            default: begin
                left_sign = left_value[63];
                right_sign = right_value[63];
                result_sign = arithmetic_result[63];
            end
        endcase

        case (operation)
            M64K_INTEGER_ADD,
            M64K_INTEGER_ADCX: arithmetic_overflow = (left_sign == right_sign) && (result_sign != left_sign);
            M64K_INTEGER_SUB,
            M64K_INTEGER_SBCX,
            M64K_INTEGER_CMP: arithmetic_overflow = (left_sign != right_sign) && (result_sign != left_sign);
            M64K_INTEGER_NEG,
            M64K_INTEGER_NEGX: arithmetic_overflow = right_sign && result_sign;
            default: arithmetic_overflow = 1'b0;
        endcase

        operation_is_legal = m64k_integer_operation_is_legal(operation);
        operation_always_writes_flags = (operation == M64K_INTEGER_CMP) || (operation == M64K_INTEGER_TST);
        result_valid = operation_is_legal && !operation_always_writes_flags;
        flags_valid = operation_is_legal && (update_flags || operation_always_writes_flags);
        extend_valid = (operation == M64K_INTEGER_ADCX) || (operation == M64K_INTEGER_SBCX) || (operation == M64K_INTEGER_NEGX);

        result = arithmetic_result;
        negative = result_sign;
        zero = arithmetic_result == 64'd0;
        overflow = arithmetic_overflow;
        carry_or_borrow = arithmetic_carry_or_borrow;
        extend_out = arithmetic_carry_or_borrow;
    end
endmodule
