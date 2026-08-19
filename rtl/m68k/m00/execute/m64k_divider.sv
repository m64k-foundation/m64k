module m64k_divider (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [31:0] dividend,
    input  logic [15:0] divisor,
    input  logic signed_operation,
    output logic busy,
    output logic done,
    output logic [31:0] result,
    output logic divide_by_zero,
    output logic overflow,
    output logic n,
    output logic z
);
    logic [31:0] dividend_shift_q;
    logic [31:0] quotient_q;
    logic [16:0] remainder_q;
    logic [16:0] divisor_q;
    logic quotient_negative_q;
    logic remainder_negative_q;
    logic signed_operation_q;
    logic zero_divisor_q;
    logic [5:0] iteration_q;

    logic [16:0] trial_remainder;
    logic quotient_bit;
    logic [16:0] remainder_next;
    logic [31:0] quotient_next;
    logic [31:0] quotient_magnitude;
    logic [15:0] remainder_magnitude;
    logic [15:0] final_quotient;
    logic [15:0] final_remainder;
    logic final_overflow;

    always_comb begin
        trial_remainder = {remainder_q[15:0], dividend_shift_q[31]};
        quotient_bit = (trial_remainder >= divisor_q);
        remainder_next = quotient_bit ?
                         (trial_remainder - divisor_q) : trial_remainder;
        quotient_next = {quotient_q[30:0], quotient_bit};
        quotient_magnitude = quotient_next;
        remainder_magnitude = remainder_next[15:0];
        final_quotient = quotient_negative_q ?
                         (~quotient_magnitude[15:0] + 16'd1) :
                         quotient_magnitude[15:0];
        final_remainder = remainder_negative_q ?
                          (~remainder_magnitude + 16'd1) :
                          remainder_magnitude;
        final_overflow = signed_operation_q ?
            (quotient_negative_q ?
                (quotient_magnitude > 32'd32768) :
                (quotient_magnitude > 32'd32767)) :
            (quotient_magnitude > 32'h0000_ffff);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'd0;
            divide_by_zero <= 1'b0;
            overflow <= 1'b0;
            n <= 1'b0;
            z <= 1'b0;
            dividend_shift_q <= 32'd0;
            quotient_q <= 32'd0;
            remainder_q <= 17'd0;
            divisor_q <= 17'd0;
            quotient_negative_q <= 1'b0;
            remainder_negative_q <= 1'b0;
            signed_operation_q <= 1'b0;
            zero_divisor_q <= 1'b0;
            iteration_q <= 6'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                divide_by_zero <= 1'b0;
                overflow <= 1'b0;
                n <= 1'b0;
                z <= 1'b0;
                quotient_q <= 32'd0;
                remainder_q <= 17'd0;
                iteration_q <= 6'd0;
                zero_divisor_q <= (divisor == 16'd0);
                quotient_negative_q <= signed_operation &&
                    (dividend[31] ^ divisor[15]);
                remainder_negative_q <= signed_operation && dividend[31];
                signed_operation_q <= signed_operation;
                dividend_shift_q <= (signed_operation && dividend[31]) ?
                                    (~dividend + 32'd1) : dividend;
                divisor_q <= {1'b0,
                    (signed_operation && divisor[15]) ?
                    (~divisor + 16'd1) : divisor};
            end else if (busy) begin
                if (zero_divisor_q) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    divide_by_zero <= 1'b1;
                end else begin
                    dividend_shift_q <= {dividend_shift_q[30:0], 1'b0};
                    remainder_q <= remainder_next;
                    quotient_q <= quotient_next;
                    if (iteration_q == 6'd31) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        divide_by_zero <= 1'b0;
                        overflow <= final_overflow;
                        result <= {final_remainder, final_quotient};
                        n <= final_quotient[15];
                        z <= (quotient_magnitude == 32'd0);
                    end else begin
                        iteration_q <= iteration_q + 6'd1;
                    end
                end
            end
        end
    end

    property start_only_when_idle;
        @(posedge clk) disable iff (!rst_n) start |-> !busy;
    endproperty
    assert property (start_only_when_idle);

    property done_is_single_cycle;
        @(posedge clk) disable iff (!rst_n) done |=> !done;
    endproperty
    assert property (done_is_single_cycle);
endmodule
