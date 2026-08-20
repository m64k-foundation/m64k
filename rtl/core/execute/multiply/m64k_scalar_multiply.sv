// Four-register throughput-one scalar multiplier implementing M64K-v1.scalar-multiply-divide.
//
// The datapath tiles the full 64-by-64 product into four parallel 32-by-32 partial products. A registered reduction stage combines the cross products and applies the Q-form two's-complement high-half correction. B/W/L inputs are zero-extended before entering the multiplier so unused upper and cross lanes see constant zero and can be structurally isolated by synthesis; this is operand isolation, not logic-generated clock gating. The final registered stage reconstructs signed sub-Q products from their exact 2W-bit patterns and formats the architectural result. No request reaches a response through a combinational single-cycle path.
module m64k_scalar_multiply (
    input  logic clock,
    input  logic reset,
    input  logic request_valid,
    output logic request_ready,
    input  m64k_scalar_multiply_pkg::m64k_multiply_request_t request,
    output logic response_valid,
    input  logic response_ready,
    output m64k_scalar_multiply_pkg::m64k_multiply_response_t response,
    input  logic squash_valid,
    input  m64k_scalar_multiply_pkg::m64k_multiply_squash_t squash
);
    import m64k_execute_backend_pkg::*;
    import m64k_scalar_multiply_pkg::*;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] operand_left;
        logic [63:0] operand_right;
        m64k_multiply_size_t operand_size;
        logic signed_operation;
        logic widening;
        logic update_flags;
    } operand_stage_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] operand_left;
        logic [63:0] operand_right;
        logic [63:0] partial_low_low;
        logic [63:0] partial_low_high;
        logic [63:0] partial_high_low;
        logic [63:0] partial_high_high;
        m64k_multiply_size_t operand_size;
        logic signed_operation;
        logic widening;
        logic update_flags;
    } partial_product_stage_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] operand_left;
        logic [63:0] operand_right;
        logic [63:0] partial_low_low;
        logic [64:0] cross_sum;
        logic [63:0] corrected_partial_high_high;
        m64k_multiply_size_t operand_size;
        logic signed_operation;
        logic widening;
        logic update_flags;
    } reduction_stage_t;

    function automatic logic [63:0] prepare_operand(
        input logic [63:0] source,
        input m64k_multiply_size_t operand_size
    );
        case (operand_size)
            M64K_MULTIPLY_SIZE_BYTE: return {56'd0, source[7:0]};
            M64K_MULTIPLY_SIZE_WORD: return {48'd0, source[15:0]};
            M64K_MULTIPLY_SIZE_LONG: return {32'd0, source[31:0]};
            M64K_MULTIPLY_SIZE_QUAD: return source;
            default: return source;
        endcase
    endfunction

    logic operand_stage_valid;
    operand_stage_t operand_stage;
    logic partial_product_stage_valid;
    partial_product_stage_t partial_product_stage;
    logic reduction_stage_valid;
    reduction_stage_t reduction_stage;
    logic result_stage_valid;
    m64k_multiply_response_t result_stage;

    logic pipeline_advances;
    logic incoming_request_squashed;
    logic operand_stage_squashed;
    logic partial_product_stage_squashed;
    logic reduction_stage_squashed;
    logic request_accepts;

    partial_product_stage_t calculated_partial_products;
    reduction_stage_t calculated_reduction;
    logic [63:0] signed_high_correction_left;
    logic [63:0] signed_high_correction_right;
    logic [64:0] calculated_low_sum;
    logic [63:0] calculated_high_sum;
    logic [127:0] calculated_full_product;
    logic [127:0] semantic_product;
    logic [15:0] corrected_byte_product;
    logic [31:0] corrected_word_product;
    logic [63:0] corrected_long_product;
    m64k_multiply_response_t calculated_response;

    always_comb begin
        pipeline_advances = !result_stage_valid || response_ready;
        request_ready = pipeline_advances;
        response_valid = result_stage_valid;
        response = result_stage;

        incoming_request_squashed = squash_valid && request.tag == squash.tag;
        operand_stage_squashed = squash_valid && operand_stage_valid && operand_stage.tag == squash.tag;
        partial_product_stage_squashed = squash_valid && partial_product_stage_valid && partial_product_stage.tag == squash.tag;
        reduction_stage_squashed = squash_valid && reduction_stage_valid && reduction_stage.tag == squash.tag;
        request_accepts = request_valid && request_ready && !incoming_request_squashed;
    end

    always_comb begin
        calculated_partial_products = '0;
        calculated_partial_products.tag = operand_stage.tag;
        calculated_partial_products.operand_left = operand_stage.operand_left;
        calculated_partial_products.operand_right = operand_stage.operand_right;
        calculated_partial_products.partial_low_low = operand_stage.operand_left[31:0] * operand_stage.operand_right[31:0];
        calculated_partial_products.partial_low_high = operand_stage.operand_left[31:0] * operand_stage.operand_right[63:32];
        calculated_partial_products.partial_high_low = operand_stage.operand_left[63:32] * operand_stage.operand_right[31:0];
        calculated_partial_products.partial_high_high = operand_stage.operand_left[63:32] * operand_stage.operand_right[63:32];
        calculated_partial_products.operand_size = operand_stage.operand_size;
        calculated_partial_products.signed_operation = operand_stage.signed_operation;
        calculated_partial_products.widening = operand_stage.widening;
        calculated_partial_products.update_flags = operand_stage.update_flags;
    end

    always_comb begin
        signed_high_correction_left = 64'd0;
        signed_high_correction_right = 64'd0;
        if (partial_product_stage.signed_operation && partial_product_stage.operand_left[63]) begin
            signed_high_correction_left = partial_product_stage.operand_right;
        end
        if (partial_product_stage.signed_operation && partial_product_stage.operand_right[63]) begin
            signed_high_correction_right = partial_product_stage.operand_left;
        end

        calculated_reduction = '0;
        calculated_reduction.tag = partial_product_stage.tag;
        calculated_reduction.operand_left = partial_product_stage.operand_left;
        calculated_reduction.operand_right = partial_product_stage.operand_right;
        calculated_reduction.partial_low_low = partial_product_stage.partial_low_low;
        calculated_reduction.cross_sum = {1'b0, partial_product_stage.partial_low_high} + {1'b0, partial_product_stage.partial_high_low};
        calculated_reduction.corrected_partial_high_high = partial_product_stage.partial_high_high - signed_high_correction_left - signed_high_correction_right;
        calculated_reduction.operand_size = partial_product_stage.operand_size;
        calculated_reduction.signed_operation = partial_product_stage.signed_operation;
        calculated_reduction.widening = partial_product_stage.widening;
        calculated_reduction.update_flags = partial_product_stage.update_flags;
    end

    always_comb begin
        calculated_low_sum = {1'b0, reduction_stage.partial_low_low} + {1'b0, reduction_stage.cross_sum[31:0], 32'd0};
        calculated_high_sum = reduction_stage.corrected_partial_high_high + {31'd0, reduction_stage.cross_sum[64:32]} + 64'(calculated_low_sum[64]);
        calculated_full_product = {calculated_high_sum, calculated_low_sum[63:0]};

        corrected_byte_product = calculated_full_product[15:0];
        corrected_word_product = calculated_full_product[31:0];
        corrected_long_product = calculated_full_product[63:0];
        if (reduction_stage.signed_operation) begin
            if (reduction_stage.operand_left[7]) begin
                corrected_byte_product = corrected_byte_product - {reduction_stage.operand_right[7:0], 8'd0};
            end
            if (reduction_stage.operand_right[7]) begin
                corrected_byte_product = corrected_byte_product - {reduction_stage.operand_left[7:0], 8'd0};
            end
            if (reduction_stage.operand_left[15]) begin
                corrected_word_product = corrected_word_product - {reduction_stage.operand_right[15:0], 16'd0};
            end
            if (reduction_stage.operand_right[15]) begin
                corrected_word_product = corrected_word_product - {reduction_stage.operand_left[15:0], 16'd0};
            end
            if (reduction_stage.operand_left[31]) begin
                corrected_long_product = corrected_long_product - {reduction_stage.operand_right[31:0], 32'd0};
            end
            if (reduction_stage.operand_right[31]) begin
                corrected_long_product = corrected_long_product - {reduction_stage.operand_left[31:0], 32'd0};
            end
        end

        semantic_product = calculated_full_product;
        if (reduction_stage.signed_operation) begin
            case (reduction_stage.operand_size)
                M64K_MULTIPLY_SIZE_BYTE: semantic_product = {{112{corrected_byte_product[15]}}, corrected_byte_product};
                M64K_MULTIPLY_SIZE_WORD: semantic_product = {{96{corrected_word_product[31]}}, corrected_word_product};
                M64K_MULTIPLY_SIZE_LONG: semantic_product = {{64{corrected_long_product[63]}}, corrected_long_product};
                M64K_MULTIPLY_SIZE_QUAD: semantic_product = calculated_full_product;
                default: semantic_product = calculated_full_product;
            endcase
        end

        calculated_response = '0;
        calculated_response.tag = reduction_stage.tag;
        calculated_response.result_count = 2'd1;
        calculated_response.results[0].valid = 1'b1;
        calculated_response.results[0].role = M64K_EXECUTE_RESULT_LOW;
        calculated_response.results[1].role = M64K_EXECUTE_RESULT_HIGH;
        calculated_response.flags_valid = reduction_stage.update_flags;

        case (reduction_stage.operand_size)
            M64K_MULTIPLY_SIZE_BYTE: begin
                if (reduction_stage.widening) begin
                    calculated_response.results[0].value = {48'd0, semantic_product[15:0]};
                    calculated_response.negative = semantic_product[15];
                    calculated_response.zero = semantic_product[15:0] == 16'd0;
                end else begin
                    calculated_response.results[0].value = {56'd0, semantic_product[7:0]};
                    calculated_response.negative = semantic_product[7];
                    calculated_response.zero = semantic_product[7:0] == 8'd0;
                    if (reduction_stage.signed_operation) begin
                        calculated_response.overflow = semantic_product[127:8] != {120{semantic_product[7]}};
                    end else begin
                        calculated_response.overflow = semantic_product[127:8] != 120'd0;
                    end
                end
            end
            M64K_MULTIPLY_SIZE_WORD: begin
                if (reduction_stage.widening) begin
                    calculated_response.results[0].value = {32'd0, semantic_product[31:0]};
                    calculated_response.negative = semantic_product[31];
                    calculated_response.zero = semantic_product[31:0] == 32'd0;
                end else begin
                    calculated_response.results[0].value = {48'd0, semantic_product[15:0]};
                    calculated_response.negative = semantic_product[15];
                    calculated_response.zero = semantic_product[15:0] == 16'd0;
                    if (reduction_stage.signed_operation) begin
                        calculated_response.overflow = semantic_product[127:16] != {112{semantic_product[15]}};
                    end else begin
                        calculated_response.overflow = semantic_product[127:16] != 112'd0;
                    end
                end
            end
            M64K_MULTIPLY_SIZE_LONG: begin
                if (reduction_stage.widening) begin
                    calculated_response.results[0].value = semantic_product[63:0];
                    calculated_response.negative = semantic_product[63];
                    calculated_response.zero = semantic_product[63:0] == 64'd0;
                end else begin
                    calculated_response.results[0].value = {32'd0, semantic_product[31:0]};
                    calculated_response.negative = semantic_product[31];
                    calculated_response.zero = semantic_product[31:0] == 32'd0;
                    if (reduction_stage.signed_operation) begin
                        calculated_response.overflow = semantic_product[127:32] != {96{semantic_product[31]}};
                    end else begin
                        calculated_response.overflow = semantic_product[127:32] != 96'd0;
                    end
                end
            end
            M64K_MULTIPLY_SIZE_QUAD: begin
                calculated_response.results[0].value = semantic_product[63:0];
                if (reduction_stage.widening) begin
                    calculated_response.result_count = 2'd2;
                    calculated_response.results[1].valid = 1'b1;
                    calculated_response.results[1].value = semantic_product[127:64];
                    calculated_response.negative = semantic_product[127];
                    calculated_response.zero = semantic_product == 128'd0;
                end else begin
                    calculated_response.negative = semantic_product[63];
                    calculated_response.zero = semantic_product[63:0] == 64'd0;
                    if (reduction_stage.signed_operation) begin
                        calculated_response.overflow = semantic_product[127:64] != {64{semantic_product[63]}};
                    end else begin
                        calculated_response.overflow = semantic_product[127:64] != 64'd0;
                    end
                end
            end
            default: begin
                calculated_response = '0;
                calculated_response.tag = reduction_stage.tag;
            end
        endcase
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            operand_stage_valid <= 1'b0;
            operand_stage <= '0;
            partial_product_stage_valid <= 1'b0;
            partial_product_stage <= '0;
            reduction_stage_valid <= 1'b0;
            reduction_stage <= '0;
            result_stage_valid <= 1'b0;
            result_stage <= '0;
        end else if (pipeline_advances) begin
            result_stage_valid <= reduction_stage_valid && !reduction_stage_squashed;
            if (reduction_stage_valid && !reduction_stage_squashed) begin
                result_stage <= calculated_response;
            end

            reduction_stage_valid <= partial_product_stage_valid && !partial_product_stage_squashed;
            if (partial_product_stage_valid && !partial_product_stage_squashed) begin
                reduction_stage <= calculated_reduction;
            end

            partial_product_stage_valid <= operand_stage_valid && !operand_stage_squashed;
            if (operand_stage_valid && !operand_stage_squashed) begin
                partial_product_stage <= calculated_partial_products;
            end

            operand_stage_valid <= request_accepts;
            if (request_accepts) begin
                operand_stage.tag <= request.tag;
                operand_stage.operand_left <= prepare_operand(request.source_left, request.operand_size);
                operand_stage.operand_right <= prepare_operand(request.source_right, request.operand_size);
                operand_stage.operand_size <= request.operand_size;
                operand_stage.signed_operation <= request.signed_operation;
                operand_stage.widening <= request.widening;
                operand_stage.update_flags <= request.update_flags;
            end
        end else begin
            if (operand_stage_squashed) begin
                operand_stage_valid <= 1'b0;
            end
            if (partial_product_stage_squashed) begin
                partial_product_stage_valid <= 1'b0;
            end
            if (reduction_stage_squashed) begin
                reduction_stage_valid <= 1'b0;
            end
        end
    end

endmodule
