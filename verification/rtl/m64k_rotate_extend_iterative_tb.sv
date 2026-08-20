module m64k_rotate_extend_iterative_tb;
    import m64k_arch_types_pkg::*;
    import m64k_execute_backend_pkg::*;
    import m64k_shift_rotate_pkg::*;
    import m64k_rotate_extend_iterative_pkg::*;

    logic clock;
    logic reset;
    logic request_valid;
    logic request_ready;
    m64k_rotate_extend_request_t request;
    logic squash_valid;
    m64k_rotate_extend_squash_t squash;
    logic response_valid;
    logic response_ready;
    m64k_rotate_extend_response_t response;
    m64k_backend_allocation_sequence_t next_allocation_sequence;

    m64k_rotate_extend_iterative dut (.*);

    always #1 clock = ~clock;

    function automatic int unsigned operand_width(input m64k_shift_size_t operand_size);
        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: return 8;
            M64K_SHIFT_SIZE_WORD: return 16;
            M64K_SHIFT_SIZE_LONG: return 32;
            M64K_SHIFT_SIZE_QUAD: return 64;
        endcase
    endfunction

    function automatic logic [64:0] oracle_ring(
        input logic [63:0] source,
        input logic extend_in,
        input logic [5:0] count,
        input m64k_shift_size_t operand_size,
        input m64k_rotate_extend_direction_t direction
    );
        logic [64:0] ring;
        int unsigned width;
        int unsigned effective_count;

        width = operand_width(operand_size);
        effective_count = int'(count) % (width + 1);
        ring = 65'd0;

        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: ring[8:0] = {source[7:0], extend_in};
            M64K_SHIFT_SIZE_WORD: ring[16:0] = {source[15:0], extend_in};
            M64K_SHIFT_SIZE_LONG: ring[32:0] = {source[31:0], extend_in};
            M64K_SHIFT_SIZE_QUAD: ring = {source, extend_in};
        endcase

        // The oracle deliberately uses repeated one-bit rotation, independently
        // of the DUT's binary-decomposed fixed-stage network.
        for (int unsigned step = 0; step < effective_count; step++) begin
            case (operand_size)
                M64K_SHIFT_SIZE_BYTE: begin
                    if (direction == M64K_ROTATE_EXTEND_LEFT) begin
                        ring[8:0] = {ring[7:0], ring[8]};
                    end else begin
                        ring[8:0] = {ring[0], ring[8:1]};
                    end
                end
                M64K_SHIFT_SIZE_WORD: begin
                    if (direction == M64K_ROTATE_EXTEND_LEFT) begin
                        ring[16:0] = {ring[15:0], ring[16]};
                    end else begin
                        ring[16:0] = {ring[0], ring[16:1]};
                    end
                end
                M64K_SHIFT_SIZE_LONG: begin
                    if (direction == M64K_ROTATE_EXTEND_LEFT) begin
                        ring[32:0] = {ring[31:0], ring[32]};
                    end else begin
                        ring[32:0] = {ring[0], ring[32:1]};
                    end
                end
                M64K_SHIFT_SIZE_QUAD: begin
                    if (direction == M64K_ROTATE_EXTEND_LEFT) begin
                        ring = {ring[63:0], ring[64]};
                    end else begin
                        ring = {ring[0], ring[64:1]};
                    end
                end
            endcase
        end

        return ring;
    endfunction

    function automatic logic [63:0] oracle_result(
        input logic [63:0] operand_bits,
        input m64k_shift_size_t operand_size
    );
        logic [63:0] mask;

        case (operand_size)
            M64K_SHIFT_SIZE_BYTE: mask = 64'h0000_0000_0000_00ff;
            M64K_SHIFT_SIZE_WORD: mask = 64'h0000_0000_0000_ffff;
            M64K_SHIFT_SIZE_LONG: mask = 64'h0000_0000_ffff_ffff;
            M64K_SHIFT_SIZE_QUAD: mask = 64'hffff_ffff_ffff_ffff;
        endcase

        return operand_bits & mask;
    endfunction

    task automatic allocate_tag(
        input logic [M64K_CORE_ID_WIDTH-1:0] core_id,
        input logic [M64K_HARDWARE_THREAD_ID_WIDTH-1:0] thread_id
    );
        request.tag = '0;
        request.tag.execution_context.core_id = core_id;
        request.tag.execution_context.hardware_thread_id = thread_id;
        request.tag.rob_index = next_allocation_sequence[M64K_BACKEND_ROB_INDEX_WIDTH-1:0];
        request.tag.rob_generation = next_allocation_sequence[M64K_BACKEND_ROB_GENERATION_WIDTH-1:0] ^ 8'ha5;
        request.tag.allocation_sequence = next_allocation_sequence;
        request.tag.uop_index = next_allocation_sequence[M64K_BACKEND_UOP_INDEX_WIDTH-1:0];
        next_allocation_sequence = next_allocation_sequence + 64'd1;
    endtask

    task automatic transact_and_check;
        logic [64:0] expected_ring;
        logic [63:0] expected_result;
        m64k_execute_tag_t expected_tag;
        int unsigned execution_cycles;

        expected_ring = oracle_ring(request.source, request.extend_in, request.count, request.operand_size, request.direction);
        expected_result = oracle_result(expected_ring[64:1], request.operand_size);
        expected_tag = request.tag;

        @(negedge clock);
        request_valid = 1'b1;
        if (!request_ready) begin
            $fatal(1, "rotate-through-X unit was not ready before isolated transaction");
        end
        @(negedge clock);
        request_valid = 1'b0;

        execution_cycles = 0;
        while (!response_valid) begin
            @(negedge clock);
            execution_cycles++;
        end

        if (execution_cycles != 6) begin
            $fatal(1, "rotate-through-X latency mismatch expected=6 observed=%0d", execution_cycles);
        end
        if (response.tag !== expected_tag
            || response.result !== expected_result
            || response.extend_valid !== 1'b1
            || response.extend_out !== expected_ring[0]
            || response.flags_valid !== request.update_flags
            || response.negative !== expected_result[operand_width(request.operand_size) - 1]
            || response.zero !== (expected_result == 64'd0)
            || response.overflow !== 1'b0
            || response.carry !== expected_ring[0]) begin
            $fatal(1, "rotate-through-X mismatch request=%p response=%p expected_ring=%017x", request, response, expected_ring);
        end

        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;
    endtask

    task automatic check_exhaustive_byte;
        request.operand_size = M64K_SHIFT_SIZE_BYTE;

        for (int unsigned direction_index = 0; direction_index < 2; direction_index++) begin
            request.direction = m64k_rotate_extend_direction_t'(direction_index[0]);
            for (int unsigned extend_index = 0; extend_index < 2; extend_index++) begin
                request.extend_in = extend_index[0];
                for (int unsigned flags_index = 0; flags_index < 2; flags_index++) begin
                    request.update_flags = flags_index[0];
                    for (int unsigned count_index = 0; count_index < 64; count_index++) begin
                        request.count = count_index[5:0];
                        for (int unsigned source_index = 0; source_index < 256; source_index++) begin
                            allocate_tag(6'd1 + direction_index[5:0], extend_index[1:0]);
                            request.source = {56'h5a_a55a_a55a_a5, source_index[7:0]};
                            transact_and_check();
                        end
                    end
                end
            end
        end
    endtask

    task automatic check_wide_boundaries;
        logic [63:0] source_values [0:7];
        logic [5:0] count_values [0:9];
        int unsigned width;

        source_values[0] = 64'd0;
        source_values[1] = 64'd1;
        source_values[2] = 64'h7fff_ffff_ffff_ffff;
        source_values[3] = 64'h8000_0000_0000_0000;
        source_values[4] = 64'hffff_ffff_ffff_ffff;
        source_values[5] = 64'haa55_aa55_aa55_aa55;
        source_values[6] = 64'h0000_0001_0000_0000;
        source_values[7] = 64'h0000_0000_0000_0100;

        for (int unsigned size_index = 1; size_index < 4; size_index++) begin
            request.operand_size = m64k_shift_size_t'(size_index[1:0]);
            width = operand_width(request.operand_size);
            count_values[0] = 6'd0;
            count_values[1] = 6'd1;
            count_values[2] = 6'(width - 1);
            count_values[3] = 6'(width);
            count_values[4] = 6'(width + 1);
            count_values[5] = 6'(2 * width);
            count_values[6] = 6'(2 * width + 1);
            count_values[7] = 6'd32;
            count_values[8] = 6'd33;
            count_values[9] = 6'd63;

            for (int unsigned direction_index = 0; direction_index < 2; direction_index++) begin
                request.direction = m64k_rotate_extend_direction_t'(direction_index[0]);
                for (int unsigned extend_index = 0; extend_index < 2; extend_index++) begin
                    request.extend_in = extend_index[0];
                    for (int unsigned flags_index = 0; flags_index < 2; flags_index++) begin
                        request.update_flags = flags_index[0];
                        for (int unsigned count_index = 0; count_index < 10; count_index++) begin
                            request.count = count_values[count_index];
                            for (int unsigned source_index = 0; source_index < 8; source_index++) begin
                                allocate_tag(6'd8 + size_index[5:0], extend_index[1:0]);
                                request.source = source_values[source_index];
                                transact_and_check();
                            end
                        end
                    end
                end
            end
        end
    endtask

    task automatic check_protocol;
        m64k_rotate_extend_response_t held_response;
        m64k_execute_tag_t cancelled_tag;
        m64k_execute_tag_t expected_tag;

        allocate_tag(6'd20, 2'd3);
        request.source = 64'h0123_4567_89ab_cdef;
        request.count = 6'd63;
        request.operand_size = M64K_SHIFT_SIZE_QUAD;
        request.direction = M64K_ROTATE_EXTEND_RIGHT;
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
                $fatal(1, "published rotate-through-X response changed under backpressure or squash");
            end
        end
        squash_valid = 1'b0;
        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;

        allocate_tag(6'd21, 2'd1);
        cancelled_tag = request.tag;
        request.direction = M64K_ROTATE_EXTEND_LEFT;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        repeat (3) @(negedge clock);
        squash_valid = 1'b1;
        squash.tag = cancelled_tag;
        @(negedge clock);
        squash_valid = 1'b0;
        repeat (8) begin
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "squashed rotate-through-X operation published a response");
            end
        end
        if (!request_ready) begin
            $fatal(1, "rotate-through-X unit did not become ready after exact-tag squash");
        end

        allocate_tag(6'd22, 2'd2);
        expected_tag = request.tag;
        request.source = 64'h8000_0000_0000_0001;
        request.count = 6'd32;
        request.direction = M64K_ROTATE_EXTEND_RIGHT;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        repeat (2) @(negedge clock);
        squash_valid = 1'b1;
        squash.tag = expected_tag;
        squash.tag.execution_context.hardware_thread_id = 2'd1;
        @(negedge clock);
        squash_valid = 1'b0;
        while (!response_valid) begin
            @(negedge clock);
        end
        if (response.tag !== expected_tag) begin
            $fatal(1, "wrong-thread squash corrupted rotate-through-X identity");
        end
        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;

        // A squash concurrent with request acceptance cancels only the exact
        // complete allocation identity and must not publish any response.
        allocate_tag(6'd23, 2'd0);
        @(negedge clock);
        request_valid = 1'b1;
        squash_valid = 1'b1;
        squash.tag = request.tag;
        @(negedge clock);
        request_valid = 1'b0;
        squash_valid = 1'b0;
        repeat (8) begin
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "accept-time exact-tag squash published a response");
            end
        end
        if (!request_ready) begin
            $fatal(1, "accept-time squash consumed iterative unit capacity");
        end
    endtask

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        request_valid = 1'b0;
        request = '0;
        squash_valid = 1'b0;
        squash = '0;
        response_ready = 1'b0;
        next_allocation_sequence = 64'd1;

        repeat (3) @(negedge clock);
        reset = 1'b0;

        check_protocol();
        check_wide_boundaries();
        check_exhaustive_byte();

        $display("m64k_rotate_extend_iterative_tb: PASS");
        $finish;
    end
endmodule
