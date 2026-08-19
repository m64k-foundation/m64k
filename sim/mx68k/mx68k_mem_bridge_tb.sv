module mx68k_mem_bridge_tb;
    import mx68k_pkg::*;

    logic clk;
    logic rst_n;
    logic cs_n;
    logic as_n;
    logic rw_n;
    logic uds_n;
    logic lds_n;
    logic [23:1] addr;
    logic [15:0] data_out;
    logic [2:0] fc;
    logic [15:0] data_in;
    logic dtack_n;
    logic berr_n;

    mx68k_mem_if mem_bus(.clk(clk), .rst_n(rst_n));

    fx68k_mem_bridge bridge (
        .clk, .rst_n, .cs_n, .as_n, .rw_n, .uds_n, .lds_n,
        .addr, .data_out, .fc, .data_in, .dtack_n, .berr_n,
        .mem(mem_bus)
    );

    mx68k_ram #(
        .BASE_ADDR(32'h0000_0000),
        .MEM_BYTES(256),
        .REQUEST_STALL_CYCLES(2)
    ) ram (
        .clk, .rst_n, .mem(mem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    mx_mem_req_t stalled_request;
    logic request_is_stalled;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            request_is_stalled <= 1'b0;
            stalled_request <= '0;
        end else if (mem_bus.req_valid && !mem_bus.req_ready) begin
            if (request_is_stalled)
                assert (mem_bus.req == stalled_request)
                    else $fatal(1, "request changed while req_ready was low");
            else begin
                request_is_stalled <= 1'b1;
                stalled_request <= mem_bus.req;
            end
        end else begin
            request_is_stalled <= 1'b0;
        end
    end

    task automatic legacy_cycle(
        input logic [23:0] cycle_addr,
        input logic cycle_rw_n,
        input logic cycle_uds_n,
        input logic cycle_lds_n,
        input logic [15:0] cycle_data_out,
        output logic [15:0] cycle_data_in,
        output logic cycle_error
    );
        integer timeout;
        logic complete;
        begin
            @(negedge clk);
            addr = cycle_addr[23:1];
            rw_n = cycle_rw_n;
            uds_n = cycle_uds_n;
            lds_n = cycle_lds_n;
            data_out = cycle_data_out;
            cs_n = 1'b0;
            as_n = 1'b0;

            complete = 1'b0;
            cycle_data_in = '0;
            cycle_error = 1'b0;
            for (timeout = 0; timeout < 50; timeout = timeout + 1) begin
                @(negedge clk);
                if (!dtack_n || !berr_n) begin
                    complete = 1'b1;
                    cycle_data_in = data_in;
                    cycle_error = !berr_n;
                    break;
                end
            end
            if (!complete)
                $fatal(1, "legacy bus cycle timed out at %08x", cycle_addr);

            cs_n = 1'b1;
            as_n = 1'b1;
            uds_n = 1'b1;
            lds_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task automatic expect_word(
        input logic [15:0] actual,
        input logic [15:0] expected,
        input string label_text
    );
        if (actual !== expected)
            $fatal(1, "%s: expected %04x, got %04x",
                   label_text, expected, actual);
    endtask

    logic [15:0] result;
    logic error;

    initial begin
        rst_n = 1'b0;
        cs_n = 1'b1;
        as_n = 1'b1;
        rw_n = 1'b1;
        uds_n = 1'b1;
        lds_n = 1'b1;
        addr = '0;
        data_out = '0;
        fc = 3'b101;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        legacy_cycle(24'h000010, 1'b0, 1'b0, 1'b0,
                     16'h1234, result, error);
        assert (!error) else $fatal(1, "word write raised BERR");
        expect_word({ram.storage[16], ram.storage[17]}, 16'h1234,
                    "big-endian word storage");

        legacy_cycle(24'h000010, 1'b1, 1'b0, 1'b0,
                     16'h0000, result, error);
        assert (!error) else $fatal(1, "word read raised BERR");
        expect_word(result, 16'h1234, "word readback");

        legacy_cycle(24'h000012, 1'b0, 1'b0, 1'b1,
                     16'hAB00, result, error);
        assert (!error) else $fatal(1, "UDS byte write raised BERR");
        legacy_cycle(24'h000012, 1'b0, 1'b1, 1'b0,
                     16'h00CD, result, error);
        assert (!error) else $fatal(1, "LDS byte write raised BERR");
        expect_word({ram.storage[18], ram.storage[19]}, 16'hABCD,
                    "UDS/LDS byte storage");

        legacy_cycle(24'h000012, 1'b1, 1'b0, 1'b0,
                     16'h0000, result, error);
        assert (!error) else $fatal(1, "byte-composed word read raised BERR");
        expect_word(result, 16'hABCD, "byte-composed word readback");

        legacy_cycle(24'h000100, 1'b1, 1'b0, 1'b0,
                     16'h0000, result, error);
        assert (error) else $fatal(1, "out-of-range access did not raise BERR");

        $display("PASS: MX68K memory protocol, bridge, endian lanes and faults");
        $finish;
    end
endmodule
