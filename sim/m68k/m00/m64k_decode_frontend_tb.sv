module m64k_decode_frontend_tb;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;
    import m64k_uop_pkg::*;

    localparam int unsigned QUEUE_WORDS = 8;
    localparam int unsigned COUNT_WIDTH = $clog2(QUEUE_WORDS + 1);

    logic clk;
    logic rst_n;
    logic redirect_valid;
    logic [31:0] redirect_pc;
    logic supervisor;
    m64k_profile_t profile;
    logic instruction_valid;
    logic instruction_ready;
    logic [COUNT_WIDTH-1:0] instruction_words;
    m64k_uop_t instruction_uop;
    m64k_exception_t instruction_exception;
    logic [31:0] perf_line_requests;
    logic [31:0] perf_stale_responses;
    logic [31:0] perf_words_delivered;
    logic [31:0] perf_redirects;
    logic [31:0] perf_instructions_decoded;

    m64k_mem_if mem_bus(.clk(clk), .rst_n(rst_n));

    m64k_decode_frontend #(
        .SOURCE_ID(4'h3),
        .QUEUE_WORDS(QUEUE_WORDS)
    ) frontend (
        .clk, .rst_n,
        .redirect_valid, .redirect_pc, .supervisor, .profile,
        .instruction_valid, .instruction_ready, .instruction_words,
        .instruction_uop, .instruction_exception,
        .perf_line_requests, .perf_stale_responses,
        .perf_words_delivered, .perf_redirects,
        .perf_instructions_decoded,
        .mem(mem_bus)
    );

    m64k_ram #(
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

    task automatic redirect_to(input logic [31:0] target);
        begin
            @(negedge clk);
            redirect_pc = target;
            redirect_valid = 1'b1;
            @(negedge clk);
            redirect_valid = 1'b0;
        end
    endtask

    task automatic wait_for_instruction;
        begin
            while (!instruction_valid)
                @(negedge clk);
        end
    endtask

    task automatic accept_instruction;
        begin
            @(negedge clk);
            instruction_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            instruction_ready = 1'b0;
        end
    endtask

    integer cycles;
    m64k_uop_t held_uop;
    m64k_exception_t held_exception;
    logic [COUNT_WIDTH-1:0] held_words;

    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 5000)
                $fatal(1, "M64K integrated decode frontend test timed out");
        end
    end

    initial begin
        rst_n = 1'b0;
        redirect_valid = 1'b0;
        redirect_pc = '0;
        supervisor = 1'b1;
        profile = M64K_PROFILE_M00;
        instruction_ready = 1'b0;
        cycles = 0;

        repeat (2) @(negedge clk);
        // BRA.W at the last word of a line; its extension starts the next line.
        ram.storage[8'h0e] = 8'h60;
        ram.storage[8'h0f] = 8'h00;
        ram.storage[8'h10] = 8'h00;
        ram.storage[8'h11] = 8'h04;
        ram.storage[8'h14] = 8'h4e;
        ram.storage[8'h15] = 8'h72;
        ram.storage[8'h16] = 8'h27;
        ram.storage[8'h17] = 8'h00;
        // 0xfe contains BRA.W; its extension fetch at 0x100 faults.
        ram.storage[8'hfe] = 8'h60;
        ram.storage[8'hff] = 8'h00;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        redirect_to(32'h0000_000e);
        wait_for_instruction();
        assert (instruction_uop.opcode == M64K_UOP_BRANCH);
        assert (instruction_words == 2);
        assert (instruction_uop.immediate == 32'h0000_0014);
        assert (!instruction_exception.valid);

        // The complete decoded record remains stable while the backend stalls.
        held_uop = instruction_uop;
        held_exception = instruction_exception;
        held_words = instruction_words;
        profile = M64K_PROFILE_M20;
        repeat (3) begin
            @(posedge clk);
            assert (instruction_valid);
            assert (instruction_uop == held_uop);
            assert (instruction_exception == held_exception);
            assert (instruction_words == held_words);
        end
        profile = M64K_PROFILE_M00;
        accept_instruction();

        redirect_to(32'h0000_0014);
        wait_for_instruction();
        assert (instruction_uop.opcode == M64K_UOP_STOP);
        assert (instruction_uop.immediate == 32'h0000_2700);
        assert (instruction_uop.privileged && instruction_words == 2);
        accept_instruction();

        redirect_to(32'h0000_00fe);
        wait_for_instruction();
        assert (!instruction_uop.valid && instruction_exception.valid);
        assert (instruction_exception.exception_class == M64K_EXC_FETCH);
        assert (instruction_exception.vector == M64K_VECTOR_ACCESS_FAULT);
        assert (instruction_exception.instruction_pc == 32'h0000_00fe);
        assert (instruction_exception.next_pc == 32'h0000_0100);
        assert (instruction_words == 2);
        accept_instruction();

        redirect_to(32'h0000_0041);
        wait_for_instruction();
        assert (!instruction_uop.valid && instruction_exception.valid);
        assert (instruction_exception.vector == M64K_VECTOR_ADDRESS_ERROR);
        assert (instruction_exception.instruction_pc == 32'h0000_0041);
        accept_instruction();

        assert (perf_instructions_decoded == 32'd4);
        assert (perf_redirects == 32'd4);
        assert (perf_words_delivered >= 32'd7);
        assert (perf_line_requests >= 32'd4);
        assert (perf_stale_responses == 32'd0);

        $display("PASS: M64K fetch-to-decode integration, stalls, redirects and faults");
        $finish;
    end
endmodule
