package mx68k_arch_pkg;
    typedef enum logic [1:0] {
        MX_PROFILE_M00 = 2'd0,
        MX_PROFILE_M10 = 2'd1,
        MX_PROFILE_M20 = 2'd2,
        MX_PROFILE_M40 = 2'd3
    } mx_profile_t;

    typedef enum logic [1:0] {
        MX_OP_BYTE = 2'd0,
        MX_OP_WORD = 2'd1,
        MX_OP_LONG = 2'd2
    } mx_operand_size_t;

    // Status register. Reserved bits are not writable architectural state.
    localparam int unsigned MX_SR_T1 = 15;
    localparam int unsigned MX_SR_T0 = 14;
    localparam int unsigned MX_SR_S  = 13;
    localparam int unsigned MX_SR_M  = 12;
    localparam int unsigned MX_SR_I2 = 10;
    localparam int unsigned MX_SR_I1 = 9;
    localparam int unsigned MX_SR_I0 = 8;
    localparam int unsigned MX_SR_X  = 4;
    localparam int unsigned MX_SR_N  = 3;
    localparam int unsigned MX_SR_Z  = 2;
    localparam int unsigned MX_SR_V  = 1;
    localparam int unsigned MX_SR_C  = 0;

    localparam logic [15:0] MX_SR_TRACE_MASK = 16'hc000;
    localparam logic [15:0] MX_SR_SUPERVISOR_MASK = 16'h3000;
    localparam logic [15:0] MX_SR_INTERRUPT_MASK = 16'h0700;
    localparam logic [15:0] MX_SR_CCR_MASK = 16'h001f;
    localparam logic [15:0] MX_SR_M00_DEFINED_MASK = 16'ha71f;
    localparam logic [15:0] MX_SR_M20_DEFINED_MASK = 16'hf71f;

    // Standard vector numbers shared by the compatibility profiles. The exact
    // meaning and frame format remain profile-specific.
    localparam logic [7:0] MX_VECTOR_RESET_SSP = 8'd0;
    localparam logic [7:0] MX_VECTOR_RESET_PC = 8'd1;
    localparam logic [7:0] MX_VECTOR_ACCESS_FAULT = 8'd2;
    localparam logic [7:0] MX_VECTOR_ADDRESS_ERROR = 8'd3;
    localparam logic [7:0] MX_VECTOR_ILLEGAL = 8'd4;
    localparam logic [7:0] MX_VECTOR_ZERO_DIVIDE = 8'd5;
    localparam logic [7:0] MX_VECTOR_CHK = 8'd6;
    localparam logic [7:0] MX_VECTOR_TRAPCC = 8'd7;
    localparam logic [7:0] MX_VECTOR_PRIVILEGE = 8'd8;
    localparam logic [7:0] MX_VECTOR_TRACE = 8'd9;
    localparam logic [7:0] MX_VECTOR_LINE_A = 8'd10;
    localparam logic [7:0] MX_VECTOR_LINE_F = 8'd11;
    localparam logic [7:0] MX_VECTOR_COPROTOCOL = 8'd13;
    localparam logic [7:0] MX_VECTOR_FORMAT_ERROR = 8'd14;
    localparam logic [7:0] MX_VECTOR_UNINITIALIZED_IRQ = 8'd15;
    localparam logic [7:0] MX_VECTOR_SPURIOUS = 8'd24;
    localparam logic [7:0] MX_VECTOR_AUTOVECTOR_BASE = 8'd24;
    localparam logic [7:0] MX_VECTOR_TRAP_BASE = 8'd32;
    localparam logic [7:0] MX_VECTOR_FP_BASE = 8'd48;
    localparam logic [7:0] MX_VECTOR_MMU_CONFIG = 8'd56;

    typedef enum logic [3:0] {
        MX_EXC_NONE,
        MX_EXC_RESET,
        MX_EXC_FETCH,
        MX_EXC_DECODE,
        MX_EXC_EXECUTE,
        MX_EXC_DATA,
        MX_EXC_FPU,
        MX_EXC_TRACE,
        MX_EXC_INTERRUPT,
        MX_EXC_TRAP,
        MX_EXC_FORMAT,
        MX_EXC_DOUBLE_FAULT
    } mx_exception_class_t;

    typedef enum logic [2:0] {
        MX_FAULT_STAGE_NONE,
        MX_FAULT_STAGE_FETCH,
        MX_FAULT_STAGE_DECODE,
        MX_FAULT_STAGE_EXECUTE,
        MX_FAULT_STAGE_TRANSLATE,
        MX_FAULT_STAGE_MEMORY,
        MX_FAULT_STAGE_COMMIT,
        MX_FAULT_STAGE_FRAME
    } mx_fault_stage_t;

    // This is the information crossing into commit. It is deliberately richer
    // than any one stack frame: the frame encoder selects fields by profile.
    typedef struct packed {
        logic valid;
        mx_exception_class_t exception_class;
        mx_fault_stage_t stage;
        logic [7:0] vector;
        logic [31:0] instruction_pc;
        logic [31:0] next_pc;
        logic [31:0] logical_address;
        logic [31:0] physical_address;
        logic [15:0] opcode;
        logic [15:0] special_status;
        logic [2:0] function_code;
        mx_operand_size_t operand_size;
        logic write;
        logic instruction;
        logic rerunnable;
    } mx_exception_t;

    typedef struct packed {
        logic x;
        logic n;
        logic z;
        logic v;
        logic c;
    } mx_alu_flags_t;

    typedef struct packed {
        logic n;
        logic z;
        logic v;
        logic c;
    } mx_condition_flags_t;

    typedef struct packed {
        logic [31:0] result;
        mx_alu_flags_t flags;
    } mx_alu_result_t;

    function automatic logic mx_interrupt_accepted(
        input logic [2:0] level,
        input logic [2:0] mask,
        input logic level7_edge
    );
        return level7_edge || ((level != 3'd0) && (level > mask));
    endfunction

    // MC68000 function-code encoding used by the group-0 special status word.
    // Program/data and user/supervisor are kept explicit so later MMUs can use
    // the same architectural access-space identity before translation.
    function automatic logic [2:0] mx_m00_function_code(
        input logic supervisor,
        input logic instruction
    );
        return {supervisor, instruction, !instruction};
    endfunction

    function automatic logic [15:0] mx_m00_special_status_word(
        input logic write,
        input logic instruction,
        input logic supervisor
    );
        logic [2:0] function_code;
        begin
            function_code = mx_m00_function_code(supervisor, instruction);
            // Bits 15:5 are zero. R/W is one for a read; I/N is one for a
            // non-instruction access; FC2:FC0 retain the access space.
            return {11'd0, !write, !instruction, function_code};
        end
    endfunction

    function automatic logic [15:0] mx_sr_defined_mask(input mx_profile_t profile);
        case (profile)
            MX_PROFILE_M00,
            MX_PROFILE_M10: return MX_SR_M00_DEFINED_MASK;
            default:        return MX_SR_M20_DEFINED_MASK;
        endcase
    endfunction

    function automatic logic [15:0] mx_sr_sanitize(
        input logic [15:0] value,
        input mx_profile_t profile
    );
        return value & mx_sr_defined_mask(profile);
    endfunction

    function automatic logic mx_condition_true(
        input logic [3:0] condition,
        input mx_condition_flags_t flags
    );
        case (condition)
            4'h0: return 1'b1;                         // T
            4'h1: return 1'b0;                         // F
            4'h2: return !flags.c && !flags.z;          // HI
            4'h3: return flags.c || flags.z;            // LS
            4'h4: return !flags.c;                      // CC/HS
            4'h5: return flags.c;                       // CS/LO
            4'h6: return !flags.z;                      // NE
            4'h7: return flags.z;                       // EQ
            4'h8: return !flags.v;                      // VC
            4'h9: return flags.v;                       // VS
            4'ha: return !flags.n;                      // PL
            4'hb: return flags.n;                       // MI
            4'hc: return flags.n == flags.v;            // GE
            4'hd: return flags.n != flags.v;            // LT
            4'he: return !flags.z && (flags.n == flags.v); // GT
            4'hf: return flags.z || (flags.n != flags.v);  // LE
            default: return 1'b0;
        endcase
    endfunction

    function automatic mx_alu_result_t mx_add(
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input mx_operand_size_t size,
        input logic carry_in,
        input logic cumulative_zero
    );
        mx_alu_result_t value;
        logic [31:0] mask;
        logic [31:0] sign_mask;
        logic [32:0] sum;
        logic lhs_sign;
        logic rhs_sign;
        logic result_sign;
        begin
            case (size)
                MX_OP_BYTE: begin mask = 32'h0000_00ff; sign_mask = 32'h0000_0080; end
                MX_OP_WORD: begin mask = 32'h0000_ffff; sign_mask = 32'h0000_8000; end
                default:    begin mask = 32'hffff_ffff; sign_mask = 32'h8000_0000; end
            endcase

            sum = {1'b0, (lhs & mask)} + {1'b0, (rhs & mask)} + carry_in;
            value = '0;
            value.result = sum[31:0] & mask;
            case (size)
                MX_OP_BYTE: value.flags.c = sum[8];
                MX_OP_WORD: value.flags.c = sum[16];
                default:    value.flags.c = sum[32];
            endcase

            lhs_sign = |(lhs & sign_mask);
            rhs_sign = |(rhs & sign_mask);
            result_sign = |(value.result & sign_mask);
            value.flags.x = value.flags.c;
            value.flags.n = result_sign;
            value.flags.z = (value.result == 32'd0) && cumulative_zero;
            value.flags.v = (lhs_sign == rhs_sign) && (result_sign != lhs_sign);
            return value;
        end
    endfunction

    function automatic mx_alu_result_t mx_subtract(
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input mx_operand_size_t size,
        input logic borrow_in,
        input logic cumulative_zero
    );
        mx_alu_result_t value;
        logic [31:0] mask;
        logic [31:0] sign_mask;
        logic [32:0] lhs_wide;
        logic [32:0] rhs_wide;
        logic [31:0] difference;
        logic lhs_sign;
        logic rhs_sign;
        logic result_sign;
        begin
            case (size)
                MX_OP_BYTE: begin mask = 32'h0000_00ff; sign_mask = 32'h0000_0080; end
                MX_OP_WORD: begin mask = 32'h0000_ffff; sign_mask = 32'h0000_8000; end
                default:    begin mask = 32'hffff_ffff; sign_mask = 32'h8000_0000; end
            endcase

            lhs_wide = {1'b0, (lhs & mask)};
            rhs_wide = {1'b0, (rhs & mask)} + borrow_in;
            difference = lhs_wide[31:0] - rhs_wide[31:0];
            value = '0;
            value.result = difference & mask;
            value.flags.c = lhs_wide < rhs_wide;

            lhs_sign = |(lhs & sign_mask);
            rhs_sign = |(rhs & sign_mask);
            result_sign = |(value.result & sign_mask);
            value.flags.x = value.flags.c;
            value.flags.n = result_sign;
            value.flags.z = (value.result == 32'd0) && cumulative_zero;
            value.flags.v = (lhs_sign != rhs_sign) && (result_sign != lhs_sign);
            return value;
        end
    endfunction

    // M68000PRM 4-1/4-2 and 4-169/4-170 define packed-BCD byte
    // arithmetic.  N and V are architecturally undefined and therefore left
    // zero here; the commit path preserves their previous values.  X mirrors
    // the decimal carry/borrow and Z is cumulative for multiprecision strings.
    function automatic mx_alu_result_t mx_add_decimal_byte(
        input logic [7:0] lhs,
        input logic [7:0] rhs,
        input logic carry_in,
        input logic cumulative_zero
    );
        mx_alu_result_t value;
        logic [4:0] low_sum;
        logic [8:0] adjusted;
        begin
            low_sum = {1'b0, lhs[3:0]} + {1'b0, rhs[3:0]} + carry_in;
            adjusted = {1'b0, lhs} + {1'b0, rhs} + carry_in;
            if (low_sum > 5'd9)
                adjusted = adjusted + 9'h006;

            value = '0;
            value.flags.c = adjusted > 9'h099;
            if (value.flags.c)
                adjusted = adjusted + 9'h060;
            value.result = {24'd0, adjusted[7:0]};
            value.flags.x = value.flags.c;
            value.flags.z = (adjusted[7:0] == 8'd0) && cumulative_zero;
            return value;
        end
    endfunction

    function automatic mx_alu_result_t mx_subtract_decimal_byte(
        input logic [7:0] lhs,
        input logic [7:0] rhs,
        input logic borrow_in,
        input logic cumulative_zero
    );
        mx_alu_result_t value;
        logic low_borrow;
        logic decimal_borrow;
        logic [8:0] adjusted;
        begin
            low_borrow = {1'b0, lhs[3:0]} <
                         ({1'b0, rhs[3:0]} + borrow_in);
            decimal_borrow = {1'b0, lhs} < ({1'b0, rhs} + borrow_in);
            adjusted = {1'b0, lhs} - ({1'b0, rhs} + borrow_in);
            if (low_borrow)
                adjusted = adjusted - 9'h006;
            if (decimal_borrow)
                adjusted = adjusted - 9'h060;

            value = '0;
            value.result = {24'd0, adjusted[7:0]};
            value.flags.c = decimal_borrow;
            value.flags.x = decimal_borrow;
            value.flags.z = (adjusted[7:0] == 8'd0) && cumulative_zero;
            return value;
        end
    endfunction
endpackage
