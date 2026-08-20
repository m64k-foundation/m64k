// Radix-4 restoring divider. Each cycle consumes two dividend bits through two
// cascaded 65-bit compare/subtract steps. This halves worst-case 128-by-64
// latency relative to radix-2 while retaining a compact single-lane datapath.
module m64k_scalar_divider (
    input  logic clock,
    input  logic reset,

    input  logic request_valid,
    output logic request_ready,
    input  m64k_scalar_divider_pkg::m64k_divide_request_t request,

    input  logic squash_valid,
    input  m64k_scalar_divider_pkg::m64k_divide_squash_t squash,

    output logic response_valid,
    input  logic response_ready,
    output m64k_scalar_divider_pkg::m64k_divide_response_t response
);
    import m64k_scalar_divider_pkg::*;
    import m64k_execute_backend_pkg::*;

    typedef enum logic [1:0] {
        DIVIDER_IDLE,
        DIVIDER_ITERATE,
        DIVIDER_RESPONSE
    } divider_state_t;

    divider_state_t state;
    m64k_execute_tag_t operation_tag;
    m64k_divide_result_form_t operation_result_form;
    logic operation_signed;
    logic operation_update_flags;
    logic quotient_negative;
    logic remainder_negative;
    logic [63:0] operand_mask;
    logic [63:0] operand_sign_bit;
    logic [63:0] divisor_magnitude;
    logic [127:0] dividend_quotient;
    logic [63:0] partial_remainder;
    logic [7:0] iterations_remaining;

    logic [64:0] first_shifted_remainder;
    logic [63:0] first_reduced_remainder;
    logic first_quotient_bit;
    logic [64:0] second_shifted_remainder;
    logic [63:0] second_reduced_remainder;
    logic second_quotient_bit;
    logic [127:0] next_dividend_quotient;
    logic squash_matches_operation;
    logic incoming_request_squashed;

    function automatic logic [63:0] select_operand_mask(input m64k_divide_size_t operand_size);
        case (operand_size)
            M64K_DIVIDE_SIZE_BYTE: begin
                return 64'h0000_0000_0000_00ff;
            end
            M64K_DIVIDE_SIZE_WORD: begin
                return 64'h0000_0000_0000_ffff;
            end
            M64K_DIVIDE_SIZE_LONG: begin
                return 64'h0000_0000_ffff_ffff;
            end
            M64K_DIVIDE_SIZE_QUAD: begin
                return 64'hffff_ffff_ffff_ffff;
            end
        endcase
    endfunction

    function automatic logic [63:0] select_operand_sign_bit(input m64k_divide_size_t operand_size);
        case (operand_size)
            M64K_DIVIDE_SIZE_BYTE: begin
                return 64'h0000_0000_0000_0080;
            end
            M64K_DIVIDE_SIZE_WORD: begin
                return 64'h0000_0000_0000_8000;
            end
            M64K_DIVIDE_SIZE_LONG: begin
                return 64'h0000_0000_8000_0000;
            end
            M64K_DIVIDE_SIZE_QUAD: begin
                return 64'h8000_0000_0000_0000;
            end
        endcase
    endfunction

    function automatic logic [7:0] select_operand_width(input m64k_divide_size_t operand_size);
        case (operand_size)
            M64K_DIVIDE_SIZE_BYTE: begin
                return 8'd8;
            end
            M64K_DIVIDE_SIZE_WORD: begin
                return 8'd16;
            end
            M64K_DIVIDE_SIZE_LONG: begin
                return 8'd32;
            end
            M64K_DIVIDE_SIZE_QUAD: begin
                return 8'd64;
            end
        endcase
    endfunction

    function automatic logic [63:0] negate_with_mask(input logic [63:0] value, input logic [63:0] width_mask);
        return ((~value) + 64'd1) & width_mask;
    endfunction

    always_comb begin
        first_shifted_remainder = {partial_remainder, dividend_quotient[127]};
        if (first_shifted_remainder >= {1'b0, divisor_magnitude}) begin
            first_reduced_remainder = first_shifted_remainder[63:0] - divisor_magnitude;
            first_quotient_bit = 1'b1;
        end else begin
            first_reduced_remainder = first_shifted_remainder[63:0];
            first_quotient_bit = 1'b0;
        end

        second_shifted_remainder = {first_reduced_remainder, dividend_quotient[126]};
        if (second_shifted_remainder >= {1'b0, divisor_magnitude}) begin
            second_reduced_remainder = second_shifted_remainder[63:0] - divisor_magnitude;
            second_quotient_bit = 1'b1;
        end else begin
            second_reduced_remainder = second_shifted_remainder[63:0];
            second_quotient_bit = 1'b0;
        end

        next_dividend_quotient = {dividend_quotient[125:0], first_quotient_bit, second_quotient_bit};
    end

    always_comb begin
        squash_matches_operation = squash_valid && squash.tag == operation_tag;
        incoming_request_squashed = squash_valid && squash.tag == request.tag;

        request_ready = state == DIVIDER_IDLE;
        response_valid = state == DIVIDER_RESPONSE;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            state <= DIVIDER_IDLE;
            operation_tag <= '0;
            operation_result_form <= M64K_DIVIDE_QUOTIENT;
            operation_signed <= 1'b0;
            operation_update_flags <= 1'b0;
            quotient_negative <= 1'b0;
            remainder_negative <= 1'b0;
            operand_mask <= 64'd0;
            operand_sign_bit <= 64'd0;
            divisor_magnitude <= 64'd0;
            dividend_quotient <= 128'd0;
            partial_remainder <= 64'd0;
            iterations_remaining <= 8'd0;
            response <= '0;
        end else begin
            case (state)
                DIVIDER_IDLE: begin
                    if (request_valid && request_ready && !incoming_request_squashed) begin : accept_request
                        logic [63:0] selected_mask;
                        logic [63:0] selected_sign_bit;
                        logic [7:0] selected_width;
                        logic [63:0] truncated_divisor;
                        logic [127:0] raw_dividend;
                        logic [127:0] dividend_width_mask;
                        logic [128:0] extended_dividend;
                        logic [128:0] dividend_magnitude;
                        logic [127:0] aligned_dividend_magnitude;
                        logic divisor_is_negative;
                        logic dividend_is_negative;

                        selected_mask = select_operand_mask(request.operand_size);
                        selected_sign_bit = select_operand_sign_bit(request.operand_size);
                        selected_width = select_operand_width(request.operand_size);
                        truncated_divisor = request.divisor & selected_mask;
                        divisor_is_negative = request.signed_operation && ((truncated_divisor & selected_sign_bit) != 64'd0);

                        if (request.double_width_dividend) begin
                            case (request.operand_size)
                                M64K_DIVIDE_SIZE_BYTE: begin
                                    raw_dividend = {112'd0, request.dividend_high[7:0], request.dividend_low[7:0]};
                                    dividend_width_mask = {112'd0, 16'hffff};
                                end
                                M64K_DIVIDE_SIZE_WORD: begin
                                    raw_dividend = {96'd0, request.dividend_high[15:0], request.dividend_low[15:0]};
                                    dividend_width_mask = {96'd0, 32'hffff_ffff};
                                end
                                M64K_DIVIDE_SIZE_LONG: begin
                                    raw_dividend = {64'd0, request.dividend_high[31:0], request.dividend_low[31:0]};
                                    dividend_width_mask = {64'd0, 64'hffff_ffff_ffff_ffff};
                                end
                                M64K_DIVIDE_SIZE_QUAD: begin
                                    raw_dividend = {request.dividend_high, request.dividend_low};
                                    dividend_width_mask = 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff;
                                end
                            endcase
                            dividend_is_negative = request.signed_operation && ((request.dividend_high & selected_sign_bit) != 64'd0);
                            iterations_remaining <= selected_width;
                        end else begin
                            raw_dividend = {64'd0, request.dividend_low & selected_mask};
                            dividend_width_mask = {64'd0, selected_mask};
                            dividend_is_negative = request.signed_operation && ((request.dividend_low & selected_sign_bit) != 64'd0);
                            iterations_remaining <= selected_width >> 1;
                        end

                        if (dividend_is_negative) begin
                            extended_dividend = {1'b1, raw_dividend | ~dividend_width_mask};
                            dividend_magnitude = (~extended_dividend) + 129'd1;
                        end else begin
                            extended_dividend = {1'b0, raw_dividend};
                            dividend_magnitude = extended_dividend;
                        end

                        case ({request.double_width_dividend, request.operand_size})
                            {1'b0, M64K_DIVIDE_SIZE_BYTE}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 120;
                            end
                            {1'b0, M64K_DIVIDE_SIZE_WORD}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 112;
                            end
                            {1'b0, M64K_DIVIDE_SIZE_LONG}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 96;
                            end
                            {1'b0, M64K_DIVIDE_SIZE_QUAD}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 64;
                            end
                            {1'b1, M64K_DIVIDE_SIZE_BYTE}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 112;
                            end
                            {1'b1, M64K_DIVIDE_SIZE_WORD}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 96;
                            end
                            {1'b1, M64K_DIVIDE_SIZE_LONG}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0] << 64;
                            end
                            {1'b1, M64K_DIVIDE_SIZE_QUAD}: begin
                                aligned_dividend_magnitude = dividend_magnitude[127:0];
                            end
                        endcase

                        assert (!dividend_magnitude[128])
                            else $error("M64K divider magnitude exceeded the unsigned 128-bit dividend domain");
                        assert (!request.double_width_dividend || request.result_form == M64K_DIVIDE_QUOTIENT_REMAINDER)
                            else $error("M64K double-width divide requires the fused quotient-remainder result form");

                        operation_tag <= request.tag;
                        operation_result_form <= request.result_form;
                        operation_signed <= request.signed_operation;
                        operation_update_flags <= request.update_flags;
                        quotient_negative <= dividend_is_negative != divisor_is_negative;
                        remainder_negative <= dividend_is_negative;
                        operand_mask <= selected_mask;
                        operand_sign_bit <= selected_sign_bit;
                        divisor_magnitude <= divisor_is_negative ? negate_with_mask(truncated_divisor, selected_mask) : truncated_divisor;
                        dividend_quotient <= aligned_dividend_magnitude;
                        partial_remainder <= 64'd0;

                        response.tag <= request.tag;
                        response.result_count <= 2'd0;
                        response.results[0].valid <= 1'b0;
                        response.results[0].role <= M64K_EXECUTE_RESULT_QUOTIENT;
                        response.results[0].value <= 64'd0;
                        response.results[1].valid <= 1'b0;
                        response.results[1].role <= M64K_EXECUTE_RESULT_REMAINDER;
                        response.results[1].value <= 64'd0;
                        response.flags_valid <= 1'b0;
                        response.negative <= 1'b0;
                        response.zero <= 1'b0;
                        response.overflow <= 1'b0;
                        response.carry <= 1'b0;
                        response.fault_valid <= 1'b0;
                        response.fault <= M64K_DIVIDE_FAULT_NONE;

                        if (truncated_divisor == 64'd0) begin
                            response.fault_valid <= 1'b1;
                            response.fault <= M64K_DIVIDE_FAULT_ZERO;
                            state <= DIVIDER_RESPONSE;
                        end else begin
                            state <= DIVIDER_ITERATE;
                        end
                    end
                end

                DIVIDER_ITERATE: begin
                    if (squash_matches_operation) begin
                        state <= DIVIDER_IDLE;
                    end else begin
                        dividend_quotient <= next_dividend_quotient;
                        partial_remainder <= second_reduced_remainder;
                        iterations_remaining <= iterations_remaining - 8'd1;

                        if (iterations_remaining == 8'd1) begin : finish_divide
                            logic [127:0] quotient_magnitude;
                            logic [63:0] quotient_result;
                            logic [63:0] remainder_result;
                            logic quotient_requested;
                            logic remainder_requested;
                            logic quotient_overflow;
                            logic positive_signed_overflow;
                            logic negative_signed_overflow;
                            logic unsigned_overflow;
                            logic selected_flag_value_is_zero;

                            quotient_magnitude = next_dividend_quotient;
                            quotient_result = quotient_negative
                                ? negate_with_mask(quotient_magnitude[63:0], operand_mask)
                                : quotient_magnitude[63:0] & operand_mask;
                            remainder_result = remainder_negative
                                ? negate_with_mask(second_reduced_remainder, operand_mask)
                                : second_reduced_remainder & operand_mask;
                            quotient_requested = operation_result_form != M64K_DIVIDE_REMAINDER;
                            remainder_requested = operation_result_form != M64K_DIVIDE_QUOTIENT;

                            unsigned_overflow = (quotient_magnitude & ~{64'd0, operand_mask}) != 128'd0;
                            positive_signed_overflow = unsigned_overflow || ((quotient_magnitude[63:0] & operand_sign_bit) != 64'd0);
                            negative_signed_overflow = unsigned_overflow
                                || quotient_magnitude[63:0] > operand_sign_bit;
                            if (operation_signed) begin
                                quotient_overflow = quotient_negative ? negative_signed_overflow : positive_signed_overflow;
                            end else begin
                                quotient_overflow = unsigned_overflow;
                            end

                            if (quotient_requested && quotient_overflow) begin
                                response.result_count <= 2'd0;
                                response.results[0].valid <= 1'b0;
                                response.results[1].valid <= 1'b0;
                                response.results[0].value <= 64'd0;
                                response.results[1].value <= 64'd0;
                                response.flags_valid <= 1'b0;
                                response.negative <= 1'b0;
                                response.zero <= 1'b0;
                                response.fault_valid <= 1'b1;
                                response.fault <= M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW;
                            end else begin
                                response.result_count <= {1'b0, quotient_requested} + {1'b0, remainder_requested};
                                case (operation_result_form)
                                    M64K_DIVIDE_QUOTIENT: begin
                                        response.results[0].valid <= 1'b1;
                                        response.results[0].role <= M64K_EXECUTE_RESULT_QUOTIENT;
                                        response.results[0].value <= quotient_result;
                                        response.results[1].valid <= 1'b0;
                                        response.results[1].role <= M64K_EXECUTE_RESULT_REMAINDER;
                                        response.results[1].value <= 64'd0;
                                    end
                                    M64K_DIVIDE_REMAINDER: begin
                                        response.results[0].valid <= 1'b1;
                                        response.results[0].role <= M64K_EXECUTE_RESULT_REMAINDER;
                                        response.results[0].value <= remainder_result;
                                        response.results[1].valid <= 1'b0;
                                        response.results[1].role <= M64K_EXECUTE_RESULT_QUOTIENT;
                                        response.results[1].value <= 64'd0;
                                    end
                                    M64K_DIVIDE_QUOTIENT_REMAINDER: begin
                                        response.results[0].valid <= 1'b1;
                                        response.results[0].role <= M64K_EXECUTE_RESULT_QUOTIENT;
                                        response.results[0].value <= quotient_result;
                                        response.results[1].valid <= 1'b1;
                                        response.results[1].role <= M64K_EXECUTE_RESULT_REMAINDER;
                                        response.results[1].value <= remainder_result;
                                    end
                                    default: begin
                                        response.results[0].valid <= 1'b0;
                                        response.results[1].valid <= 1'b0;
                                    end
                                endcase
                                response.flags_valid <= operation_update_flags;
                                if (operation_result_form == M64K_DIVIDE_REMAINDER) begin
                                    response.negative <= (remainder_result & operand_sign_bit) != 64'd0;
                                    selected_flag_value_is_zero = (remainder_result & operand_mask) == 64'd0;
                                end else begin
                                    response.negative <= (quotient_result & operand_sign_bit) != 64'd0;
                                    selected_flag_value_is_zero = (quotient_result & operand_mask) == 64'd0;
                                end
                                response.zero <= selected_flag_value_is_zero;
                                response.fault_valid <= 1'b0;
                                response.fault <= M64K_DIVIDE_FAULT_NONE;
                            end

                            response.overflow <= 1'b0;
                            response.carry <= 1'b0;
                            state <= DIVIDER_RESPONSE;
                        end
                    end
                end

                DIVIDER_RESPONSE: begin
                    if (response_ready) begin
                        state <= DIVIDER_IDLE;
                    end
                end

                default: begin
                    state <= DIVIDER_IDLE;
                end
            endcase
        end
    end

endmodule
