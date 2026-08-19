module m64k_shifter (
    input  logic [31:0] operand,
    input  m64k_arch_pkg::m64k_operand_size_t size,
    input  logic [5:0] count,
    input  logic direction_left,
    // 00 AS, 01 LS, 10 ROX, 11 RO.  This is the encoding carried by the
    // M00 uop condition field, not an externally visible ISA encoding.
    input  logic [1:0] shift_kind,
    input  logic old_extend,
    output m64k_arch_pkg::m64k_alu_result_t shift_result
);
    import m64k_arch_pkg::*;

    logic [31:0] width_mask;
    logic [31:0] sign_mask;
    logic [31:0] working;
    logic [31:0] result_value;
    logic [32:0] rotate_ring;
    logic [32:0] rotated_ring;
    logic [32:0] ring_mask;
    logic signed [63:0] signed_operand;
    logic signed [63:0] signed_shifted;
    logic signed [63:0] signed_result;
    integer unsigned width;
    integer unsigned ring_width;
    integer unsigned effective_count;
    integer unsigned count_value;
    logic carry_value;
    logic extend_value;
    logic overflow_value;

    always_comb begin
        case (size)
            M64K_OP_BYTE: begin
                width = 8;
                width_mask = 32'h0000_00ff;
                sign_mask = 32'h0000_0080;
                signed_operand = {{56{operand[7]}}, operand[7:0]};
            end
            M64K_OP_WORD: begin
                width = 16;
                width_mask = 32'h0000_ffff;
                sign_mask = 32'h0000_8000;
                signed_operand = {{48{operand[15]}}, operand[15:0]};
            end
            default: begin
                width = 32;
                width_mask = 32'hffff_ffff;
                sign_mask = 32'h8000_0000;
                signed_operand = {{32{operand[31]}}, operand};
            end
        endcase

        working = operand & width_mask;
        result_value = working;
        carry_value = 1'b0;
        extend_value = old_extend;
        overflow_value = 1'b0;
        rotate_ring = 33'd0;
        rotated_ring = 33'd0;
        case (size)
            M64K_OP_BYTE: ring_mask = 33'h0000_01ff;
            M64K_OP_WORD: ring_mask = 33'h0001_ffff;
            default: ring_mask = 33'h1_ffff_ffff;
        endcase
        ring_width = width + 1;
        count_value = {26'd0, count};
        effective_count = 0;
        signed_shifted = signed_operand;
        signed_result = signed_operand;

        if (count != 6'd0) begin
            unique case (shift_kind)
                2'b00, 2'b01: begin
                    if (direction_left) begin
                        result_value = (count_value < width) ?
                            ((working << count) & width_mask) : 32'd0;
                        if (count_value <= width)
                            carry_value = |((working >>
                                            (width - count_value)) &
                                            32'd1);

                        // ASL reports overflow if the sign changed at any
                        // intermediate step.  For a count below the operand
                        // width, comparing the exact signed product with the
                        // sign extension of the truncated result is
                        // equivalent to observing every crossed sign bit.
                        // Once the entire operand has been shifted out, every
                        // non-zero input necessarily crossed the sign bit.
                        if (shift_kind == 2'b00) begin
                            if (count_value < width) begin
                                signed_shifted = signed_operand <<< count;
                                case (size)
                                    M64K_OP_BYTE:
                                        signed_result =
                                            {{56{result_value[7]}},
                                             result_value[7:0]};
                                    M64K_OP_WORD:
                                        signed_result =
                                            {{48{result_value[15]}},
                                             result_value[15:0]};
                                    default:
                                        signed_result =
                                            {{32{result_value[31]}},
                                             result_value};
                                endcase
                                overflow_value =
                                    (signed_shifted != signed_result);
                            end else begin
                                overflow_value = (working != 32'd0);
                            end
                        end
                    end else if (shift_kind == 2'b00) begin
                        if (count_value < width) begin
                            case (size)
                                M64K_OP_BYTE:
                                    result_value =
                                        {{24{working[7]}}, working[7:0]} >>>
                                        count;
                                M64K_OP_WORD:
                                    result_value =
                                        {{16{working[15]}}, working[15:0]} >>>
                                        count;
                                default:
                                    result_value = $signed(working) >>> count;
                            endcase
                            result_value = result_value & width_mask;
                            carry_value = |((working >> (count - 1)) & 32'd1);
                        end else begin
                            result_value = ((working & sign_mask) != 32'd0) ?
                                           width_mask : 32'd0;
                            carry_value = |(working & sign_mask);
                        end
                    end else begin
                        result_value = (count_value < width) ?
                                       (working >> count) : 32'd0;
                        if (count_value <= width)
                            carry_value = |((working >> (count - 1)) & 32'd1);
                    end
                    extend_value = carry_value;
                end

                2'b10: begin
                    // ROX rotates a width+1 ring whose bit zero is X and
                    // whose remaining bits are the architectural operand.
                    // The modulo constants are fixed after size selection;
                    // the datapath is a pair of barrel shifts plus an OR.
                    // count is six bits.  Reduce it modulo 9/17/33 with a
                    // short subtract network instead of inferring a divider.
                    effective_count = count_value;
                    case (size)
                        M64K_OP_BYTE: begin
                            if (effective_count >= 36)
                                effective_count = effective_count - 36;
                            if (effective_count >= 18)
                                effective_count = effective_count - 18;
                            if (effective_count >= 9)
                                effective_count = effective_count - 9;
                        end
                        M64K_OP_WORD: begin
                            if (effective_count >= 34)
                                effective_count = effective_count - 34;
                            if (effective_count >= 17)
                                effective_count = effective_count - 17;
                        end
                        default: begin
                            if (effective_count >= 33)
                                effective_count = effective_count - 33;
                        end
                    endcase
                    rotate_ring = (({1'd0, working} << 1) |
                                   {32'd0, old_extend}) & ring_mask;
                    if (effective_count == 0) begin
                        rotated_ring = rotate_ring;
                    end else if (direction_left) begin
                        rotated_ring =
                            ((rotate_ring << effective_count) |
                             (rotate_ring >>
                              (ring_width - effective_count))) & ring_mask;
                    end else begin
                        rotated_ring =
                            ((rotate_ring >> effective_count) |
                             (rotate_ring <<
                              (ring_width - effective_count))) & ring_mask;
                    end
                    result_value = rotated_ring[32:1] & width_mask;
                    carry_value = rotated_ring[0];
                    extend_value = rotated_ring[0];
                end

                default: begin
                    // Plain rotates use the operand-width ring and never
                    // modify X.  C is still the final bit rotated out, even
                    // when a non-zero count is a whole multiple of width.
                    effective_count = count_value & (width - 1);
                    if (effective_count == 0) begin
                        result_value = working;
                    end else if (direction_left) begin
                        result_value =
                            ((working << effective_count) |
                             (working >> (width - effective_count))) &
                            width_mask;
                    end else begin
                        result_value =
                            ((working >> effective_count) |
                             (working << (width - effective_count))) &
                            width_mask;
                    end
                    carry_value = direction_left ? result_value[0] :
                        |((result_value >> (width - 1)) & 32'd1);
                end
            endcase
        end else if (shift_kind == 2'b10) begin
            // M68000PRM: a zero-count ROX copies X to C; all other
            // zero-count register shifts clear C.  X is always preserved.
            carry_value = old_extend;
        end

        shift_result.result = result_value & width_mask;
        shift_result.flags.x = (shift_kind == 2'b11) ? old_extend :
                               extend_value;
        shift_result.flags.n = |(result_value & sign_mask);
        shift_result.flags.z = ((result_value & width_mask) == 32'd0);
        shift_result.flags.v = overflow_value;
        shift_result.flags.c = carry_value;
    end
endmodule
