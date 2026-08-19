package mx68k_shift_reference_pkg;
    import mx68k_arch_pkg::*;

    // Straight one-bit-at-a-time architectural oracle.  Its structure is
    // intentionally different from the barrel RTL and follows the shift
    // pseudocode/flag rules in M68000PRM 4-20..4-23, 4-112..4-115 and
    // 4-159..4-165.  This package is simulation-only.
    function automatic mx_alu_result_t reference_shift(
        input logic [31:0] ref_operand,
        input mx_operand_size_t ref_size,
        input logic [5:0] ref_count,
        input logic ref_left,
        input logic [1:0] ref_kind,
        input logic ref_x
    );
        mx_alu_result_t value;
        logic [31:0] width_mask;
        logic [31:0] sign_mask;
        logic [31:0] working;
        logic [31:0] shifted;
        logic out_bit;
        logic incoming_bit;
        logic extend_bit;
        logic overflow;
        logic old_sign;
        begin
            case (ref_size)
                MX_OP_BYTE: begin
                    width_mask = 32'h0000_00ff;
                    sign_mask = 32'h0000_0080;
                end
                MX_OP_WORD: begin
                    width_mask = 32'h0000_ffff;
                    sign_mask = 32'h0000_8000;
                end
                default: begin
                    width_mask = 32'hffff_ffff;
                    sign_mask = 32'h8000_0000;
                end
            endcase
            working = ref_operand & width_mask;
            extend_bit = ref_x;
            out_bit = 1'b0;
            overflow = 1'b0;
            for (int shift_index = 0; shift_index < 64; shift_index++) begin
                if (shift_index < ref_count) begin
                    old_sign = |(working & sign_mask);
                    out_bit = ref_left ? old_sign : working[0];
                    incoming_bit = 1'b0;
                    if (ref_kind == 2'b10)
                        incoming_bit = extend_bit;
                    else if (ref_kind == 2'b11)
                        incoming_bit = out_bit;
                    else if ((ref_kind == 2'b00) && !ref_left)
                        incoming_bit = old_sign;
                    if (ref_left) begin
                        shifted = (working << 1) & width_mask;
                        if (incoming_bit)
                            shifted[0] = 1'b1;
                        if (ref_kind == 2'b00)
                            overflow = overflow |
                                       (old_sign != |(shifted & sign_mask));
                    end else begin
                        shifted = working >> 1;
                        if (incoming_bit)
                            shifted = shifted | sign_mask;
                    end
                    working = shifted;
                    if (ref_kind != 2'b11)
                        extend_bit = out_bit;
                end
            end
            value.result = working;
            value.flags.n = |(working & sign_mask);
            value.flags.z = (working == 32'd0);
            value.flags.v = overflow;
            if (ref_count == 6'd0) begin
                value.flags.c = (ref_kind == 2'b10) ? ref_x : 1'b0;
                value.flags.x = ref_x;
            end else begin
                value.flags.c = out_bit;
                value.flags.x = (ref_kind == 2'b11) ? ref_x : extend_bit;
            end
            return value;
        end
    endfunction
endpackage
