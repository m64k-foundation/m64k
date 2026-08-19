module m64k_fetch_frontend_tb;
    import m64k_pkg::*;

    logic clk;
    logic rst_n;
    logic redirect_valid;
    logic [31:0] redirect_pc;
    logic supervisor;
    logic word_valid;
    logic word_ready;
    logic [31:0] word_pc;
    logic [15:0] word_data;
    m64k_mem_fault_t word_fault;
    logic [31:0] perf_line_requests;
    logic [31:0] perf_stale_responses;
    logic [31:0] perf_words_delivered;
    logic [31:0] perf_redirects;

    m64k_mem_if mem_bus(.clk(clk), .rst_n(rst_n));

    m64k_fetch_frontend #(.SOURCE_ID(4'h2)) frontend (
        .clk, .rst_n,
        .redirect_valid, .redirect_pc, .supervisor,
        .word_valid, .word_ready, .word_pc, .word_data, .word_fault,
        .perf_line_requests, .perf_stale_responses,
        .perf_words_delivered, .perf_redirects,
        .mem(mem_bus)
    );

    m64k_ram #(
        .BASE_ADDR(32'h0000_0000),
        .MEM_BYTES(256),
        .REQUEST_STALL_CYCLES(3)
    ) ram (
        .clk, .rst_n, .mem(mem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic redirect_to(input logic [31:0] target);
        begin
            @(negedge clk);
            redirect_pc = target;
            redirect_valid = 1'b1;
            @(negedge clk);
            redirect_valid = 1'b0;
        end
    endtask

    task automatic expect_word(
        input logic [31:0] expected_pc,
        input logic [15:0] expected_data,
        input m64k_mem_fault_t expected_fault,
        input integer blocked_cycles
    );
        integer blocked;
        logic [31:0] held_pc;
        logic [15:0] held_data;
        m64k_mem_fault_t held_fault;
        begin
            while (!word_valid)
                @(negedge clk);
            held_pc = word_pc;
            held_data = word_data;
            held_fault = word_fault;

            for (blocked = 0; blocked < blocked_cycles; blocked = blocked + 1) begin
                @(posedge clk);
                assert (word_valid);
                assert (word_pc == held_pc);
                assert (word_data == held_data);
                assert (word_fault == held_fault);
            end

            assert (word_pc == expected_pc)
                else $fatal(1, "expected fetch PC %08x, got %08x",
                            expected_pc, word_pc);
            assert (word_data == expected_data)
                else $fatal(1, "fetch @%08x expected %04x, got %04x",
                            expected_pc, expected_data, word_data);
            assert (word_fault == expected_fault)
                else $fatal(1, "fetch @%08x expected fault %0d, got %0d",
                            expected_pc, expected_fault, word_fault);

            @(negedge clk);
            word_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            word_ready = 1'b0;
        end
    endtask

    integer cycles;
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 5000)
                $fatal(1, "M64K fetch frontend test timed out");
        end
    end

    initial begin
        rst_n = 1'b0;
        redirect_valid = 1'b0;
        redirect_pc = '0;
        supervisor = 1'b1;
        word_ready = 1'b0;
        cycles = 0;

        repeat (2) @(negedge clk);
        ram.storage[8'h0e] = 8'ha0;
        ram.storage[8'h0f] = 8'ha1;
        ram.storage[8'h10] = 8'hb0;
        ram.storage[8'h11] = 8'hb1;
        ram.storage[8'h40] = 8'hca;
        ram.storage[8'h41] = 8'hfe;
        ram.storage[8'h80] = 8'hde;
        ram.storage[8'h81] = 8'had;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Start at the last word in a line, then cross into the prefetched line.
        redirect_to(32'h0000_000e);
        expect_word(32'h0000_000e, 16'ha0a1, M64K_FAULT_NONE, 3);
        expect_word(32'h0000_0010, 16'hb0b1, M64K_FAULT_NONE, 1);

        // Redirect once a request for 0x40 has entered the request channel.
        // Whether it is still blocked or already waiting for response, its
        // epoch is old and CAFe must never reach the decoder.
        redirect_to(32'h0000_0040);
        while (!(mem_bus.req_valid && (mem_bus.req.addr == 32'h0000_0040)))
            @(negedge clk);
        redirect_to(32'h0000_0080);
        expect_word(32'h0000_0080, 16'hdead, M64K_FAULT_NONE, 2);
        assert (perf_stale_responses != 0)
            else $fatal(1, "redirected response was not counted as stale");

        // A memory access fault is delivered as a token at the exact PC.
        redirect_to(32'h0000_0100);
        expect_word(32'h0000_0100, 16'h0000, M64K_FAULT_ACCESS, 1);

        // Odd instruction PCs fault locally and do not need a memory response.
        redirect_to(32'h0000_0081);
        expect_word(32'h0000_0081, 16'h0000, M64K_FAULT_ALIGNMENT, 1);

        assert (perf_redirects == 32'd5);
        assert (perf_words_delivered == 32'd5);
        assert (perf_line_requests >= 32'd4);

        $display("PASS: M64K fetch crossing, prefetch, epochs, redirects and faults");
        $finish;
    end
endmodule
