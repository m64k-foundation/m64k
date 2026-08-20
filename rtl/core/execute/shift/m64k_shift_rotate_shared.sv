// Unified scalar shift/rotate execution candidate. Ordinary operations use one
// throughput-one logarithmic datapath. Rotate-through-X reuses that same
// datapath for two complementary shifts and publishes the GPR/X result
// atomically. A ROX request occupies the shared resource for one additional
// execution cycle; it does not instantiate a second variable-distance barrel.
module m64k_shift_rotate_shared (
    input  logic clock,
    input  logic reset,

    input  logic request_valid,
    output logic request_ready,
    input  m64k_shift_rotate_shared_pkg::m64k_shift_rotate_shared_request_t request,

    input  logic squash_valid,
    input  m64k_shift_rotate_shared_pkg::m64k_shift_rotate_shared_squash_t squash,

    output logic response_valid,
    input  logic response_ready,
    output m64k_shift_rotate_shared_pkg::m64k_shift_rotate_shared_response_t response
);
    import m64k_execute_backend_pkg::*;
    import m64k_shift_rotate_pkg::*;
    import m64k_shift_rotate_shared_pkg::*;

    typedef enum logic [1:0] {
        SHIFT_ROTATE_IDLE,
        SHIFT_ROTATE_ROX_SECOND,
        SHIFT_ROTATE_RESPONSE
    } shift_rotate_state_t;

    shift_rotate_state_t state;
    m64k_shift_rotate_shared_response_t response_state;

    logic [63:0] rox_first_partial;
    logic [5:0] rox_effective_count;
    m64k_shift_size_t rox_operand_size;
    logic rox_right;
    logic rox_extend_in;
    logic rox_first_extend_out;
    logic rox_update_flags;

    logic request_is_rox;
    logic incoming_request_squashed;
    logic active_rox_squashed;
    logic accepting_request;

    logic [63:0] selected_operand_mask;
    logic [6:0] rox_operand_width;
    logic [63:0] masked_request_source;
    logic [5:0] request_rox_count;
    logic [6:0] rox_complement_count;
    logic rox_second_shift_is_full_width;
    logic [63:0] rox_first_source;
    logic rox_count_one_extend_out;
    logic [63:0] rox_result;

    logic [63:0] datapath_source;
    logic [5:0] datapath_count;
    m64k_shift_size_t datapath_size;
    m64k_shift_operation_t datapath_operation;
    logic datapath_update_flags;
    logic datapath_supported;
    logic [63:0] datapath_result;
    logic datapath_result_valid;
    logic datapath_negative;
    logic datapath_zero;
    logic datapath_overflow;
    logic datapath_carry;
    logic datapath_flags_valid;

    function automatic logic [5:0] reduce_rox_count(
        input logic [5:0] selected_count,
        input m64k_shift_size_t selected_size
    );
        logic [5:0] reduced;

        reduced = selected_count;

        case (selected_size)
            M64K_SHIFT_SIZE_BYTE: begin
                if (reduced >= 6'd36) begin
                    reduced = reduced - 6'd36;
                end
                if (reduced >= 6'd18) begin
                    reduced = reduced - 6'd18;
                end
                if (reduced >= 6'd9) begin
                    reduced = reduced - 6'd9;
                end
            end
            M64K_SHIFT_SIZE_WORD: begin
                if (reduced >= 6'd34) begin
                    reduced = reduced - 6'd34;
                end
                if (reduced >= 6'd17) begin
                    reduced = reduced - 6'd17;
                end
            end
            M64K_SHIFT_SIZE_LONG: begin
                if (reduced >= 6'd33) begin
                    reduced = reduced - 6'd33;
                end
            end
            M64K_SHIFT_SIZE_QUAD: begin
                // A six-bit architectural count is always less than 65.
            end
        endcase

        return reduced;
    endfunction

    always_comb begin
        request_is_rox = request.operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR};
        incoming_request_squashed = squash_valid && squash.tag == request.tag;
        active_rox_squashed = squash_valid && squash.tag == response_state.tag;

        response_valid = state == SHIFT_ROTATE_RESPONSE;
        response = response_state;

        case (request.operand_size)
            M64K_SHIFT_SIZE_BYTE: begin
                selected_operand_mask = 64'h0000_0000_0000_00ff;
            end
            M64K_SHIFT_SIZE_WORD: begin
                selected_operand_mask = 64'h0000_0000_0000_ffff;
            end
            M64K_SHIFT_SIZE_LONG: begin
                selected_operand_mask = 64'h0000_0000_ffff_ffff;
            end
            M64K_SHIFT_SIZE_QUAD: begin
                selected_operand_mask = 64'hffff_ffff_ffff_ffff;
            end
        endcase

        case (rox_operand_size)
            M64K_SHIFT_SIZE_BYTE: rox_operand_width = 7'd8;
            M64K_SHIFT_SIZE_WORD: rox_operand_width = 7'd16;
            M64K_SHIFT_SIZE_LONG: rox_operand_width = 7'd32;
            M64K_SHIFT_SIZE_QUAD: rox_operand_width = 7'd64;
        endcase

        masked_request_source = request.source & selected_operand_mask;
        request_rox_count = reduce_rox_count(request.count, request.operand_size);

        rox_complement_count = rox_operand_width + 7'd1 - {1'b0, rox_effective_count};
        rox_second_shift_is_full_width = rox_complement_count == 7'd64;

        case (request.operand_size)
            M64K_SHIFT_SIZE_BYTE: begin
                rox_first_source = request.operation == M64K_SHIFT_ROXR
                    ? {56'd0, request.extend_in, masked_request_source[7:1]}
                    : {56'd0, masked_request_source[6:0], request.extend_in};
                rox_count_one_extend_out = request.operation == M64K_SHIFT_ROXR
                    ? masked_request_source[0]
                    : masked_request_source[7];
            end
            M64K_SHIFT_SIZE_WORD: begin
                rox_first_source = request.operation == M64K_SHIFT_ROXR
                    ? {48'd0, request.extend_in, masked_request_source[15:1]}
                    : {48'd0, masked_request_source[14:0], request.extend_in};
                rox_count_one_extend_out = request.operation == M64K_SHIFT_ROXR
                    ? masked_request_source[0]
                    : masked_request_source[15];
            end
            M64K_SHIFT_SIZE_LONG: begin
                rox_first_source = request.operation == M64K_SHIFT_ROXR
                    ? {32'd0, request.extend_in, masked_request_source[31:1]}
                    : {32'd0, masked_request_source[30:0], request.extend_in};
                rox_count_one_extend_out = request.operation == M64K_SHIFT_ROXR
                    ? masked_request_source[0]
                    : masked_request_source[31];
            end
            M64K_SHIFT_SIZE_QUAD: begin
                rox_first_source = request.operation == M64K_SHIFT_ROXR
                    ? {request.extend_in, masked_request_source[63:1]}
                    : {masked_request_source[62:0], request.extend_in};
                rox_count_one_extend_out = request.operation == M64K_SHIFT_ROXR
                    ? masked_request_source[0]
                    : masked_request_source[63];
            end
        endcase

        datapath_source = request.source;
        datapath_count = request.count;
        datapath_size = request.operand_size;
        datapath_operation = request.operation;
        datapath_update_flags = request.update_flags;

        if (state == SHIFT_ROTATE_ROX_SECOND) begin
            datapath_source = response_state.result;
            datapath_count = rox_complement_count[5:0];
            datapath_size = rox_operand_size;
            datapath_operation = rox_right ? M64K_SHIFT_LSL : M64K_SHIFT_LSR;
            datapath_update_flags = 1'b0;
        end else if (request_is_rox) begin
            datapath_source = request_rox_count == 6'd0 ? masked_request_source : rox_first_source;
            datapath_count = request_rox_count == 6'd0 ? 6'd0 : request_rox_count - 6'd1;
            datapath_operation = request.operation == M64K_SHIFT_ROXR ? M64K_SHIFT_LSR : M64K_SHIFT_LSL;
            datapath_update_flags = 1'b0;
        end

    end

    m64k_shift_rotate_fast datapath (
        .source(datapath_source),
        .count(datapath_count),
        .operand_size(datapath_size),
        .operation(datapath_operation),
        .update_flags(datapath_update_flags),
        .operation_supported(datapath_supported),
        .result(datapath_result),
        .result_valid(datapath_result_valid),
        .negative(datapath_negative),
        .zero(datapath_zero),
        .overflow(datapath_overflow),
        .carry(datapath_carry),
        .flags_valid(datapath_flags_valid)
    );

    always_comb begin
        request_ready = (state == SHIFT_ROTATE_IDLE || (state == SHIFT_ROTATE_RESPONSE && response_ready))
            && (request_is_rox || (datapath_supported && datapath_result_valid));
        accepting_request = request_valid && request_ready && !incoming_request_squashed;

        if (rox_effective_count == 6'd0) begin
            rox_result = response_state.result;
        end else begin
            rox_result = rox_first_partial | (rox_second_shift_is_full_width ? 64'd0 : datapath_result);
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            state <= SHIFT_ROTATE_IDLE;
        end else begin
            case (state)
                SHIFT_ROTATE_IDLE,
                SHIFT_ROTATE_RESPONSE: begin
                    if (state == SHIFT_ROTATE_RESPONSE && !response_ready) begin
                        state <= SHIFT_ROTATE_RESPONSE;
                    end else if (accepting_request) begin
                        response_state <= '0;
                        response_state.tag <= request.tag;

                        if (request_is_rox) begin
                            response_state.result <= masked_request_source;
                            rox_first_partial <= datapath_result;
                            rox_effective_count <= request_rox_count;
                            rox_operand_size <= request.operand_size;
                            rox_right <= request.operation == M64K_SHIFT_ROXR;
                            rox_extend_in <= request.extend_in;
                            rox_first_extend_out <= request_rox_count == 6'd1 ? rox_count_one_extend_out : datapath_carry;
                            rox_update_flags <= request.update_flags;
                            state <= SHIFT_ROTATE_ROX_SECOND;
                        end else begin
                            response_state.result <= datapath_result;
                            response_state.flags_valid <= datapath_flags_valid;
                            response_state.negative <= datapath_negative;
                            response_state.zero <= datapath_zero;
                            response_state.overflow <= datapath_overflow;
                            response_state.carry <= datapath_carry;
                            response_state.extend_valid <= 1'b0;
                            response_state.extend_out <= request.extend_in;
                            state <= SHIFT_ROTATE_RESPONSE;
                        end
                    end else begin
                        state <= SHIFT_ROTATE_IDLE;
                    end
                end
                SHIFT_ROTATE_ROX_SECOND: begin
                    if (active_rox_squashed) begin
                        state <= SHIFT_ROTATE_IDLE;
                    end else begin
                        response_state.result <= rox_result;
                        response_state.flags_valid <= rox_update_flags;
                        response_state.negative <= rox_result[6'(rox_operand_width - 7'd1)];
                        response_state.zero <= rox_result == 64'd0;
                        response_state.overflow <= 1'b0;
                        response_state.carry <= rox_effective_count == 6'd0 ? rox_extend_in : rox_first_extend_out;
                        response_state.extend_valid <= 1'b1;
                        response_state.extend_out <= rox_effective_count == 6'd0 ? rox_extend_in : rox_first_extend_out;
                        state <= SHIFT_ROTATE_RESPONSE;
                    end
                end
                default: begin
                    state <= SHIFT_ROTATE_IDLE;
                end
            endcase
        end
    end

endmodule
