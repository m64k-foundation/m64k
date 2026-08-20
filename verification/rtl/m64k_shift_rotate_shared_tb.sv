module m64k_shift_rotate_shared_tb;
    import m64k_arch_types_pkg::*;
    import m64k_execute_backend_pkg::*;
    import m64k_shift_rotate_pkg::*;
    import m64k_shift_rotate_shared_pkg::*;

    logic clock;
    logic reset;
    logic request_valid;
    logic request_ready;
    m64k_shift_rotate_shared_request_t request;
    logic squash_valid;
    m64k_shift_rotate_shared_squash_t squash;
    logic response_valid;
    logic response_ready;
    m64k_shift_rotate_shared_response_t response;

    logic [63:0] reference_result;
    logic reference_result_valid;
    logic reference_negative;
    logic reference_zero;
    logic reference_overflow;
    logic reference_carry;
    logic reference_flags_valid;
    logic reference_extend_out;
    logic reference_extend_valid;

    logic [M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH-1:0] allocation_sequence;

    m64k_shift_rotate_shared dut (.*);

    m64k_shift_rotate reference (
        .source(request.source),
        .count(request.count),
        .operand_size(request.operand_size),
        .operation(request.operation),
        .extend_in(request.extend_in),
        .update_flags(request.update_flags),
        .result(reference_result),
        .result_valid(reference_result_valid),
        .negative(reference_negative),
        .zero(reference_zero),
        .overflow(reference_overflow),
        .carry(reference_carry),
        .flags_valid(reference_flags_valid),
        .extend_out(reference_extend_out),
        .extend_valid(reference_extend_valid)
    );

    always #1 clock = ~clock;

    function automatic int unsigned operand_width(input m64k_shift_size_t selected_size);
        case (selected_size)
            M64K_SHIFT_SIZE_BYTE: return 8;
            M64K_SHIFT_SIZE_WORD: return 16;
            M64K_SHIFT_SIZE_LONG: return 32;
            M64K_SHIFT_SIZE_QUAD: return 64;
        endcase
    endfunction

    function automatic logic [64:0] repeated_rox_oracle(
        input logic [63:0] source,
        input logic extend_in,
        input logic [5:0] count,
        input m64k_shift_size_t selected_size,
        input logic rotate_right
    );
        logic [64:0] ring;
        int unsigned width;
        int unsigned reduced_count;

        width = operand_width(selected_size);
        ring = 65'd0;
        ring[0] = extend_in;
        for (int unsigned bit_index = 0; bit_index < width; bit_index++) begin
            ring[bit_index + 1] = source[bit_index];
        end

        reduced_count = int'(count) % (width + 1);
        for (int unsigned step = 0; step < reduced_count; step++) begin
            if (rotate_right) begin
                logic wrap_bit;

                wrap_bit = ring[0];
                for (int unsigned bit_index = 0; bit_index < width; bit_index++) begin
                    ring[bit_index] = ring[bit_index + 1];
                end
                ring[width] = wrap_bit;
            end else begin
                logic wrap_bit;

                wrap_bit = ring[width];
                for (int unsigned bit_index = width; bit_index > 0; bit_index--) begin
                    ring[bit_index] = ring[bit_index - 1];
                end
                ring[0] = wrap_bit;
            end
        end

        return ring;
    endfunction

    task automatic allocate_tag;
        request.tag = '0;
        request.tag.execution_context.core_id = allocation_sequence[M64K_CORE_ID_WIDTH-1:0];
        request.tag.execution_context.hardware_thread_id = allocation_sequence[M64K_HARDWARE_THREAD_ID_WIDTH-1:0];
        request.tag.rob_index = allocation_sequence[M64K_BACKEND_ROB_INDEX_WIDTH-1:0];
        request.tag.rob_generation = allocation_sequence[M64K_BACKEND_ROB_GENERATION_WIDTH-1:0] ^ 8'hc3;
        request.tag.allocation_sequence = allocation_sequence;
        request.tag.uop_index = allocation_sequence[M64K_BACKEND_UOP_INDEX_WIDTH-1:0];
        allocation_sequence++;
    endtask

    task automatic transact_and_check;
        m64k_shift_rotate_shared_response_t expected;
        logic [64:0] expected_ring;
        int unsigned width;
        int unsigned execution_waits;

        expected = '0;
        expected.tag = request.tag;
        width = operand_width(request.operand_size);

        if (request.operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR}) begin
            expected_ring = repeated_rox_oracle(
                request.source,
                request.extend_in,
                request.count,
                request.operand_size,
                request.operation == M64K_SHIFT_ROXR
            );
            expected.result = expected_ring[64:1];
            case (request.operand_size)
                M64K_SHIFT_SIZE_BYTE: expected.result = {56'd0, expected_ring[8:1]};
                M64K_SHIFT_SIZE_WORD: expected.result = {48'd0, expected_ring[16:1]};
                M64K_SHIFT_SIZE_LONG: expected.result = {32'd0, expected_ring[32:1]};
                M64K_SHIFT_SIZE_QUAD: expected.result = expected_ring[64:1];
            endcase
            expected.flags_valid = request.update_flags;
            expected.negative = expected.result[width - 1];
            expected.zero = expected.result == 64'd0;
            expected.overflow = 1'b0;
            expected.carry = expected_ring[0];
            expected.extend_valid = 1'b1;
            expected.extend_out = expected_ring[0];
        end else begin
            #1;
            if (!reference_result_valid) begin
                $fatal(1, "complete reference rejected a legal ordinary shift/rotate operation");
            end
            expected.result = reference_result;
            expected.flags_valid = reference_flags_valid;
            expected.negative = reference_negative;
            expected.zero = reference_zero;
            expected.overflow = reference_overflow;
            expected.carry = reference_carry;
            expected.extend_valid = reference_extend_valid;
            expected.extend_out = reference_extend_out;
        end

        @(negedge clock);
        if (!request_ready) begin
            $fatal(1, "shared shift/rotate candidate was not ready before an isolated request");
        end
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;

        execution_waits = 0;
        while (!response_valid) begin
            @(negedge clock);
            execution_waits++;
        end

        if (execution_waits != (request.operation inside {M64K_SHIFT_ROXL, M64K_SHIFT_ROXR} ? 1 : 0)) begin
            $fatal(1, "shared shift/rotate latency mismatch operation=%s waits=%0d", request.operation.name(), execution_waits);
        end

        if (response !== expected) begin
            $fatal(1, "shared shift/rotate mismatch request=%p expected=%p observed=%p", request, expected, response);
        end

        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;
    endtask

    task automatic check_ordinary_throughput;
        m64k_execute_tag_t previous_tag;

        request.source = 64'h89ab_cdef_0123_4567;
        request.count = 6'd7;
        request.operand_size = M64K_SHIFT_SIZE_QUAD;
        request.extend_in = 1'b0;
        request.update_flags = 1'b1;
        response_ready = 1'b1;

        for (int unsigned request_index = 0; request_index < 16; request_index++) begin
            @(negedge clock);
            if (request_index != 0 && (!response_valid || response.tag !== previous_tag)) begin
                $fatal(1, "ordinary throughput-one stream lost or reordered a response at index %0d", request_index);
            end

            allocate_tag();
            request.operation = m64k_shift_operation_t'(request_index % 6);
            previous_tag = request.tag;
            request_valid = 1'b1;

            if (!request_ready) begin
                $fatal(1, "ordinary throughput-one stream observed request backpressure at index %0d", request_index);
            end
        end

        @(negedge clock);
        request_valid = 1'b0;
        if (!response_valid || response.tag !== previous_tag) begin
            $fatal(1, "ordinary throughput-one stream lost its final response");
        end
        @(negedge clock);
        response_ready = 1'b0;
    endtask

    task automatic check_exhaustive_byte;
        request.operand_size = M64K_SHIFT_SIZE_BYTE;

        for (int unsigned operation_index = 0; operation_index < 8; operation_index++) begin
            request.operation = m64k_shift_operation_t'(operation_index[2:0]);
            for (int unsigned extend_index = 0; extend_index < 2; extend_index++) begin
                request.extend_in = extend_index[0];
                for (int unsigned flags_index = 0; flags_index < 2; flags_index++) begin
                    request.update_flags = flags_index[0];
                    for (int unsigned count_index = 0; count_index < 64; count_index++) begin
                        request.count = count_index[5:0];
                        for (int unsigned source_index = 0; source_index < 256; source_index++) begin
                            allocate_tag();
                            request.source = {56'hd3_5aa5_96c3_69, source_index[7:0]};
                            transact_and_check();
                        end
                    end
                end
            end
        end
    endtask

    task automatic check_wide_boundaries;
        logic [63:0] values [0:7];
        logic [5:0] counts [0:8];
        int unsigned width;

        values = '{64'd0, 64'd1, 64'h7fff_ffff_ffff_ffff, 64'h8000_0000_0000_0000,
            64'hffff_ffff_ffff_ffff, 64'haa55_aa55_aa55_aa55, 64'h0000_0001_0000_0000, 64'h0000_0000_0000_0100};

        for (int unsigned size_index = 1; size_index < 4; size_index++) begin
            request.operand_size = m64k_shift_size_t'(size_index[1:0]);
            width = operand_width(request.operand_size);
            counts = '{6'd0, 6'd1, 6'(width - 1), 6'(width), 6'(width + 1), 6'd17, 6'd32, 6'd33, 6'd63};

            for (int unsigned operation_index = 0; operation_index < 8; operation_index++) begin
                request.operation = m64k_shift_operation_t'(operation_index[2:0]);
                for (int unsigned extend_index = 0; extend_index < 2; extend_index++) begin
                    request.extend_in = extend_index[0];
                    for (int unsigned flags_index = 0; flags_index < 2; flags_index++) begin
                        request.update_flags = flags_index[0];
                        for (int unsigned count_index = 0; count_index < 9; count_index++) begin
                            request.count = counts[count_index];
                            for (int unsigned value_index = 0; value_index < 8; value_index++) begin
                                allocate_tag();
                                request.source = values[value_index];
                                transact_and_check();
                            end
                        end
                    end
                end
            end
        end
    endtask

    task automatic check_reproducible_random_cases;
        logic [63:0] random_state;

        random_state = 64'hd8b5_3ca7_491e_62f0;
        for (int unsigned case_index = 0; case_index < 8192; case_index++) begin
            random_state = {random_state[62:0], random_state[63] ^ random_state[62] ^ random_state[60] ^ random_state[59]};
            allocate_tag();
            request.source = random_state;
            request.count = random_state[13:8];
            request.operand_size = m64k_shift_size_t'(random_state[15:14]);
            request.operation = m64k_shift_operation_t'(random_state[18:16]);
            request.extend_in = random_state[19];
            request.update_flags = random_state[20];
            transact_and_check();
        end
    endtask

    task automatic check_protocol;
        m64k_shift_rotate_shared_response_t held_response;
        m64k_execute_tag_t cancelled_tag;

        allocate_tag();
        request.source = 64'h0123_4567_89ab_cdef;
        request.count = 6'd63;
        request.operand_size = M64K_SHIFT_SIZE_QUAD;
        request.operation = M64K_SHIFT_ROXR;
        request.extend_in = 1'b1;
        request.update_flags = 1'b1;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        while (!response_valid) begin
            @(negedge clock);
        end
        held_response = response;
        squash_valid = 1'b1;
        squash.tag = request.tag;
        repeat (4) begin
            @(negedge clock);
            if (!response_valid || response !== held_response) begin
                $fatal(1, "published response was changed by backpressure or squash");
            end
        end
        squash_valid = 1'b0;
        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;

        allocate_tag();
        request.operation = M64K_SHIFT_ROXL;
        @(negedge clock);
        if (!request_ready) begin
            $fatal(1, "candidate was not ready for accept-time squash verification");
        end
        request_valid = 1'b1;
        squash_valid = 1'b1;
        squash.tag = request.tag;
        @(negedge clock);
        request_valid = 1'b0;
        squash_valid = 1'b0;
        repeat (4) begin
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "accept-time exact squash published a response");
            end
        end

        allocate_tag();
        cancelled_tag = request.tag;
        request.operation = M64K_SHIFT_ROXL;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        squash_valid = 1'b1;
        squash.tag = cancelled_tag;
        @(negedge clock);
        squash_valid = 1'b0;
        repeat (4) begin
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "squashed ROX request published a response");
            end
        end

        allocate_tag();
        request.operation = M64K_SHIFT_ROXR;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        squash_valid = 1'b1;
        squash.tag = request.tag;
        squash.tag.execution_context.hardware_thread_id ^= 2'b01;
        @(negedge clock);
        squash_valid = 1'b0;
        while (!response_valid) begin
            @(negedge clock);
        end
        if (response.tag !== request.tag) begin
            $fatal(1, "wrong-thread squash corrupted an independent request");
        end
        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;
    endtask

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        request_valid = 1'b0;
        request = '0;
        squash_valid = 1'b0;
        squash = '0;
        response_ready = 1'b0;
        allocation_sequence = M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH'(1);

        repeat (3) @(negedge clock);
        reset = 1'b0;

        check_exhaustive_byte();
        check_wide_boundaries();
        check_reproducible_random_cases();
        check_ordinary_throughput();
        check_protocol();

        $display("M64K shared shift/rotate candidate passed exhaustive semantic and protocol verification");
        $finish;
    end
endmodule
