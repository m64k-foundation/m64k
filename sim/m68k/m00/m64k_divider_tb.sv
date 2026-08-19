module m64k_divider_tb;
    logic clk;
    logic rst_n;
    logic start;
    logic [31:0] dividend;
    logic [15:0] divisor;
    logic signed_operation;
    logic busy;
    logic done;
    logic [31:0] result;
    logic divide_by_zero;
    logic overflow;
    logic n;
    logic z;

    m64k_divider dut (.*);

    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end

    task automatic check_unsigned(
        input logic [31:0] test_dividend,
        input logic [15:0] test_divisor
    );
        logic [31:0] expected_quotient;
        logic [31:0] expected_remainder;
        logic expected_overflow;
        begin
            while (busy) @(negedge clk);
            dividend = test_dividend;
            divisor = test_divisor;
            signed_operation = 1'b0;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) @(negedge clk);
            if (test_divisor == 16'd0) begin
                assert (divide_by_zero);
            end else begin
                expected_quotient = test_dividend / test_divisor;
                expected_remainder = test_dividend % test_divisor;
                expected_overflow = expected_quotient > 32'h0000_ffff;
                assert (!divide_by_zero);
                assert (overflow == expected_overflow);
                assert (result == {expected_remainder[15:0],
                                   expected_quotient[15:0]});
                assert (n == expected_quotient[15]);
                assert (z == (expected_quotient == 32'd0));
            end
        end
    endtask

    task automatic check_signed(
        input logic signed [31:0] test_dividend,
        input logic signed [15:0] test_divisor
    );
        logic signed [63:0] expected_quotient;
        logic signed [63:0] expected_remainder;
        logic expected_overflow;
        begin
            while (busy) @(negedge clk);
            dividend = test_dividend;
            divisor = test_divisor;
            signed_operation = 1'b1;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) @(negedge clk);
            if (test_divisor == 16'sd0) begin
                assert (divide_by_zero);
            end else begin
                expected_quotient = test_dividend / test_divisor;
                expected_remainder = test_dividend % test_divisor;
                expected_overflow = (expected_quotient > 64'sd32767) ||
                                    (expected_quotient < -64'sd32768);
                assert (!divide_by_zero);
                assert (overflow == expected_overflow);
                assert (result == {expected_remainder[15:0],
                                   expected_quotient[15:0]});
                assert (n == expected_quotient[15]);
                assert (z == (expected_quotient == 64'sd0));
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        dividend = 32'd0;
        divisor = 16'd0;
        signed_operation = 1'b0;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        check_unsigned(32'd0, 16'd0);
        check_unsigned(32'd0, 16'd1);
        check_unsigned(32'hffff_ffff, 16'hffff);
        check_unsigned(32'hffff_ffff, 16'd1);
        check_unsigned(32'h0000_ffff, 16'd1);
        check_unsigned(32'h0001_0000, 16'd1);
        check_unsigned(32'h8000_0000, 16'h8000);

        check_signed(32'sd0, 16'sd0);
        check_signed(32'sd0, 16'sd1);
        check_signed(32'sd7, -16'sd3);
        check_signed(-32'sd7, 16'sd3);
        check_signed(-32'sd7, -16'sd3);
        check_signed(32'sh7fff_ffff, 16'sh7fff);
        check_signed(-32'sh8000_0000, -16'sd1);
        check_signed(-32'sh8000_0000, -16'sh8000);
        check_signed(-32'sd32768, 16'sd1);
        check_signed(-32'sd32769, 16'sd1);

        for (int test_index = 0; test_index < 2048; test_index++) begin
            check_unsigned($urandom, $urandom);
            check_signed($signed($urandom), $signed($urandom));
        end

        $display("PASS: iterative M00 word divider (boundary + 4096 randomized cases)");
        $finish;
    end
endmodule
