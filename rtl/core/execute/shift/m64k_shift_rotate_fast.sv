// Production-candidate combinational datapath for direct scalar shifts and rotates.
//
// PPA assumptions:
// - ASL, ASR, LSL, LSR, ROL, and ROR share one normalized 64-bit, six-stage
//   logarithmic network with 1/2/4/8/16/32-bit stages.
// - Direction reversal and subword replication are wiring transformations. They
//   must be confirmed as such in the synthesized netlist rather than counted as
//   zero-cost by assumption.
// - Carry selection and ASL overflow detection run in parallel with the result
//   network. They are not permitted to add a second result barrel after it.
// - This block is purely combinational and makes no frequency, power, or area
//   claim until synthesized in a sequential execution partition with real SDC,
//   library corners, placement, clocking, and activity data.
// - ROXL and ROXR are deliberately unsupported here. The complete architectural
//   reference remains m64k_shift_rotate; a production ROX implementation awaits
//   a tagged multi-cycle execution or microcode contract.
module m64k_shift_rotate_fast (
    input  logic [63:0] source,
    input  logic [5:0] count,
    input  m64k_shift_rotate_pkg::m64k_shift_size_t operand_size,
    input  m64k_shift_rotate_pkg::m64k_shift_operation_t operation,
    input  logic update_flags,
    output logic operation_supported,
    output logic [63:0] result,
    output logic result_valid,
    output logic negative,
    output logic zero,
    output logic overflow,
    output logic carry,
    output logic flags_valid
);
    import m64k_shift_rotate_pkg::*;

    function automatic logic [63:0] reverse64(input logic [63:0] value);
        logic [63:0] reversed;

        for (int unsigned bit_index = 0; bit_index < 64; bit_index++) begin
            reversed[bit_index] = value[63 - bit_index];
        end

        return reversed;
    endfunction

    function automatic logic stage_changes_asl_sign(
        input logic [63:0] value,
        input m64k_shift_size_t size,
        input logic [2:0] stage_index
    );
        logic changes_sign;

        changes_sign = 1'b0;

        case (stage_index)
            3'd0: begin
                case (size)
                    M64K_SHIFT_SIZE_BYTE: changes_sign = !((&value[7:6]) || (~|value[7:6]));
                    M64K_SHIFT_SIZE_WORD: changes_sign = !((&value[15:14]) || (~|value[15:14]));
                    M64K_SHIFT_SIZE_LONG: changes_sign = !((&value[31:30]) || (~|value[31:30]));
                    M64K_SHIFT_SIZE_QUAD: changes_sign = !((&value[63:62]) || (~|value[63:62]));
                endcase
            end
            3'd1: begin
                case (size)
                    M64K_SHIFT_SIZE_BYTE: changes_sign = !((&value[7:5]) || (~|value[7:5]));
                    M64K_SHIFT_SIZE_WORD: changes_sign = !((&value[15:13]) || (~|value[15:13]));
                    M64K_SHIFT_SIZE_LONG: changes_sign = !((&value[31:29]) || (~|value[31:29]));
                    M64K_SHIFT_SIZE_QUAD: changes_sign = !((&value[63:61]) || (~|value[63:61]));
                endcase
            end
            3'd2: begin
                case (size)
                    M64K_SHIFT_SIZE_BYTE: changes_sign = !((&value[7:3]) || (~|value[7:3]));
                    M64K_SHIFT_SIZE_WORD: changes_sign = !((&value[15:11]) || (~|value[15:11]));
                    M64K_SHIFT_SIZE_LONG: changes_sign = !((&value[31:27]) || (~|value[31:27]));
                    M64K_SHIFT_SIZE_QUAD: changes_sign = !((&value[63:59]) || (~|value[63:59]));
                endcase
            end
            3'd3: begin
                case (size)
                    M64K_SHIFT_SIZE_BYTE: changes_sign = |value[7:0];
                    M64K_SHIFT_SIZE_WORD: changes_sign = !((&value[15:7]) || (~|value[15:7]));
                    M64K_SHIFT_SIZE_LONG: changes_sign = !((&value[31:23]) || (~|value[31:23]));
                    M64K_SHIFT_SIZE_QUAD: changes_sign = !((&value[63:55]) || (~|value[63:55]));
                endcase
            end
            3'd4: begin
                case (size)
                    M64K_SHIFT_SIZE_BYTE: changes_sign = |value[7:0];
                    M64K_SHIFT_SIZE_WORD: changes_sign = |value[15:0];
                    M64K_SHIFT_SIZE_LONG: changes_sign = !((&value[31:15]) || (~|value[31:15]));
                    M64K_SHIFT_SIZE_QUAD: changes_sign = !((&value[63:47]) || (~|value[63:47]));
                endcase
            end
            3'd5: begin
                case (size)
                    M64K_SHIFT_SIZE_BYTE: changes_sign = |value[7:0];
                    M64K_SHIFT_SIZE_WORD: changes_sign = |value[15:0];
                    M64K_SHIFT_SIZE_LONG: changes_sign = |value[31:0];
                    M64K_SHIFT_SIZE_QUAD: changes_sign = !((&value[63:31]) || (~|value[63:31]));
                endcase
            end
            default: changes_sign = 1'b0;
        endcase

        return changes_sign;
    endfunction

    logic [6:0] operand_width;
    logic [5:0] sign_index;
    logic [63:0] operand_mask;
    logic [63:0] operand;
    logic operand_sign;
    logic [63:0] sign_extended_operand;
    logic operation_is_right;
    logic operation_is_shift;
    logic operation_is_rotate;
    logic rotate_mode;
    logic fill;
    logic [5:0] network_count;
    logic [63:0] replicated_operand;
    logic [63:0] network_input;
    logic [63:0] stage_1_shift;
    logic [63:0] stage_1_rotate;
    logic [63:0] stage_1;
    logic [63:0] stage_2_shift;
    logic [63:0] stage_2_rotate;
    logic [63:0] stage_2;
    logic [63:0] stage_4_shift;
    logic [63:0] stage_4_rotate;
    logic [63:0] stage_4;
    logic [63:0] stage_8_shift;
    logic [63:0] stage_8_rotate;
    logic [63:0] stage_8;
    logic [63:0] stage_16_shift;
    logic [63:0] stage_16_rotate;
    logic [63:0] stage_16;
    logic [63:0] stage_32_shift;
    logic [63:0] stage_32_rotate;
    logic [63:0] stage_32;
    logic [63:0] normalized_result;
    logic [63:0] operation_result;
    logic operation_carry;
    logic overflow_after_1;
    logic overflow_after_2;
    logic overflow_after_4;
    logic overflow_after_8;
    logic overflow_after_16;
    logic overflow_after_32;
    logic [5:0] carry_index;

    always_comb begin
        operation_is_right = operation inside {M64K_SHIFT_ASR, M64K_SHIFT_LSR, M64K_SHIFT_ROR};
        operation_is_shift = operation inside {M64K_SHIFT_ASL, M64K_SHIFT_ASR, M64K_SHIFT_LSL, M64K_SHIFT_LSR};
        operation_is_rotate = operation inside {M64K_SHIFT_ROL, M64K_SHIFT_ROR};
        operation_supported = operation_is_shift || operation_is_rotate;
        rotate_mode = operation_is_rotate;

        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: begin
                operand_width = 7'd8;
                sign_index = 6'd7;
                operand_mask = 64'h0000_0000_0000_00ff;
                replicated_operand = {8{source[7:0]}};
                network_count = rotate_mode ? {3'd0, count[2:0]} : count;
            end
            M64K_SHIFT_SIZE_WORD: begin
                operand_width = 7'd16;
                sign_index = 6'd15;
                operand_mask = 64'h0000_0000_0000_ffff;
                replicated_operand = {4{source[15:0]}};
                network_count = rotate_mode ? {2'd0, count[3:0]} : count;
            end
            M64K_SHIFT_SIZE_LONG: begin
                operand_width = 7'd32;
                sign_index = 6'd31;
                operand_mask = 64'h0000_0000_ffff_ffff;
                replicated_operand = {2{source[31:0]}};
                network_count = rotate_mode ? {1'b0, count[4:0]} : count;
            end
            M64K_SHIFT_SIZE_QUAD: begin
                operand_width = 7'd64;
                sign_index = 6'd63;
                operand_mask = 64'hffff_ffff_ffff_ffff;
                replicated_operand = source;
                network_count = count;
            end
        endcase

        operand = source & operand_mask;
        operand_sign = operand[sign_index];
        sign_extended_operand = operand | ({64{operand_sign}} & ~operand_mask);
        fill = operation == M64K_SHIFT_ASR && operand_sign;

        if (rotate_mode) begin
            network_input = operation_is_right ? reverse64(replicated_operand) : replicated_operand;
        end else if (operation_is_right) begin
            network_input = reverse64(operation == M64K_SHIFT_ASR ? sign_extended_operand : operand);
        end else begin
            network_input = operand;
        end

        stage_1_shift = {network_input[62:0], fill};
        stage_1_rotate = {network_input[62:0], network_input[63]};
        stage_1 = network_count[0] ? (rotate_mode ? stage_1_rotate : stage_1_shift) : network_input;

        stage_2_shift = {stage_1[61:0], {2{fill}}};
        stage_2_rotate = {stage_1[61:0], stage_1[63:62]};
        stage_2 = network_count[1] ? (rotate_mode ? stage_2_rotate : stage_2_shift) : stage_1;

        stage_4_shift = {stage_2[59:0], {4{fill}}};
        stage_4_rotate = {stage_2[59:0], stage_2[63:60]};
        stage_4 = network_count[2] ? (rotate_mode ? stage_4_rotate : stage_4_shift) : stage_2;

        stage_8_shift = {stage_4[55:0], {8{fill}}};
        stage_8_rotate = {stage_4[55:0], stage_4[63:56]};
        stage_8 = network_count[3] ? (rotate_mode ? stage_8_rotate : stage_8_shift) : stage_4;

        stage_16_shift = {stage_8[47:0], {16{fill}}};
        stage_16_rotate = {stage_8[47:0], stage_8[63:48]};
        stage_16 = network_count[4] ? (rotate_mode ? stage_16_rotate : stage_16_shift) : stage_8;

        stage_32_shift = {stage_16[31:0], {32{fill}}};
        stage_32_rotate = {stage_16[31:0], stage_16[63:32]};
        stage_32 = network_count[5] ? (rotate_mode ? stage_32_rotate : stage_32_shift) : stage_16;

        normalized_result = operation_is_right ? reverse64(stage_32) : stage_32;
        operation_result = normalized_result & operand_mask;

        operation_carry = 1'b0;
        carry_index = 6'd0;
        if (count != 6'd0) begin
            case (operation)
                M64K_SHIFT_ASL,
                M64K_SHIFT_LSL: begin
                    if ({1'b0, count} <= operand_width) begin
                        carry_index = 6'(operand_width - {1'b0, count});
                        operation_carry = operand[carry_index];
                    end
                end
                M64K_SHIFT_ASR: begin
                    if ({1'b0, count} >= operand_width) begin
                        operation_carry = operand_sign;
                    end else begin
                        operation_carry = operand[count - 6'd1];
                    end
                end
                M64K_SHIFT_LSR: begin
                    if ({1'b0, count} <= operand_width) begin
                        operation_carry = operand[count - 6'd1];
                    end
                end
                M64K_SHIFT_ROL: operation_carry = operation_result[0];
                M64K_SHIFT_ROR: operation_carry = operation_result[sign_index];
                default: operation_carry = 1'b0;
            endcase
        end

        overflow_after_1 = operation == M64K_SHIFT_ASL && network_count[0] && stage_changes_asl_sign(network_input, operand_size, 3'd0);
        overflow_after_2 = overflow_after_1 || (operation == M64K_SHIFT_ASL && network_count[1] && stage_changes_asl_sign(stage_1, operand_size, 3'd1));
        overflow_after_4 = overflow_after_2 || (operation == M64K_SHIFT_ASL && network_count[2] && stage_changes_asl_sign(stage_2, operand_size, 3'd2));
        overflow_after_8 = overflow_after_4 || (operation == M64K_SHIFT_ASL && network_count[3] && stage_changes_asl_sign(stage_4, operand_size, 3'd3));
        overflow_after_16 = overflow_after_8 || (operation == M64K_SHIFT_ASL && network_count[4] && stage_changes_asl_sign(stage_8, operand_size, 3'd4));
        overflow_after_32 = overflow_after_16 || (operation == M64K_SHIFT_ASL && network_count[5] && stage_changes_asl_sign(stage_16, operand_size, 3'd5));

        result = operation_supported ? operation_result : 64'd0;
        result_valid = operation_supported;
        negative = operation_supported ? operation_result[sign_index] : 1'b0;
        zero = operation_supported ? operation_result == 64'd0 : 1'b0;
        overflow = operation_supported ? overflow_after_32 : 1'b0;
        carry = operation_supported ? operation_carry : 1'b0;
        flags_valid = operation_supported && update_flags;
    end
endmodule
