module m64k_scalar_divider_tb;
    import m64k_arch_types_pkg::*;
    import m64k_execute_backend_pkg::*;
    import m64k_scalar_divider_pkg::*;

    logic clock;
    logic reset;
    logic request_valid;
    logic request_ready;
    m64k_divide_request_t request;
    logic squash_valid;
    m64k_divide_squash_t squash;
    logic response_valid;
    logic response_ready;
    m64k_divide_response_t response;
    m64k_backend_allocation_sequence_t next_allocation_sequence;

    m64k_scalar_divider dut (.*);

    always #1 clock = ~clock;

    function automatic logic [63:0] size_mask(input m64k_divide_size_t operand_size);
        case (operand_size)
            M64K_DIVIDE_SIZE_BYTE: return 64'h0000_0000_0000_00ff;
            M64K_DIVIDE_SIZE_WORD: return 64'h0000_0000_0000_ffff;
            M64K_DIVIDE_SIZE_LONG: return 64'h0000_0000_ffff_ffff;
            M64K_DIVIDE_SIZE_QUAD: return 64'hffff_ffff_ffff_ffff;
        endcase
    endfunction

    function automatic logic [63:0] size_sign_bit(input m64k_divide_size_t operand_size);
        case (operand_size)
            M64K_DIVIDE_SIZE_BYTE: return 64'h0000_0000_0000_0080;
            M64K_DIVIDE_SIZE_WORD: return 64'h0000_0000_0000_8000;
            M64K_DIVIDE_SIZE_LONG: return 64'h0000_0000_8000_0000;
            M64K_DIVIDE_SIZE_QUAD: return 64'h8000_0000_0000_0000;
        endcase
    endfunction

    task automatic allocate_tag(
        input logic [M64K_CORE_ID_WIDTH-1:0] core_id,
        input logic [M64K_HARDWARE_THREAD_ID_WIDTH-1:0] thread_id
    );
        request.tag = '0;
        request.tag.execution_context.core_id = core_id;
        request.tag.execution_context.hardware_thread_id = thread_id;
        request.tag.rob_index = next_allocation_sequence[M64K_BACKEND_ROB_INDEX_WIDTH-1:0];
        request.tag.rob_generation = next_allocation_sequence[M64K_BACKEND_ROB_GENERATION_WIDTH-1:0] ^ 8'h5a;
        request.tag.allocation_sequence = next_allocation_sequence;
        request.tag.uop_index = next_allocation_sequence[M64K_BACKEND_UOP_INDEX_WIDTH-1:0];
        next_allocation_sequence = next_allocation_sequence + 64'd1;
    endtask

    task automatic transact;
        @(negedge clock);
        request_valid = 1'b1;
        while (!request_ready) begin
            @(negedge clock);
        end
        @(negedge clock);
        request_valid = 1'b0;
        while (!response_valid) begin
            @(negedge clock);
        end
    endtask

    task automatic retire_response;
        response_ready = 1'b1;
        @(negedge clock);
        response_ready = 1'b0;
    endtask

    task automatic check_response(
        input m64k_divide_fault_t expected_fault,
        input logic expected_quotient_valid,
        input logic expected_remainder_valid,
        input logic [63:0] expected_quotient,
        input logic [63:0] expected_remainder,
        input logic expected_flags_valid,
        input logic expected_negative,
        input logic expected_zero
    );
        logic [1:0] expected_count;
        logic observed_quotient_valid;
        logic observed_remainder_valid;
        logic [63:0] observed_quotient;
        logic [63:0] observed_remainder;

        expected_count = {1'b0, expected_quotient_valid} + {1'b0, expected_remainder_valid};
        observed_quotient_valid = 1'b0;
        observed_remainder_valid = 1'b0;
        observed_quotient = 64'd0;
        observed_remainder = 64'd0;

        for (int unsigned result_index = 0; result_index < 2; result_index++) begin
            if (response.results[result_index].valid) begin
                case (response.results[result_index].role)
                    M64K_EXECUTE_RESULT_QUOTIENT: begin
                        if (observed_quotient_valid) begin
                            $fatal(1, "divider published duplicate quotient roles");
                        end
                        observed_quotient_valid = 1'b1;
                        observed_quotient = response.results[result_index].value;
                    end
                    M64K_EXECUTE_RESULT_REMAINDER: begin
                        if (observed_remainder_valid) begin
                            $fatal(1, "divider published duplicate remainder roles");
                        end
                        observed_remainder_valid = 1'b1;
                        observed_remainder = response.results[result_index].value;
                    end
                    default: begin
                        $fatal(1, "divider published a result with a non-divide role");
                    end
                endcase
            end
        end

        if (response.tag !== request.tag
            || response.fault_valid !== (expected_fault != M64K_DIVIDE_FAULT_NONE)
            || response.fault !== expected_fault
            || response.result_count !== expected_count
            || observed_quotient_valid !== expected_quotient_valid
            || observed_remainder_valid !== expected_remainder_valid
            || response.flags_valid !== expected_flags_valid) begin
            $fatal(1, "divider response metadata mismatch response=%p", response);
        end

        if (expected_quotient_valid && observed_quotient !== expected_quotient) begin
            $fatal(1, "quotient mismatch expected=%016x observed=%016x", expected_quotient, observed_quotient);
        end
        if (expected_remainder_valid && observed_remainder !== expected_remainder) begin
            $fatal(1, "remainder mismatch expected=%016x observed=%016x", expected_remainder, observed_remainder);
        end
        if (expected_flags_valid) begin
            if (response.negative !== expected_negative || response.zero !== expected_zero
                || response.overflow !== 1'b0 || response.carry !== 1'b0) begin
                $fatal(1, "divide flag mismatch response=%p", response);
            end
        end
        if (expected_fault != M64K_DIVIDE_FAULT_NONE) begin
            if (response.results[0].valid || response.results[1].valid || response.flags_valid) begin
                $fatal(1, "faulting divide exposed a write or flag update response=%p", response);
            end
        end
    endtask

    task automatic check_exhaustive_byte;
        integer signed dividend_value;
        integer signed divisor_value;
        integer signed quotient_value;
        integer signed remainder_value;
        logic [63:0] expected_quotient;
        logic [63:0] expected_remainder;
        logic expected_quotient_valid;
        logic expected_remainder_valid;
        m64k_divide_fault_t expected_fault;

        request.operand_size = M64K_DIVIDE_SIZE_BYTE;
        request.double_width_dividend = 1'b0;
        request.dividend_high = 64'd0;
        request.update_flags = 1'b1;

        for (int unsigned signed_index = 0; signed_index < 2; signed_index++) begin
            request.signed_operation = signed_index[0];
            for (int unsigned form_index = 0; form_index < 3; form_index++) begin
                request.result_form = m64k_divide_result_form_t'(form_index[1:0]);
                for (int unsigned dividend_bits = 0; dividend_bits < 256; dividend_bits++) begin
                    for (int unsigned divisor_bits = 0; divisor_bits < 256; divisor_bits++) begin
                        allocate_tag(6'd1, signed_index[0] ? 2'd1 : 2'd0);
                        request.dividend_low = 64'(dividend_bits);
                        request.divisor = 64'(divisor_bits);
                        transact();

                        expected_quotient_valid = request.result_form != M64K_DIVIDE_REMAINDER;
                        expected_remainder_valid = request.result_form != M64K_DIVIDE_QUOTIENT;
                        expected_fault = M64K_DIVIDE_FAULT_NONE;
                        expected_quotient = 64'd0;
                        expected_remainder = 64'd0;
                        dividend_value = request.signed_operation && dividend_bits >= 128 ? integer'(dividend_bits) - 256 : integer'(dividend_bits);
                        divisor_value = request.signed_operation && divisor_bits >= 128 ? integer'(divisor_bits) - 256 : integer'(divisor_bits);

                        if (divisor_bits == 0) begin
                            expected_fault = M64K_DIVIDE_FAULT_ZERO;
                            expected_quotient_valid = 1'b0;
                            expected_remainder_valid = 1'b0;
                        end else begin
                            quotient_value = dividend_value / divisor_value;
                            remainder_value = dividend_value - quotient_value * divisor_value;
                            if (expected_quotient_valid && (quotient_value < -128 || quotient_value > 255
                                || (request.signed_operation && quotient_value > 127))) begin
                                expected_fault = M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW;
                                expected_quotient_valid = 1'b0;
                                expected_remainder_valid = 1'b0;
                            end else begin
                                expected_quotient = 64'(quotient_value) & 64'hff;
                                expected_remainder = 64'(remainder_value) & 64'hff;
                            end
                        end

                        check_response(
                            expected_fault,
                            expected_quotient_valid,
                            expected_remainder_valid,
                            expected_quotient,
                            expected_remainder,
                            expected_fault == M64K_DIVIDE_FAULT_NONE,
                            request.result_form == M64K_DIVIDE_REMAINDER ? expected_remainder[7] : expected_quotient[7],
                            request.result_form == M64K_DIVIDE_REMAINDER ? expected_remainder == 64'd0 : expected_quotient == 64'd0
                        );
                        retire_response();
                    end
                end
            end
        end
    endtask

    task automatic check_same_width_directed(
        input m64k_divide_size_t operand_size,
        input logic signed_operation,
        input logic [63:0] dividend,
        input logic [63:0] divisor,
        input logic [63:0] quotient,
        input logic [63:0] remainder
    );
        logic [63:0] mask;

        mask = size_mask(operand_size);
        allocate_tag(6'd3, signed_operation ? 2'd1 : 2'd0);
        request.operand_size = operand_size;
        request.result_form = M64K_DIVIDE_QUOTIENT_REMAINDER;
        request.signed_operation = signed_operation;
        request.double_width_dividend = 1'b0;
        request.update_flags = 1'b1;
        request.dividend_low = dividend;
        request.dividend_high = 64'd0;
        request.divisor = divisor;
        transact();
        check_response(
            M64K_DIVIDE_FAULT_NONE,
            1'b1,
            1'b1,
            quotient & mask,
            remainder & mask,
            1'b1,
            (quotient & size_sign_bit(operand_size)) != 64'd0,
            (quotient & mask) == 64'd0
        );
        retire_response();
    endtask

    task automatic check_wide_directed(
        input m64k_divide_size_t operand_size,
        input logic signed_operation,
        input logic [63:0] dividend_high,
        input logic [63:0] dividend_low,
        input logic [63:0] divisor,
        input m64k_divide_fault_t expected_fault,
        input logic [63:0] expected_quotient,
        input logic [63:0] expected_remainder
    );
        logic [63:0] mask;
        logic successful;

        mask = size_mask(operand_size);
        successful = expected_fault == M64K_DIVIDE_FAULT_NONE;
        allocate_tag(6'd4, signed_operation ? 2'd1 : 2'd0);
        request.operand_size = operand_size;
        request.result_form = M64K_DIVIDE_QUOTIENT_REMAINDER;
        request.signed_operation = signed_operation;
        request.double_width_dividend = 1'b1;
        request.update_flags = 1'b1;
        request.dividend_high = dividend_high;
        request.dividend_low = dividend_low;
        request.divisor = divisor;
        transact();
        check_response(
            expected_fault,
            successful,
            successful,
            expected_quotient & mask,
            expected_remainder & mask,
            successful,
            (expected_quotient & size_sign_bit(operand_size)) != 64'd0,
            (expected_quotient & mask) == 64'd0
        );
        retire_response();
    endtask

    task automatic check_same_width_minimum_fault_matrix(input m64k_divide_size_t operand_size);
        logic [63:0] mask;
        logic [63:0] sign_bit;

        mask = size_mask(operand_size);
        sign_bit = size_sign_bit(operand_size);
        allocate_tag(6'd5, 2'd1);
        request.operand_size = operand_size;
        request.result_form = M64K_DIVIDE_QUOTIENT_REMAINDER;
        request.signed_operation = 1'b1;
        request.double_width_dividend = 1'b0;
        request.update_flags = 1'b1;
        request.dividend_high = 64'd0;
        request.dividend_low = sign_bit;
        request.divisor = mask;
        transact();
        check_response(M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 1'b0, 1'b0, 64'd0, 64'd0, 1'b0, 1'b0, 1'b0);
        retire_response();

        allocate_tag(6'd5, 2'd1);
        request.result_form = M64K_DIVIDE_REMAINDER;
        transact();
        check_response(M64K_DIVIDE_FAULT_NONE, 1'b0, 1'b1, 64'd0, 64'd0, 1'b1, 1'b0, 1'b1);
        retire_response();

        allocate_tag(6'd5, 2'd1);
        request.result_form = M64K_DIVIDE_QUOTIENT_REMAINDER;
        request.divisor = 64'd0;
        transact();
        check_response(M64K_DIVIDE_FAULT_ZERO, 1'b0, 1'b0, 64'd0, 64'd0, 1'b0, 1'b0, 1'b0);
        retire_response();
    endtask

    task automatic check_byte_wide_boundary_partition;
        integer signed divisor_value;
        integer signed quotient_value;
        integer signed remainder_value;
        integer signed dividend_value;
        integer signed maximum_remainder_magnitude;
        logic [15:0] dividend_pattern;
        m64k_divide_fault_t expected_fault;

        for (int unsigned signed_index = 0; signed_index < 2; signed_index++) begin
            for (int unsigned divisor_bits = 0; divisor_bits < 256; divisor_bits++) begin
                divisor_value = signed_index[0] && divisor_bits >= 128 ? integer'(divisor_bits) - 256 : integer'(divisor_bits);
                if (divisor_value == 0) begin
                    for (int unsigned boundary_index = 0; boundary_index < 6; boundary_index++) begin
                        case (boundary_index)
                            0: dividend_pattern = 16'h0000;
                            1: dividend_pattern = 16'h0001;
                            2: dividend_pattern = 16'h7fff;
                            3: dividend_pattern = 16'h8000;
                            4: dividend_pattern = 16'hfffe;
                            default: dividend_pattern = 16'hffff;
                        endcase
                        check_wide_directed(
                            M64K_DIVIDE_SIZE_BYTE,
                            signed_index[0],
                            {56'd0, dividend_pattern[15:8]},
                            {56'd0, dividend_pattern[7:0]},
                            64'(divisor_bits),
                            M64K_DIVIDE_FAULT_ZERO,
                            64'd0,
                            64'd0
                        );
                    end
                    continue;
                end

                maximum_remainder_magnitude = divisor_value < 0 ? -divisor_value - 1 : divisor_value - 1;
                for (int unsigned quotient_index = 0; quotient_index < 6; quotient_index++) begin
                    if (signed_index[0]) begin
                        case (quotient_index)
                            0: quotient_value = -129;
                            1: quotient_value = -128;
                            2: quotient_value = -127;
                            3: quotient_value = 126;
                            4: quotient_value = 127;
                            default: quotient_value = 128;
                        endcase
                    end else begin
                        case (quotient_index)
                            0: quotient_value = -1;
                            1: quotient_value = 0;
                            2: quotient_value = 1;
                            3: quotient_value = 254;
                            4: quotient_value = 255;
                            default: quotient_value = 256;
                        endcase
                    end

                    for (int unsigned remainder_index = 0; remainder_index < 3; remainder_index++) begin
                        case (remainder_index)
                            0: remainder_value = 0;
                            1: remainder_value = maximum_remainder_magnitude;
                            default: remainder_value = -maximum_remainder_magnitude;
                        endcase
                        if (!signed_index[0] && remainder_index == 2) begin
                            continue;
                        end

                        dividend_value = quotient_value * divisor_value + remainder_value;
                        if (signed_index[0]) begin
                            if (dividend_value < -32768 || dividend_value > 32767) begin
                                continue;
                            end
                            if (remainder_value != 0 && ((remainder_value < 0) != (dividend_value < 0))) begin
                                continue;
                            end
                            expected_fault = quotient_value < -128 || quotient_value > 127
                                ? M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW
                                : M64K_DIVIDE_FAULT_NONE;
                        end else begin
                            if (dividend_value < 0 || dividend_value > 65535) begin
                                continue;
                            end
                            expected_fault = quotient_value > 255
                                ? M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW
                                : M64K_DIVIDE_FAULT_NONE;
                        end

                        dividend_pattern = 16'(dividend_value);
                        check_wide_directed(
                            M64K_DIVIDE_SIZE_BYTE,
                            signed_index[0],
                            {56'd0, dividend_pattern[15:8]},
                            {56'd0, dividend_pattern[7:0]},
                            64'(divisor_bits),
                            expected_fault,
                            64'(quotient_value) & 64'hff,
                            64'(remainder_value) & 64'hff
                        );
                    end
                end
            end
        end
    endtask

    task automatic check_protocol;
        m64k_divide_response_t held_response;
        m64k_execute_tag_t cancelled_tag;

        allocate_tag(6'd7, 2'd1);
        request.operand_size = M64K_DIVIDE_SIZE_QUAD;
        request.result_form = M64K_DIVIDE_QUOTIENT_REMAINDER;
        request.signed_operation = 1'b0;
        request.double_width_dividend = 1'b0;
        request.update_flags = 1'b1;
        request.dividend_low = 64'hffff_ffff_ffff_fff1;
        request.dividend_high = 64'd0;
        request.divisor = 64'd17;
        transact();
        held_response = response;

        squash_valid = 1'b1;
        squash.tag = request.tag;
        repeat (3) begin
            @(negedge clock);
            if (!response_valid || response !== held_response) begin
                $fatal(1, "published divider response changed under backpressure or matching squash");
            end
        end
        squash_valid = 1'b0;
        retire_response();

        allocate_tag(6'd2, 2'd0);
        cancelled_tag = request.tag;
        request.dividend_low = 64'hfedc_ba98_7654_3210;
        request.divisor = 64'd3;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        repeat (5) @(negedge clock);
        squash_valid = 1'b1;
        squash.tag = cancelled_tag;
        @(negedge clock);
        squash_valid = 1'b0;
        repeat (70) begin
            @(negedge clock);
            if (response_valid) begin
                $fatal(1, "squashed iterative divide published a response");
            end
        end
        if (!request_ready) begin
            $fatal(1, "divider did not return to ready after exact-tag squash");
        end

        allocate_tag(6'd6, 2'd0);
        request.dividend_low = 64'd13;
        request.divisor = 64'd3;
        @(negedge clock);
        request_valid = 1'b1;
        @(negedge clock);
        request_valid = 1'b0;
        repeat (4) @(negedge clock);
        squash_valid = 1'b1;
        squash.tag = request.tag;
        squash.tag.execution_context.hardware_thread_id = 2'd1;
        @(negedge clock);
        squash_valid = 1'b0;
        while (!response_valid) begin
            @(negedge clock);
        end
        check_response(M64K_DIVIDE_FAULT_NONE, 1'b1, 1'b1, 64'd4, 64'd1, 1'b1, 1'b0, 1'b0);
        retire_response();

        allocate_tag(6'd6, 2'd1);
        request.result_form = M64K_DIVIDE_QUOTIENT;
        request.update_flags = 1'b0;
        request.dividend_low = 64'd13;
        request.divisor = 64'd3;
        transact();
        check_response(M64K_DIVIDE_FAULT_NONE, 1'b1, 1'b0, 64'd4, 64'd0, 1'b0, 1'b0, 1'b0);
        retire_response();
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

        check_same_width_directed(M64K_DIVIDE_SIZE_BYTE, 1'b0, 64'd13, 64'd3, 64'd4, 64'd1);
        check_same_width_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'd13, 64'd3, 64'd4, 64'd1);
        check_same_width_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'd13, 64'd3, 64'd4, 64'd1);
        check_same_width_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd13, 64'd3, 64'd4, 64'd1);
        check_same_width_directed(M64K_DIVIDE_SIZE_BYTE, 1'b1, 64'hf3, 64'd3, 64'hfc, 64'hff);
        check_same_width_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'hfff3, 64'd3, 64'hfffc, 64'hffff);
        check_same_width_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'hffff_fff3, 64'd3, 64'hffff_fffc, 64'hffff_ffff);
        check_same_width_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'hffff_ffff_ffff_fff3, 64'd3, 64'hffff_ffff_ffff_fffc, 64'hffff_ffff_ffff_ffff);

        check_same_width_minimum_fault_matrix(M64K_DIVIDE_SIZE_BYTE);
        check_same_width_minimum_fault_matrix(M64K_DIVIDE_SIZE_WORD);
        check_same_width_minimum_fault_matrix(M64K_DIVIDE_SIZE_LONG);
        check_same_width_minimum_fault_matrix(M64K_DIVIDE_SIZE_QUAD);

        check_wide_directed(M64K_DIVIDE_SIZE_BYTE, 1'b0, 64'h01, 64'h00, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'h55, 64'h01);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'h0001, 64'h0000, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'h5555, 64'h0001);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'h0000_0001, 64'h0000_0000, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'h5555_5555, 64'h0000_0001);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd0, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff, M64K_DIVIDE_FAULT_NONE, 64'd1, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_BYTE, 1'b1, 64'hff, 64'hf3, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'hfc, 64'hff);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'hffff, 64'hfff3, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'hfffc, 64'hffff);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'hffff_ffff, 64'hffff_fff3, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'hffff_fffc, 64'hffff_ffff);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_fff3, 64'd3, M64K_DIVIDE_FAULT_NONE, 64'hffff_ffff_ffff_fffc, 64'hffff_ffff_ffff_ffff);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd1, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd1, 64'd0, 64'd0, M64K_DIVIDE_FAULT_ZERO, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'h8000_0000_0000_0000, 64'd0, 64'hffff_ffff_ffff_ffff, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);

        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'd0, 64'hfffe, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'hfffe, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'd0, 64'hffff, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'hffff, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'd1, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'd0, 64'd0, 64'hffff, M64K_DIVIDE_FAULT_NONE, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'hffff, 64'h7fff, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'hffff, 64'h8000, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h8000, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'hffff, 64'h8001, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h8001, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'd0, 64'h7ffe, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h7ffe, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'd0, 64'h7fff, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h7fff, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'd0, 64'h8000, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'h8000, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b1, 64'h7fff, 64'hffff, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_WORD, 1'b0, 64'hffff, 64'hffff, 64'hffff, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);

        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'd0, 64'hffff_fffe, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'hffff_fffe, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'd0, 64'hffff_ffff, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'hffff_ffff, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'd1, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'd0, 64'd0, 64'hffff_ffff, M64K_DIVIDE_FAULT_NONE, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'hffff_ffff, 64'h7fff_ffff, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'hffff_ffff, 64'h8000_0000, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h8000_0000, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'hffff_ffff, 64'h8000_0001, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h8000_0001, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'd0, 64'h7fff_fffe, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h7fff_fffe, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'd0, 64'h7fff_ffff, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h7fff_ffff, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'd0, 64'h8000_0000, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'h8000_0000, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b1, 64'h7fff_ffff, 64'hffff_ffff, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_LONG, 1'b0, 64'hffff_ffff, 64'hffff_ffff, 64'hffff_ffff, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);

        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd0, 64'hffff_ffff_ffff_fffe, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'hffff_ffff_ffff_fffe, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd0, 64'hffff_ffff_ffff_ffff, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'hffff_ffff_ffff_ffff, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd1, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'd0, 64'd0, 64'hffff_ffff_ffff_ffff, M64K_DIVIDE_FAULT_NONE, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'hffff_ffff_ffff_ffff, 64'h7fff_ffff_ffff_ffff, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'hffff_ffff_ffff_ffff, 64'h8000_0000_0000_0000, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h8000_0000_0000_0000, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'hffff_ffff_ffff_ffff, 64'h8000_0000_0000_0001, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h8000_0000_0000_0001, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'd0, 64'h7fff_ffff_ffff_fffe, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h7fff_ffff_ffff_fffe, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'd0, 64'h7fff_ffff_ffff_ffff, 64'd1, M64K_DIVIDE_FAULT_NONE, 64'h7fff_ffff_ffff_ffff, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'd0, 64'h8000_0000_0000_0000, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'h8000_0000_0000_0000, 64'd0, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b1, 64'h7fff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff, 64'd1, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);
        check_wide_directed(M64K_DIVIDE_SIZE_QUAD, 1'b0, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff, M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW, 64'd0, 64'd0);

        check_protocol();
        check_byte_wide_boundary_partition();
        check_exhaustive_byte();

        $display("m64k_scalar_divider_tb: PASS");
        $finish;
    end
endmodule
