module m64k_shift_rotate (
    input  logic [63:0] source,
    input  logic [5:0] count,
    input  m64k_shift_rotate_pkg::m64k_shift_size_t operand_size,
    input  m64k_shift_rotate_pkg::m64k_shift_operation_t operation,
    input  logic extend_in,
    input  logic update_flags,
    output logic [63:0] result,
    output logic result_valid,
    output logic negative,
    output logic zero,
    output logic overflow,
    output logic carry,
    output logic flags_valid,
    output logic extend_out,
    output logic extend_valid
);
    import m64k_shift_rotate_pkg::*;

    function automatic logic [63:0] reverse64(input logic [63:0] value);
        logic [63:0] reversed;

        for (int unsigned bit_index = 0; bit_index < 64; bit_index++) begin
            reversed[bit_index] = value[63 - bit_index];
        end

        return reversed;
    endfunction

    function automatic logic [8:0] reverse9(input logic [8:0] value);
        logic [8:0] reversed;

        for (int unsigned bit_index = 0; bit_index < 9; bit_index++) begin
            reversed[bit_index] = value[8 - bit_index];
        end

        return reversed;
    endfunction

    function automatic logic [16:0] reverse17(input logic [16:0] value);
        logic [16:0] reversed;

        for (int unsigned bit_index = 0; bit_index < 17; bit_index++) begin
            reversed[bit_index] = value[16 - bit_index];
        end

        return reversed;
    endfunction

    function automatic logic [32:0] reverse33(input logic [32:0] value);
        logic [32:0] reversed;

        for (int unsigned bit_index = 0; bit_index < 33; bit_index++) begin
            reversed[bit_index] = value[32 - bit_index];
        end

        return reversed;
    endfunction

    function automatic logic [64:0] reverse65(input logic [64:0] value);
        logic [64:0] reversed;

        for (int unsigned bit_index = 0; bit_index < 65; bit_index++) begin
            reversed[bit_index] = value[64 - bit_index];
        end

        return reversed;
    endfunction

    function automatic logic [63:0] barrel_shift_left64(
        input logic [63:0] value,
        input logic [63:0] width_mask,
        input logic [5:0] shift_count
    );
        logic [63:0] stage_1;
        logic [63:0] stage_2;
        logic [63:0] stage_4;
        logic [63:0] stage_8;
        logic [63:0] stage_16;
        logic [63:0] stage_32;

        stage_1  = shift_count[0] ? (value << 1) & width_mask : value;
        stage_2  = shift_count[1] ? (stage_1 << 2) & width_mask : stage_1;
        stage_4  = shift_count[2] ? (stage_2 << 4) & width_mask : stage_2;
        stage_8  = shift_count[3] ? (stage_4 << 8) & width_mask : stage_4;
        stage_16 = shift_count[4] ? (stage_8 << 16) & width_mask : stage_8;
        stage_32 = shift_count[5] ? (stage_16 << 32) & width_mask : stage_16;

        return stage_32;
    endfunction

    function automatic logic [63:0] barrel_shift_right64(
        input logic [63:0] value,
        input logic fill,
        input logic [5:0] shift_count
    );
        logic [63:0] stage_1;
        logic [63:0] stage_2;
        logic [63:0] stage_4;
        logic [63:0] stage_8;
        logic [63:0] stage_16;
        logic [63:0] stage_32;

        stage_1  = shift_count[0] ? {fill, value[63:1]} : value;
        stage_2  = shift_count[1] ? {{2{fill}}, stage_1[63:2]} : stage_1;
        stage_4  = shift_count[2] ? {{4{fill}}, stage_2[63:4]} : stage_2;
        stage_8  = shift_count[3] ? {{8{fill}}, stage_4[63:8]} : stage_4;
        stage_16 = shift_count[4] ? {{16{fill}}, stage_8[63:16]} : stage_8;
        stage_32 = shift_count[5] ? {{32{fill}}, stage_16[63:32]} : stage_16;

        return stage_32;
    endfunction

    function automatic logic [63:0] barrel_rotate_left64(
        input logic [63:0] value,
        input logic [5:0] rotate_count
    );
        logic [63:0] stage_1;
        logic [63:0] stage_2;
        logic [63:0] stage_4;
        logic [63:0] stage_8;
        logic [63:0] stage_16;
        logic [63:0] stage_32;

        stage_1  = rotate_count[0] ? {value[62:0], value[63]} : value;
        stage_2  = rotate_count[1] ? {stage_1[61:0], stage_1[63:62]} : stage_1;
        stage_4  = rotate_count[2] ? {stage_2[59:0], stage_2[63:60]} : stage_2;
        stage_8  = rotate_count[3] ? {stage_4[55:0], stage_4[63:56]} : stage_4;
        stage_16 = rotate_count[4] ? {stage_8[47:0], stage_8[63:48]} : stage_8;
        stage_32 = rotate_count[5] ? {stage_16[31:0], stage_16[63:32]} : stage_16;

        return stage_32;
    endfunction

    function automatic logic [8:0] barrel_rotate_left9(input logic [8:0] value, input logic [3:0] rotate_count);
        logic [8:0] stage_1;
        logic [8:0] stage_2;
        logic [8:0] stage_4;
        logic [8:0] stage_8;

        stage_1 = rotate_count[0] ? {value[7:0], value[8]} : value;
        stage_2 = rotate_count[1] ? {stage_1[6:0], stage_1[8:7]} : stage_1;
        stage_4 = rotate_count[2] ? {stage_2[4:0], stage_2[8:5]} : stage_2;
        stage_8 = rotate_count[3] ? {stage_4[0], stage_4[8:1]} : stage_4;

        return stage_8;
    endfunction

    function automatic logic [16:0] barrel_rotate_left17(input logic [16:0] value, input logic [4:0] rotate_count);
        logic [16:0] stage_1;
        logic [16:0] stage_2;
        logic [16:0] stage_4;
        logic [16:0] stage_8;
        logic [16:0] stage_16;

        stage_1  = rotate_count[0] ? {value[15:0], value[16]} : value;
        stage_2  = rotate_count[1] ? {stage_1[14:0], stage_1[16:15]} : stage_1;
        stage_4  = rotate_count[2] ? {stage_2[12:0], stage_2[16:13]} : stage_2;
        stage_8  = rotate_count[3] ? {stage_4[8:0], stage_4[16:9]} : stage_4;
        stage_16 = rotate_count[4] ? {stage_8[0], stage_8[16:1]} : stage_8;

        return stage_16;
    endfunction

    function automatic logic [32:0] barrel_rotate_left33(input logic [32:0] value, input logic [5:0] rotate_count);
        logic [32:0] stage_1;
        logic [32:0] stage_2;
        logic [32:0] stage_4;
        logic [32:0] stage_8;
        logic [32:0] stage_16;
        logic [32:0] stage_32;

        stage_1  = rotate_count[0] ? {value[31:0], value[32]} : value;
        stage_2  = rotate_count[1] ? {stage_1[30:0], stage_1[32:31]} : stage_1;
        stage_4  = rotate_count[2] ? {stage_2[28:0], stage_2[32:29]} : stage_2;
        stage_8  = rotate_count[3] ? {stage_4[24:0], stage_4[32:25]} : stage_4;
        stage_16 = rotate_count[4] ? {stage_8[16:0], stage_8[32:17]} : stage_8;
        stage_32 = rotate_count[5] ? {stage_16[0], stage_16[32:1]} : stage_16;

        return stage_32;
    endfunction

    function automatic logic [64:0] barrel_rotate_left65(input logic [64:0] value, input logic [5:0] rotate_count);
        logic [64:0] stage_1;
        logic [64:0] stage_2;
        logic [64:0] stage_4;
        logic [64:0] stage_8;
        logic [64:0] stage_16;
        logic [64:0] stage_32;

        stage_1  = rotate_count[0] ? {value[63:0], value[64]} : value;
        stage_2  = rotate_count[1] ? {stage_1[62:0], stage_1[64:63]} : stage_1;
        stage_4  = rotate_count[2] ? {stage_2[60:0], stage_2[64:61]} : stage_2;
        stage_8  = rotate_count[3] ? {stage_4[56:0], stage_4[64:57]} : stage_4;
        stage_16 = rotate_count[4] ? {stage_8[48:0], stage_8[64:49]} : stage_8;
        stage_32 = rotate_count[5] ? {stage_16[32:0], stage_16[64:33]} : stage_16;

        return stage_32;
    endfunction

    function automatic logic [3:0] reduce_modulo9(input logic [5:0] value);
        logic [5:0] reduced;

        reduced = value;
        if (reduced >= 6'd36) begin
            reduced = reduced - 6'd36;
        end
        if (reduced >= 6'd18) begin
            reduced = reduced - 6'd18;
        end
        if (reduced >= 6'd9) begin
            reduced = reduced - 6'd9;
        end

        return reduced[3:0];
    endfunction

    function automatic logic [4:0] reduce_modulo17(input logic [5:0] value);
        logic [5:0] reduced;

        reduced = value;
        if (reduced >= 6'd34) begin
            reduced = reduced - 6'd34;
        end
        if (reduced >= 6'd17) begin
            reduced = reduced - 6'd17;
        end

        return reduced[4:0];
    endfunction

    function automatic logic [5:0] reduce_modulo33(input logic [5:0] value);
        if (value >= 6'd33) begin
            return value - 6'd33;
        end

        return value;
    endfunction

    function automatic logic asl_overflow(
        input logic [63:0] value,
        input m64k_shift_size_t size,
        input logic [5:0] shift_count
    );
        logic [6:0] width;
        logic [63:0] width_mask;
        logic sign;
        logic [63:0] sign_difference;
        logic [63:0] relevant_mask;
        logic [63:0] shifted_width_mask;
        logic [6:0] mask_shift;
        logic overflow_result;

        case (size)
            M64K_SHIFT_SIZE_BYTE: begin
                width = 7'd8;
                width_mask = 64'h0000_0000_0000_00ff;
                sign = value[7];
            end
            M64K_SHIFT_SIZE_WORD: begin
                width = 7'd16;
                width_mask = 64'h0000_0000_0000_ffff;
                sign = value[15];
            end
            M64K_SHIFT_SIZE_LONG: begin
                width = 7'd32;
                width_mask = 64'h0000_0000_ffff_ffff;
                sign = value[31];
            end
            M64K_SHIFT_SIZE_QUAD: begin
                width = 7'd64;
                width_mask = 64'hffff_ffff_ffff_ffff;
                sign = value[63];
            end
        endcase

        sign_difference = value ^ {64{sign}};
        mask_shift = {1'b0, shift_count} + 7'd1;
        if (mask_shift[6]) begin
            shifted_width_mask = 64'd0;
        end else begin
            shifted_width_mask = barrel_shift_right64(width_mask, 1'b0, mask_shift[5:0]);
        end
        relevant_mask = width_mask & ~shifted_width_mask;
        overflow_result = 1'b0;

        if (shift_count != 6'd0) begin
            if ({1'b0, shift_count} >= width) begin
                overflow_result = (value & width_mask) != 64'd0;
            end else begin
                overflow_result = |(sign_difference & relevant_mask);
            end
        end

        return overflow_result;
    endfunction

    logic [5:0] architectural_count;
    logic [6:0] operand_width;
    logic [5:0] sign_index;
    logic [63:0] operand_mask;
    logic [63:0] operand;
    logic operand_sign;
    logic [63:0] sign_extended_operand;
    logic operation_is_right;
    logic operation_is_shift;
    logic operation_is_rotate;
    logic operation_is_rotate_extend;
    logic [63:0] shift_input;
    logic [63:0] shifted_value;
    logic [5:0] rotate_count;
    logic [63:0] replicated_operand;
    logic [63:0] rotate_input;
    logic [63:0] rotated_value;
    logic [8:0] ring9_input;
    logic [16:0] ring17_input;
    logic [32:0] ring33_input;
    logic [64:0] ring65_input;
    logic [8:0] ring9_output;
    logic [16:0] ring17_output;
    logic [32:0] ring33_output;
    logic [64:0] ring65_output;
    logic [63:0] operation_result;
    logic operation_carry;
    logic operation_overflow;
    logic resulting_extend;
    logic [5:0] carry_index;

    always_comb begin
        architectural_count = count;
        operation_is_right = operation inside {M64K_SHIFT_ASR, M64K_SHIFT_LSR, M64K_SHIFT_ROR, M64K_SHIFT_ROXR};
        operation_is_shift = operation inside {M64K_SHIFT_ASL, M64K_SHIFT_ASR, M64K_SHIFT_LSL, M64K_SHIFT_LSR};
        operation_is_rotate = operation inside {M64K_SHIFT_ROL, M64K_SHIFT_ROR};
        operation_is_rotate_extend = operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR};

        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: begin
                operand_width = 7'd8;
                sign_index = 6'd7;
                operand_mask = 64'h0000_0000_0000_00ff;
                rotate_count = {3'd0, architectural_count[2:0]};
                replicated_operand = {8{source[7:0]}};
            end
            M64K_SHIFT_SIZE_WORD: begin
                operand_width = 7'd16;
                sign_index = 6'd15;
                operand_mask = 64'h0000_0000_0000_ffff;
                rotate_count = {2'd0, architectural_count[3:0]};
                replicated_operand = {4{source[15:0]}};
            end
            M64K_SHIFT_SIZE_LONG: begin
                operand_width = 7'd32;
                sign_index = 6'd31;
                operand_mask = 64'h0000_0000_ffff_ffff;
                rotate_count = {1'b0, architectural_count[4:0]};
                replicated_operand = {2{source[31:0]}};
            end
            M64K_SHIFT_SIZE_QUAD: begin
                operand_width = 7'd64;
                sign_index = 6'd63;
                operand_mask = 64'hffff_ffff_ffff_ffff;
                rotate_count = architectural_count;
                replicated_operand = source;
            end
        endcase

        operand = source & operand_mask;
        operand_sign = operand[sign_index];
        sign_extended_operand = operand | ({64{operand_sign}} & ~operand_mask);

        shift_input = operation == M64K_SHIFT_ASR ? sign_extended_operand : operand;
        if (operation_is_right) begin
            shifted_value = barrel_shift_right64(shift_input, operation == M64K_SHIFT_ASR && operand_sign, architectural_count) & operand_mask;
        end else begin
            shifted_value = barrel_shift_left64(shift_input, operand_mask, architectural_count);
        end

        rotate_input = operation_is_right ? reverse64(replicated_operand) : replicated_operand;
        rotated_value = barrel_rotate_left64(rotate_input, rotate_count);
        if (operation_is_right) begin
            rotated_value = reverse64(rotated_value);
        end
        rotated_value &= operand_mask;

        ring9_input = operation == M64K_SHIFT_ROXR ? reverse9({operand[7:0], extend_in}) : {operand[7:0], extend_in};
        ring17_input = operation == M64K_SHIFT_ROXR ? reverse17({operand[15:0], extend_in}) : {operand[15:0], extend_in};
        ring33_input = operation == M64K_SHIFT_ROXR ? reverse33({operand[31:0], extend_in}) : {operand[31:0], extend_in};
        ring65_input = operation == M64K_SHIFT_ROXR ? reverse65({operand, extend_in}) : {operand, extend_in};

        ring9_output = barrel_rotate_left9(ring9_input, reduce_modulo9(architectural_count));
        ring17_output = barrel_rotate_left17(ring17_input, reduce_modulo17(architectural_count));
        ring33_output = barrel_rotate_left33(ring33_input, reduce_modulo33(architectural_count));
        ring65_output = barrel_rotate_left65(ring65_input, architectural_count);

        if (operation == M64K_SHIFT_ROXR) begin
            ring9_output = reverse9(ring9_output);
            ring17_output = reverse17(ring17_output);
            ring33_output = reverse33(ring33_output);
            ring65_output = reverse65(ring65_output);
        end

        operation_result = 64'd0;
        resulting_extend = extend_in;

        if (operation_is_shift) begin
            operation_result = shifted_value;
        end else if (operation_is_rotate) begin
            operation_result = rotated_value;
        end else if (operation_is_rotate_extend) begin
            case (operand_size)
                M64K_SHIFT_SIZE_BYTE: begin
                    operation_result = {56'd0, ring9_output[8:1]};
                    resulting_extend = ring9_output[0];
                end
                M64K_SHIFT_SIZE_WORD: begin
                    operation_result = {48'd0, ring17_output[16:1]};
                    resulting_extend = ring17_output[0];
                end
                M64K_SHIFT_SIZE_LONG: begin
                    operation_result = {32'd0, ring33_output[32:1]};
                    resulting_extend = ring33_output[0];
                end
                M64K_SHIFT_SIZE_QUAD: begin
                    operation_result = ring65_output[64:1];
                    resulting_extend = ring65_output[0];
                end
            endcase
        end

        operation_carry = 1'b0;
        carry_index = 6'd0;
        if (operation_is_rotate_extend) begin
            operation_carry = resulting_extend;
        end else if (architectural_count != 6'd0) begin
            case (operation)
                M64K_SHIFT_ASL,
                M64K_SHIFT_LSL: begin
                    if ({1'b0, architectural_count} <= operand_width) begin
                        carry_index = 6'(operand_width - {1'b0, architectural_count});
                        operation_carry = operand[carry_index];
                    end
                end
                M64K_SHIFT_ASR: begin
                    if ({1'b0, architectural_count} >= operand_width) begin
                        operation_carry = operand_sign;
                    end else begin
                        operation_carry = operand[architectural_count - 6'd1];
                    end
                end
                M64K_SHIFT_LSR: begin
                    if ({1'b0, architectural_count} <= operand_width) begin
                        operation_carry = operand[architectural_count - 6'd1];
                    end
                end
                M64K_SHIFT_ROL: operation_carry = operation_result[0];
                M64K_SHIFT_ROR: operation_carry = operation_result[sign_index];
                default: operation_carry = 1'b0;
            endcase
        end

        operation_overflow = (operation == M64K_SHIFT_ASL) && asl_overflow(operand, operand_size, architectural_count);

        result = operation_result;
        result_valid = 1'b1;
        negative = operation_result[sign_index];
        zero = operation_result == 64'd0;
        overflow = operation_overflow;
        carry = operation_carry;
        flags_valid = update_flags;
        extend_out = resulting_extend;
        extend_valid = operation_is_rotate_extend;
    end
endmodule
