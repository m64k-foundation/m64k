module m64k_scalar_multiply_tb;
    import m64k_arch_types_pkg::*;
    import m64k_execute_backend_pkg::*;
    import m64k_scalar_multiply_pkg::*;

    logic clock;
    logic reset;
    logic request_valid;
    logic request_ready;
    m64k_multiply_request_t request;
    logic response_valid;
    logic response_ready;
    m64k_multiply_response_t response;
    logic squash_valid;
    m64k_multiply_squash_t squash;
    m64k_backend_allocation_sequence_t next_identity;
    logic [31:0] checked_operations;

    m64k_scalar_multiply dut (.*);

    function automatic logic [63:0] reference_prepare_operand(
        input logic [63:0] source,
        input m64k_multiply_size_t operand_size,
        input logic signed_operation
    );
        case (operand_size)
            M64K_MULTIPLY_SIZE_BYTE: begin
                return signed_operation ? {{56{source[7]}}, source[7:0]} : {56'd0, source[7:0]};
            end
            M64K_MULTIPLY_SIZE_WORD: begin
                return signed_operation ? {{48{source[15]}}, source[15:0]} : {48'd0, source[15:0]};
            end
            M64K_MULTIPLY_SIZE_LONG: begin
                return signed_operation ? {{32{source[31]}}, source[31:0]} : {32'd0, source[31:0]};
            end
            M64K_MULTIPLY_SIZE_QUAD: begin
                return source;
            end
            default: begin
                return source;
            end
        endcase
    endfunction

    function automatic m64k_multiply_response_t reference_multiply(input m64k_multiply_request_t selected_request);
        m64k_multiply_response_t expected;
        logic [63:0] prepared_left;
        logic [63:0] prepared_right;
        logic signed [63:0] signed_left;
        logic signed [63:0] signed_right;
        logic signed [127:0] signed_product;
        logic [127:0] product;

        prepared_left = reference_prepare_operand(selected_request.source_left, selected_request.operand_size, selected_request.signed_operation);
        prepared_right = reference_prepare_operand(selected_request.source_right, selected_request.operand_size, selected_request.signed_operation);
        signed_left = $signed(prepared_left);
        signed_right = $signed(prepared_right);
        signed_product = signed_left * signed_right;
        product = selected_request.signed_operation ? $unsigned(signed_product) : prepared_left * prepared_right;

        expected = '0;
        expected.tag = selected_request.tag;
        expected.result_count = 2'd1;
        expected.results[0].valid = 1'b1;
        expected.results[0].role = M64K_EXECUTE_RESULT_LOW;
        expected.results[1].role = M64K_EXECUTE_RESULT_HIGH;
        expected.flags_valid = selected_request.update_flags;

        case (selected_request.operand_size)
            M64K_MULTIPLY_SIZE_BYTE: begin
                if (selected_request.widening) begin
                    expected.results[0].value = {48'd0, product[15:0]};
                    expected.negative = product[15];
                    expected.zero = product[15:0] == 16'd0;
                end else begin
                    expected.results[0].value = {56'd0, product[7:0]};
                    expected.negative = product[7];
                    expected.zero = product[7:0] == 8'd0;
                    if (selected_request.signed_operation) begin
                        expected.overflow = product[127:8] != {120{product[7]}};
                    end else begin
                        expected.overflow = product[127:8] != 120'd0;
                    end
                end
            end
            M64K_MULTIPLY_SIZE_WORD: begin
                if (selected_request.widening) begin
                    expected.results[0].value = {32'd0, product[31:0]};
                    expected.negative = product[31];
                    expected.zero = product[31:0] == 32'd0;
                end else begin
                    expected.results[0].value = {48'd0, product[15:0]};
                    expected.negative = product[15];
                    expected.zero = product[15:0] == 16'd0;
                    if (selected_request.signed_operation) begin
                        expected.overflow = product[127:16] != {112{product[15]}};
                    end else begin
                        expected.overflow = product[127:16] != 112'd0;
                    end
                end
            end
            M64K_MULTIPLY_SIZE_LONG: begin
                if (selected_request.widening) begin
                    expected.results[0].value = product[63:0];
                    expected.negative = product[63];
                    expected.zero = product[63:0] == 64'd0;
                end else begin
                    expected.results[0].value = {32'd0, product[31:0]};
                    expected.negative = product[31];
                    expected.zero = product[31:0] == 32'd0;
                    if (selected_request.signed_operation) begin
                        expected.overflow = product[127:32] != {96{product[31]}};
                    end else begin
                        expected.overflow = product[127:32] != 96'd0;
                    end
                end
            end
            M64K_MULTIPLY_SIZE_QUAD: begin
                expected.results[0].value = product[63:0];
                if (selected_request.widening) begin
                    expected.result_count = 2'd2;
                    expected.results[1].valid = 1'b1;
                    expected.results[1].value = product[127:64];
                    expected.negative = product[127];
                    expected.zero = product == 128'd0;
                end else begin
                    expected.negative = product[63];
                    expected.zero = product[63:0] == 64'd0;
                    if (selected_request.signed_operation) begin
                        expected.overflow = product[127:64] != {64{product[63]}};
                    end else begin
                        expected.overflow = product[127:64] != 64'd0;
                    end
                end
            end
            default: begin
                expected = '0;
                expected.tag = selected_request.tag;
            end
        endcase

        return expected;
    endfunction

    task automatic fail_response(
        input m64k_multiply_request_t selected_request,
        input m64k_multiply_response_t expected,
        input m64k_multiply_response_t observed
    );
        $fatal(
            1,
            "multiply mismatch: allocation=%0d rob=%0d generation=%0d uop=%0d size=%s signed=%0b widening=%0b F=%0b left=%016x right=%016x expected=%x observed=%x",
            selected_request.tag.allocation_sequence,
            selected_request.tag.rob_index,
            selected_request.tag.rob_generation,
            selected_request.tag.uop_index,
            selected_request.operand_size.name(),
            selected_request.signed_operation,
            selected_request.widening,
            selected_request.update_flags,
            selected_request.source_left,
            selected_request.source_right,
            expected,
            observed
        );
    endtask

    task automatic make_request(
        output m64k_multiply_request_t selected_request,
        input logic [63:0] source_left,
        input logic [63:0] source_right,
        input m64k_multiply_size_t operand_size,
        input logic signed_operation,
        input logic widening,
        input logic update_flags
    );
        selected_request = '0;
        selected_request.tag.execution_context.core_id = 6'd3;
        selected_request.tag.execution_context.hardware_thread_id = 2'd1;
        selected_request.tag.rob_index = next_identity[7:0];
        selected_request.tag.rob_generation = next_identity[15:8];
        selected_request.tag.allocation_sequence = next_identity;
        selected_request.tag.uop_index = next_identity[3:0];
        selected_request.source_left = source_left;
        selected_request.source_right = source_right;
        selected_request.operand_size = operand_size;
        selected_request.signed_operation = signed_operation;
        selected_request.widening = widening;
        selected_request.update_flags = update_flags;
        next_identity = next_identity + 64'd1;
    endtask

    task automatic issue_and_check(input m64k_multiply_request_t selected_request);
        m64k_multiply_response_t expected;

        expected = reference_multiply(selected_request);
        @(negedge clock);
        request = selected_request;
        request_valid = 1'b1;
        response_ready = 1'b1;

        do begin
            @(posedge clock);
        end while (!request_ready);

        @(negedge clock);
        request_valid = 1'b0;

        while (!response_valid) begin
            @(negedge clock);
        end

        if (response !== expected) begin
            fail_response(selected_request, expected, response);
        end

        checked_operations = checked_operations + 32'd1;
        @(posedge clock);
        @(negedge clock);
    endtask

    task automatic check_exhaustive_byte;
        m64k_multiply_request_t selected_request;

        for (integer unsigned signed_index = 0; signed_index < 2; signed_index++) begin
            for (integer unsigned widening_index = 0; widening_index < 2; widening_index++) begin
                for (integer unsigned left_value = 0; left_value < 256; left_value++) begin
                    for (integer unsigned right_value = 0; right_value < 256; right_value++) begin
                        make_request(
                            selected_request,
                            64'(left_value),
                            64'(right_value),
                            M64K_MULTIPLY_SIZE_BYTE,
                            1'(signed_index),
                            1'(widening_index),
                            1'b1
                        );
                        issue_and_check(selected_request);
                    end
                end
            end
        end
    endtask

    task automatic check_wide_boundaries;
        m64k_multiply_request_t selected_request;
        logic [63:0] values [0:9];

        values[0] = 64'd0;
        values[1] = 64'd1;
        values[2] = 64'd2;
        values[3] = 64'h0000_0000_0000_7fff;
        values[4] = 64'h0000_0000_0000_8000;
        values[5] = 64'h0000_0000_ffff_ffff;
        values[6] = 64'h0000_0000_8000_0000;
        values[7] = 64'h7fff_ffff_ffff_ffff;
        values[8] = 64'h8000_0000_0000_0000;
        values[9] = 64'hffff_ffff_ffff_ffff;

        for (integer unsigned size_index = 1; size_index < 4; size_index++) begin
            for (integer unsigned signed_index = 0; signed_index < 2; signed_index++) begin
                for (integer unsigned widening_index = 0; widening_index < 2; widening_index++) begin
                    for (integer unsigned left_index = 0; left_index < 10; left_index++) begin
                        for (integer unsigned right_index = 0; right_index < 10; right_index++) begin
                            make_request(
                                selected_request,
                                values[left_index],
                                values[right_index],
                                m64k_multiply_size_t'(size_index),
                                1'(signed_index),
                                1'(widening_index),
                                1'b1
                            );
                            issue_and_check(selected_request);
                        end
                    end
                end
            end
        end

        make_request(selected_request, 64'hffff_ffff_ffff_ffff, 64'd2, M64K_MULTIPLY_SIZE_QUAD, 1'b1, 1'b1, 1'b0);
        issue_and_check(selected_request);
    endtask

    task automatic check_backpressure_and_atomic_response;
        m64k_multiply_request_t selected_request;
        m64k_multiply_response_t expected;
        m64k_multiply_response_t held_response;

        make_request(
            selected_request,
            64'hffff_ffff_ffff_fffe,
            64'h8000_0000_0000_0001,
            M64K_MULTIPLY_SIZE_QUAD,
            1'b1,
            1'b1,
            1'b1
        );
        expected = reference_multiply(selected_request);

        @(negedge clock);
        response_ready = 1'b0;
        request = selected_request;
        request_valid = 1'b1;
        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;

        while (!response_valid) begin
            @(negedge clock);
        end
        held_response = response;

        repeat (7) begin
            @(posedge clock);
            @(negedge clock);
            if (!response_valid || response !== held_response) begin
                $fatal(1, "response changed while blocked: expected=%x observed=%x valid=%0b", held_response, response, response_valid);
            end
        end

        if (held_response !== expected || held_response.result_count != 2'd2) begin
            fail_response(selected_request, expected, held_response);
        end

        response_ready = 1'b1;
        @(posedge clock);
        @(negedge clock);
    endtask

    task automatic check_throughput_one;
        m64k_multiply_request_t selected_requests [0:3];
        m64k_multiply_response_t expected_responses [0:3];

        for (integer unsigned request_index = 0; request_index < 4; request_index++) begin
            make_request(
                selected_requests[request_index],
                64'h1020_3040_5060_7080 + 64'(request_index),
                64'h8877_6655_4433_2211 - 64'(request_index),
                M64K_MULTIPLY_SIZE_QUAD,
                1'(request_index[0]),
                1'b1,
                1'b1
            );
            expected_responses[request_index] = reference_multiply(selected_requests[request_index]);
        end

        response_ready = 1'b0;
        for (integer unsigned request_index = 0; request_index < 4; request_index++) begin
            @(negedge clock);
            request = selected_requests[request_index];
            request_valid = 1'b1;
            @(posedge clock);
            if (!request_ready) begin
                $fatal(1, "throughput-one pipeline rejected request %0d", request_index);
            end
        end

        @(negedge clock);
        request_valid = 1'b0;
        while (!response_valid) begin
            @(negedge clock);
        end

        response_ready = 1'b1;
        for (integer unsigned response_index = 0; response_index < 4; response_index++) begin
            if (!response_valid) begin
                $fatal(1, "bubble appeared between throughput-one responses at index %0d", response_index);
            end
            if (response !== expected_responses[response_index]) begin
                fail_response(selected_requests[response_index], expected_responses[response_index], response);
            end
            @(posedge clock);
            @(negedge clock);
        end
    endtask

    task automatic check_squash;
        m64k_multiply_request_t selected_request;
        m64k_multiply_response_t held_response;

        make_request(selected_request, 64'h0123_4567_89ab_cdef, 64'hfedc_ba98_7654_3210, M64K_MULTIPLY_SIZE_QUAD, 1'b0, 1'b1, 1'b1);

        @(negedge clock);
        response_ready = 1'b0;
        request = selected_request;
        request_valid = 1'b1;
        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;

        while (!response_valid) begin
            @(negedge clock);
        end
        held_response = response;

        squash.tag = selected_request.tag;
        squash_valid = 1'b1;
        #1;
        if (!response_valid || response !== held_response) begin
            $fatal(1, "squash retracted or changed an irrevocable held response");
        end

        @(posedge clock);
        @(negedge clock);
        squash_valid = 1'b0;
        response_ready = 1'b1;
        @(posedge clock);
        @(negedge clock);
        if (response_valid) begin
            $fatal(1, "accepted response remained valid");
        end

        make_request(selected_request, 64'h1111_2222_3333_4444, 64'h5555_6666_7777_8888, M64K_MULTIPLY_SIZE_QUAD, 1'b0, 1'b1, 1'b1);
        request = selected_request;
        request_valid = 1'b1;
        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;
        squash.tag = selected_request.tag;
        squash_valid = 1'b1;
        @(posedge clock);
        @(negedge clock);
        squash_valid = 1'b0;

        repeat (6) begin
            @(posedge clock);
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "pending squashed operation produced a response");
            end
        end

        make_request(selected_request, 64'h0123_4567_89ab_cdef, 64'hfedc_ba98_7654_3210, M64K_MULTIPLY_SIZE_QUAD, 1'b0, 1'b1, 1'b1);
        request = selected_request;
        request_valid = 1'b1;
        squash.tag = selected_request.tag;
        squash_valid = 1'b1;
        #1;
        if (!request_ready) begin
            $fatal(1, "pipeline did not accept a same-cycle squashed request handshake");
        end
        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;
        squash_valid = 1'b0;

        repeat (4) begin
            @(posedge clock);
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "same-cycle squashed request produced a response");
            end
        end
    endtask

    task automatic check_pending_stage_squash(
        input integer unsigned stage_advances,
        input logic [63:0] distinguishing_value
    );
        m64k_multiply_request_t selected_request;

        make_request(selected_request, distinguishing_value, 64'h9e37_79b9_7f4a_7c15, M64K_MULTIPLY_SIZE_QUAD, 1'b1, 1'b1, 1'b1);
        @(negedge clock);
        request = selected_request;
        request_valid = 1'b1;
        response_ready = 1'b1;
        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;

        repeat (stage_advances) begin
            @(posedge clock);
            @(negedge clock);
        end

        squash.tag = selected_request.tag;
        squash_valid = 1'b1;
        @(posedge clock);
        @(negedge clock);
        squash_valid = 1'b0;

        repeat (7) begin
            @(posedge clock);
            @(negedge clock);
            if (response_valid && response.tag == selected_request.tag) begin
                $fatal(1, "stage-%0d squashed tag produced a response: tag=%x", stage_advances, selected_request.tag);
            end
        end
    endtask

    task automatic check_exact_tag_squash_among_inflight;
        m64k_multiply_request_t selected_requests [0:2];
        m64k_multiply_response_t expected_first;
        m64k_multiply_response_t expected_third;
        integer unsigned observed_count;

        for (integer unsigned request_index = 0; request_index < 3; request_index++) begin
            make_request(
                selected_requests[request_index],
                64'ha100_0000_0000_0000 + 64'(request_index),
                64'h0000_0000_0000_0101 + 64'(request_index),
                M64K_MULTIPLY_SIZE_QUAD,
                1'b0,
                1'b1,
                1'b1
            );
        end
        expected_first = reference_multiply(selected_requests[0]);
        expected_third = reference_multiply(selected_requests[2]);

        response_ready = 1'b1;
        for (integer unsigned request_index = 0; request_index < 3; request_index++) begin
            @(negedge clock);
            request = selected_requests[request_index];
            request_valid = 1'b1;
            @(posedge clock);
            if (!request_ready) begin
                $fatal(1, "multi-inflight setup rejected request %0d", request_index);
            end
        end

        @(negedge clock);
        request_valid = 1'b0;
        squash.tag = selected_requests[1].tag;
        squash_valid = 1'b1;
        @(posedge clock);
        @(negedge clock);
        squash_valid = 1'b0;

        observed_count = 0;
        repeat (9) begin
            if (response_valid) begin
                if (response.tag == selected_requests[1].tag) begin
                    $fatal(1, "middle squashed tag escaped from multi-inflight pipeline");
                end
                if (observed_count == 0 && response !== expected_first) begin
                    fail_response(selected_requests[0], expected_first, response);
                end
                if (observed_count == 1 && response !== expected_third) begin
                    fail_response(selected_requests[2], expected_third, response);
                end
                observed_count++;
            end
            @(posedge clock);
            @(negedge clock);
        end

        if (observed_count != 2) begin
            $fatal(1, "multi-inflight squash scoreboard observed %0d responses instead of 2", observed_count);
        end
    endtask

    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    initial begin
        reset = 1'b1;
        request_valid = 1'b0;
        request = '0;
        response_ready = 1'b0;
        squash_valid = 1'b0;
        squash = '0;
        next_identity = 64'd1;
        checked_operations = 32'd0;

        repeat (3) begin
            @(posedge clock);
        end
        @(negedge clock);
        reset = 1'b0;

        check_exhaustive_byte();
        if (checked_operations != 32'd262144) begin
            $fatal(1, "exhaustive byte matrix executed %0d cases instead of 262144", checked_operations);
        end
        check_wide_boundaries();
        check_throughput_one();
        check_backpressure_and_atomic_response();
        check_squash();
        check_pending_stage_squash(0, 64'h0000_0000_0000_0101);
        check_pending_stage_squash(1, 64'h0000_0000_0000_0202);
        check_pending_stage_squash(2, 64'h0000_0000_0000_0303);
        check_exact_tag_squash_among_inflight();

        $display("M64K scalar multiplier passed exhaustive byte, wide boundary, backpressure, squash, and atomic-result verification");
        $finish;
    end
endmodule
