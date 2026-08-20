module m64k_integer_execute_tb;
    import m64k_arch_types_pkg::*;
    import m64k_execute_backend_pkg::*;
    import m64k_integer_alu_pkg::*;
    import m64k_integer_execute_pkg::*;

    logic clock;
    logic reset;
    logic request_valid;
    logic request_ready;
    m64k_integer_execute_request_t request;
    logic response_valid;
    logic response_ready;
    m64k_integer_execute_response_t response;
    logic integrity_error;
    logic squash_valid;
    m64k_integer_execute_squash_t squash;

    logic [63:0] reference_result;
    logic reference_result_valid;
    logic reference_negative;
    logic reference_zero;
    logic reference_overflow;
    logic reference_carry_or_borrow;
    logic reference_flags_valid;
    logic reference_extend;
    logic reference_extend_valid;

    m64k_integer_execute dut (
        .clock(clock),
        .reset(reset),
        .request_valid(request_valid),
        .request_ready(request_ready),
        .request(request),
        .response_valid(response_valid),
        .response_ready(response_ready),
        .response(response),
        .integrity_error(integrity_error),
        .squash_valid(squash_valid),
        .squash(squash)
    );

    m64k_integer_alu semantic_reference (
        .source_left(request.source_left),
        .source_right(request.source_right),
        .operand_size(request.operand_size),
        .operation(request.operation),
        .extend_in(request.extend_in),
        .update_flags(request.update_flags),
        .result(reference_result),
        .result_valid(reference_result_valid),
        .negative(reference_negative),
        .zero(reference_zero),
        .overflow(reference_overflow),
        .carry_or_borrow(reference_carry_or_borrow),
        .flags_valid(reference_flags_valid),
        .extend_out(reference_extend),
        .extend_valid(reference_extend_valid)
    );

    always #1 clock = ~clock;

    function automatic m64k_execute_tag_t make_tag(
        input logic [5:0] core_id,
        input logic [1:0] hardware_thread_id,
        input logic [7:0] rob_index,
        input m64k_backend_allocation_sequence_t allocation_sequence
    );
        m64k_execute_tag_t tag;

        tag = '0;
        tag.execution_context.core_id = core_id;
        tag.execution_context.hardware_thread_id = hardware_thread_id;
        tag.rob_index = rob_index;
        tag.rob_generation = 8'h5a;
        tag.allocation_sequence = allocation_sequence;
        tag.uop_index = 4'h3;
        return tag;
    endfunction

    task automatic issue_and_check(
        input m64k_integer_operation_t operation,
        input m64k_integer_size_t operand_size,
        input logic [63:0] source_left,
        input logic [63:0] source_right,
        input logic extend_in,
        input logic update_flags,
        input m64k_execute_tag_t tag
    );
        logic [63:0] expected_result;
        logic expected_result_valid;
        logic expected_negative;
        logic expected_zero;
        logic expected_overflow;
        logic expected_carry_or_borrow;
        logic expected_flags_valid;
        logic expected_extend;
        logic expected_extend_valid;

        @(negedge clock);
        request.tag = tag;
        request.source_left = source_left;
        request.source_right = source_right;
        request.operand_size = operand_size;
        request.operation = operation;
        request.extend_in = extend_in;
        request.update_flags = update_flags;
        request_valid = 1'b1;
        #0;

        expected_result = reference_result;
        expected_result_valid = reference_result_valid;
        expected_negative = reference_negative;
        expected_zero = reference_zero;
        expected_overflow = reference_overflow;
        expected_carry_or_borrow = reference_carry_or_borrow;
        expected_flags_valid = reference_flags_valid;
        expected_extend = reference_extend;
        expected_extend_valid = reference_extend_valid;

        if (!request_ready) begin
            $fatal(1, "integer execution pipe unexpectedly rejected an unblocked request");
        end

        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;

        if (!response_valid) begin
            $fatal(1, "integer execution pipe did not publish an accepted request");
        end
        if (response.tag !== tag) begin
            $fatal(1, "integer execution pipe corrupted the execution tag");
        end
        if (response.result_valid !== expected_result_valid || response.result.valid !== expected_result_valid) begin
            $fatal(1, "integer execution pipe result validity mismatch");
        end
        if (response.result.role !== M64K_EXECUTE_RESULT_LOW) begin
            $fatal(1, "integer execution pipe returned the wrong result role");
        end
        if (response.result.value !== expected_result) begin
            $fatal(1, "integer execution pipe result mismatch");
        end
        if (response.flags_valid !== expected_flags_valid || response.negative !== expected_negative || response.zero !== expected_zero || response.overflow !== expected_overflow || response.carry_or_borrow !== expected_carry_or_borrow) begin
            $fatal(1, "integer execution pipe condition-state mismatch");
        end
        if (response.extend_valid !== expected_extend_valid || response.extend !== expected_extend) begin
            $fatal(1, "integer execution pipe extend-state mismatch");
        end

        @(posedge clock);
        @(negedge clock);
        if (response_valid) begin
            $fatal(1, "consumed integer response remained valid");
        end
    endtask

    task automatic check_same_cycle_squash;
        m64k_execute_tag_t cancelled_tag;

        cancelled_tag = make_tag(6'd3, 2'd1, 8'h44, 64'h1001);
        @(negedge clock);
        request = '0;
        request.tag = cancelled_tag;
        request.operation = M64K_INTEGER_ADD;
        request.operand_size = M64K_INTEGER_SIZE_QUAD;
        request.source_left = 64'd10;
        request.source_right = 64'd20;
        request_valid = 1'b1;
        squash.tag = cancelled_tag;
        squash_valid = 1'b1;

        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;
        squash_valid = 1'b0;
        if (response_valid) begin
            $fatal(1, "same-cycle exact-tag squash published a response");
        end
    endtask

    task automatic check_held_response;
        m64k_execute_tag_t held_tag;
        m64k_integer_execute_response_t held_response;

        held_tag = make_tag(6'd17, 2'd2, 8'hc0, 64'hbeef);
        @(negedge clock);
        response_ready = 1'b0;
        request = '0;
        request.tag = held_tag;
        request.operation = M64K_INTEGER_XOR;
        request.operand_size = M64K_INTEGER_SIZE_QUAD;
        request.source_left = 64'h55aa_55aa_0123_4567;
        request.source_right = 64'haa55_aa55_7654_3210;
        request.update_flags = 1'b1;
        request_valid = 1'b1;

        @(posedge clock);
        @(negedge clock);
        request_valid = 1'b0;
        if (!response_valid) begin
            $fatal(1, "backpressured response was not published");
        end
        held_response = response;

        squash.tag = held_tag;
        squash_valid = 1'b1;
        repeat (3) begin
            @(posedge clock);
            @(negedge clock);
            if (!response_valid || response !== held_response || request_ready) begin
                $fatal(1, "published response changed or retracted under backpressure");
            end
        end

        squash_valid = 1'b0;
        response_ready = 1'b1;
        @(posedge clock);
        @(negedge clock);
        if (response_valid) begin
            $fatal(1, "released held response remained valid");
        end
    endtask

    task automatic check_invalid_operations_are_rejected;
        for (int unsigned operation_index = 12; operation_index < 16; operation_index++) begin
            @(negedge clock);
            request = '0;
            request.tag = make_tag(6'd1, 2'd0, 8'(operation_index), 64'h8000 + 64'(operation_index));
            request.operation = m64k_integer_operation_t'(operation_index);
            request.operand_size = M64K_INTEGER_SIZE_QUAD;
            request_valid = 1'b1;
            #0;

            if (request_ready || !integrity_error) begin
                $fatal(1, "unsupported integer uop was accepted or failed to report an integrity error");
            end

            @(posedge clock);
            @(negedge clock);
            request_valid = 1'b0;
            if (response_valid) begin
                $fatal(1, "unsupported integer uop published a response");
            end
        end
    endtask

    task automatic check_throughput_and_identity_isolation;
        m64k_execute_tag_t expected_tag;

        for (int unsigned request_index = 0; request_index < 16; request_index++) begin
            @(negedge clock);
            if ((request_index != 0) && (!response_valid || response.tag !== expected_tag || response.result.value !== (64'd100 + 64'(request_index) - 64'd1))) begin
                $fatal(1, "back-to-back integer response lost order, identity, or value");
            end

            request = '0;
            request.tag = make_tag(6'(request_index % 4), 2'(request_index % 2), 8'(request_index), 64'h1_0000_0000 + 64'(request_index));
            request.operation = M64K_INTEGER_ADD;
            request.operand_size = M64K_INTEGER_SIZE_QUAD;
            request.source_left = 64'd100;
            request.source_right = 64'(request_index);
            request_valid = 1'b1;

            squash_valid = request_index == 7;
            squash.tag = make_tag(6'd63, 2'd3, 8'hff, 64'hffff_ffff_ffff_ffff);
            #0;
            if (!request_ready || integrity_error) begin
                $fatal(1, "legal back-to-back integer request was not accepted");
            end
            expected_tag = request.tag;
            @(posedge clock);
        end

        @(negedge clock);
        if (!response_valid || response.tag !== expected_tag || response.result.value !== 64'd115) begin
            $fatal(1, "final back-to-back integer response was lost");
        end
        request_valid = 1'b0;
        squash_valid = 1'b0;
        @(posedge clock);
        @(negedge clock);
        if (response_valid) begin
            $fatal(1, "back-to-back stream did not drain");
        end
    endtask

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        request_valid = 1'b0;
        request = '0;
        response_ready = 1'b1;
        squash_valid = 1'b0;
        squash = '0;

        repeat (3) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;

        for (int unsigned operation_index = 0; operation_index < 12; operation_index++) begin
            for (int unsigned size_index = 0; size_index < 4; size_index++) begin
                for (int unsigned policy_index = 0; policy_index < 4; policy_index++) begin
                    issue_and_check(
                        m64k_integer_operation_t'(operation_index),
                        m64k_integer_size_t'(size_index),
                        64'h8000_0001_ffff_007f ^ 64'(operation_index),
                        64'h7fff_ffff_0000_0081 ^ 64'(size_index),
                        policy_index[0],
                        policy_index[1],
                        make_tag(6'(operation_index), 2'(size_index), 8'(operation_index * 4 + size_index), 64'(operation_index * 16 + size_index * 4 + policy_index))
                    );
                end
            end
        end

        check_same_cycle_squash();
        check_held_response();
        check_invalid_operations_are_rejected();
        check_throughput_and_identity_isolation();

        $display("M64K tagged integer execution pipe verification passed");
        $finish;
    end
endmodule
