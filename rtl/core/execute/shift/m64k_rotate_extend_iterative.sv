// Six-stage iterative rotate-through-X execution unit implementing the ROXL
// and ROXR portion of M64K-v1.scalar-shift-rotate. Each iteration conditionally
// applies one fixed 1/2/4/8/16/32-bit rotation to a W+1-bit ring. The design
// therefore avoids a parallel variable-width rotate-through-X barrel while
// preserving a fixed six-cycle execution latency for every operand width and
// count. Published responses are irrevocable; exact-tag squash only cancels
// unpublished work.
module m64k_rotate_extend_iterative (
    input  logic clock,
    input  logic reset,

    input  logic request_valid,
    output logic request_ready,
    input  m64k_rotate_extend_iterative_pkg::m64k_rotate_extend_request_t request,

    input  logic squash_valid,
    input  m64k_rotate_extend_iterative_pkg::m64k_rotate_extend_squash_t squash,

    output logic response_valid,
    input  logic response_ready,
    output m64k_rotate_extend_iterative_pkg::m64k_rotate_extend_response_t response
);
    import m64k_rotate_extend_iterative_pkg::*;
    import m64k_shift_rotate_pkg::*;

    typedef enum logic [1:0] {
        ROTATE_EXTEND_IDLE,
        ROTATE_EXTEND_ITERATE,
        ROTATE_EXTEND_RESPONSE
    } rotate_extend_state_t;

    rotate_extend_state_t state;
    m64k_execute_backend_pkg::m64k_execute_tag_t operation_tag;
    m64k_shift_size_t operation_size;
    m64k_rotate_extend_direction_t operation_direction;
    logic operation_update_flags;
    logic [5:0] effective_count;
    logic [2:0] stage_index;
    logic [64:0] ring_state;

    logic incoming_request_squashed;
    logic active_operation_squashed;
    logic [64:0] rotated_ring;
    logic [64:0] architectural_ring;

    function automatic logic [5:0] reduce_rotate_count(
        input logic [5:0] count,
        input m64k_shift_size_t operand_size
    );
        logic [5:0] reduced;

        reduced = count;

        case (operand_size)
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
                // The architectural count is at most 63, below the 65-bit ring
                // width, so reduction cannot change the count.
            end
        endcase

        return reduced;
    endfunction

    function automatic logic [64:0] make_ring(
        input logic [63:0] source,
        input logic extend_in,
        input m64k_shift_size_t operand_size
    );
        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: return {56'd0, source[7:0], extend_in};
            M64K_SHIFT_SIZE_WORD: return {48'd0, source[15:0], extend_in};
            M64K_SHIFT_SIZE_LONG: return {32'd0, source[31:0], extend_in};
            M64K_SHIFT_SIZE_QUAD: return {source, extend_in};
        endcase
    endfunction

    function automatic logic [64:0] rotate_left_stage(
        input logic [64:0] ring,
        input m64k_shift_size_t operand_size,
        input logic [2:0] selected_stage
    );
        logic [64:0] rotated;

        rotated = ring;

        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: begin
                case (selected_stage)
                    3'd0: rotated[8:0] = {ring[7:0], ring[8]};
                    3'd1: rotated[8:0] = {ring[6:0], ring[8:7]};
                    3'd2: rotated[8:0] = {ring[4:0], ring[8:5]};
                    3'd3: rotated[8:0] = {ring[0], ring[8:1]};
                    default: begin
                    end
                endcase
            end
            M64K_SHIFT_SIZE_WORD: begin
                case (selected_stage)
                    3'd0: rotated[16:0] = {ring[15:0], ring[16]};
                    3'd1: rotated[16:0] = {ring[14:0], ring[16:15]};
                    3'd2: rotated[16:0] = {ring[12:0], ring[16:13]};
                    3'd3: rotated[16:0] = {ring[8:0], ring[16:9]};
                    3'd4: rotated[16:0] = {ring[0], ring[16:1]};
                    default: begin
                    end
                endcase
            end
            M64K_SHIFT_SIZE_LONG: begin
                case (selected_stage)
                    3'd0: rotated[32:0] = {ring[31:0], ring[32]};
                    3'd1: rotated[32:0] = {ring[30:0], ring[32:31]};
                    3'd2: rotated[32:0] = {ring[28:0], ring[32:29]};
                    3'd3: rotated[32:0] = {ring[24:0], ring[32:25]};
                    3'd4: rotated[32:0] = {ring[16:0], ring[32:17]};
                    3'd5: rotated[32:0] = {ring[0], ring[32:1]};
                    default: begin
                    end
                endcase
            end
            M64K_SHIFT_SIZE_QUAD: begin
                case (selected_stage)
                    3'd0: rotated = {ring[63:0], ring[64]};
                    3'd1: rotated = {ring[62:0], ring[64:63]};
                    3'd2: rotated = {ring[60:0], ring[64:61]};
                    3'd3: rotated = {ring[56:0], ring[64:57]};
                    3'd4: rotated = {ring[48:0], ring[64:49]};
                    3'd5: rotated = {ring[32:0], ring[64:33]};
                    default: begin
                    end
                endcase
            end
        endcase

        return rotated;
    endfunction

    function automatic logic [64:0] reverse_ring(
        input logic [64:0] ring,
        input m64k_shift_size_t operand_size
    );
        logic [64:0] reversed;

        reversed = ring;

        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: begin
                for (int unsigned bit_index = 0; bit_index < 9; bit_index++) begin
                    reversed[bit_index] = ring[8 - bit_index];
                end
            end
            M64K_SHIFT_SIZE_WORD: begin
                for (int unsigned bit_index = 0; bit_index < 17; bit_index++) begin
                    reversed[bit_index] = ring[16 - bit_index];
                end
            end
            M64K_SHIFT_SIZE_LONG: begin
                for (int unsigned bit_index = 0; bit_index < 33; bit_index++) begin
                    reversed[bit_index] = ring[32 - bit_index];
                end
            end
            M64K_SHIFT_SIZE_QUAD: begin
                for (int unsigned bit_index = 0; bit_index < 65; bit_index++) begin
                    reversed[bit_index] = ring[64 - bit_index];
                end
            end
        endcase

        return reversed;
    endfunction

    always_comb begin
        incoming_request_squashed = squash_valid && squash.tag == request.tag;
        active_operation_squashed = squash_valid && squash.tag == operation_tag;
        request_ready = state == ROTATE_EXTEND_IDLE;
        response_valid = state == ROTATE_EXTEND_RESPONSE;

        rotated_ring = ring_state;
        if (effective_count[stage_index]) begin
            rotated_ring = rotate_left_stage(ring_state, operation_size, stage_index);
        end

        architectural_ring = operation_direction == M64K_ROTATE_EXTEND_RIGHT
            ? reverse_ring(rotated_ring, operation_size)
            : rotated_ring;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            state <= ROTATE_EXTEND_IDLE;
            operation_tag <= '0;
            operation_size <= M64K_SHIFT_SIZE_BYTE;
            operation_direction <= M64K_ROTATE_EXTEND_LEFT;
            operation_update_flags <= 1'b0;
            effective_count <= 6'd0;
            stage_index <= 3'd0;
            ring_state <= 65'd0;
            response <= '0;
        end else begin
            case (state)
                ROTATE_EXTEND_IDLE: begin
                    if (request_valid && request_ready && !incoming_request_squashed) begin
                        operation_tag <= request.tag;
                        operation_size <= request.operand_size;
                        operation_direction <= request.direction;
                        operation_update_flags <= request.update_flags;
                        effective_count <= reduce_rotate_count(request.count, request.operand_size);
                        stage_index <= 3'd0;
                        if (request.direction == M64K_ROTATE_EXTEND_RIGHT) begin
                            ring_state <= reverse_ring(make_ring(request.source, request.extend_in, request.operand_size), request.operand_size);
                        end else begin
                            ring_state <= make_ring(request.source, request.extend_in, request.operand_size);
                        end
                        state <= ROTATE_EXTEND_ITERATE;
                    end
                end
                ROTATE_EXTEND_ITERATE: begin
                    if (active_operation_squashed) begin
                        state <= ROTATE_EXTEND_IDLE;
                    end else begin
                        ring_state <= rotated_ring;

                        if (stage_index == 3'd5) begin
                            response <= '0;
                            response.tag <= operation_tag;
                            response.flags_valid <= operation_update_flags;
                            response.overflow <= 1'b0;
                            response.carry <= architectural_ring[0];
                            response.extend_valid <= 1'b1;
                            response.extend_out <= architectural_ring[0];

                            case (operation_size)
                                M64K_SHIFT_SIZE_BYTE: begin
                                    response.result <= {56'd0, architectural_ring[8:1]};
                                    response.negative <= architectural_ring[8];
                                    response.zero <= architectural_ring[8:1] == 8'd0;
                                end
                                M64K_SHIFT_SIZE_WORD: begin
                                    response.result <= {48'd0, architectural_ring[16:1]};
                                    response.negative <= architectural_ring[16];
                                    response.zero <= architectural_ring[16:1] == 16'd0;
                                end
                                M64K_SHIFT_SIZE_LONG: begin
                                    response.result <= {32'd0, architectural_ring[32:1]};
                                    response.negative <= architectural_ring[32];
                                    response.zero <= architectural_ring[32:1] == 32'd0;
                                end
                                M64K_SHIFT_SIZE_QUAD: begin
                                    response.result <= architectural_ring[64:1];
                                    response.negative <= architectural_ring[64];
                                    response.zero <= architectural_ring[64:1] == 64'd0;
                                end
                            endcase

                            state <= ROTATE_EXTEND_RESPONSE;
                        end else begin
                            stage_index <= stage_index + 3'd1;
                        end
                    end
                end
                ROTATE_EXTEND_RESPONSE: begin
                    if (response_ready) begin
                        state <= ROTATE_EXTEND_IDLE;
                    end
                end
                default: begin
                    state <= ROTATE_EXTEND_IDLE;
                end
            endcase
        end
    end

endmodule
