module mx68k_decode_frontend #(
    parameter logic [3:0] SOURCE_ID = 4'd0,
    parameter int unsigned EPOCH_WIDTH = 8,
    parameter int unsigned QUEUE_WORDS = 16
) (
    input logic clk,
    input logic rst_n,
    input logic redirect_valid,
    input logic [31:0] redirect_pc,
    input logic supervisor,
    input mx68k_arch_pkg::mx_profile_t profile,

    output logic instruction_valid,
    input logic instruction_ready,
    output logic [$clog2(QUEUE_WORDS+1)-1:0] instruction_words,
    output mx68k_uop_pkg::mx_uop_t instruction_uop,
    output mx68k_arch_pkg::mx_exception_t instruction_exception,

    output logic [31:0] perf_line_requests,
    output logic [31:0] perf_stale_responses,
    output logic [31:0] perf_words_delivered,
    output logic [31:0] perf_redirects,
    output logic [31:0] perf_instructions_decoded,

    mx68k_mem_if.master mem
);
    import mx68k_pkg::*;

    localparam int unsigned COUNT_WIDTH = $clog2(QUEUE_WORDS + 1);

    logic fetch_word_valid;
    logic fetch_word_ready;
    logic [31:0] fetch_word_pc;
    logic [15:0] fetch_word_data;
    mx_mem_fault_t fetch_word_fault;

    logic window_valid;
    logic [31:0] window_pc;
    logic [COUNT_WIDTH-1:0] window_count;
    logic [QUEUE_WORDS*16-1:0] window_words;
    logic [QUEUE_WORDS*4-1:0] window_faults;
    logic decode_valid;
    logic decode_need_more;
    logic [COUNT_WIDTH-1:0] decode_words;
    logic consume_valid;
    logic consume_ready;
    mx68k_arch_pkg::mx_profile_t stream_profile_q;

    mx68k_fetch_frontend #(
        .SOURCE_ID(SOURCE_ID),
        .EPOCH_WIDTH(EPOCH_WIDTH)
    ) fetch (
        .clk, .rst_n,
        .redirect_valid, .redirect_pc, .supervisor,
        .word_valid(fetch_word_valid),
        .word_ready(fetch_word_ready),
        .word_pc(fetch_word_pc),
        .word_data(fetch_word_data),
        .word_fault(fetch_word_fault),
        .perf_line_requests, .perf_stale_responses,
        .perf_words_delivered, .perf_redirects,
        .mem
    );

    mx68k_instruction_buffer #(.DEPTH_WORDS(QUEUE_WORDS)) instruction_buffer (
        .clk, .rst_n,
        .flush(redirect_valid),
        .input_valid(fetch_word_valid),
        .input_ready(fetch_word_ready),
        .input_pc(fetch_word_pc),
        .input_data(fetch_word_data),
        .input_fault(fetch_word_fault),
        .window_valid, .window_pc, .window_count,
        .window_words, .window_faults,
        .consume_valid, .consume_ready,
        .consume_words(decode_words)
    );

    mx68k_predecoder #(.WINDOW_WORDS(QUEUE_WORDS)) predecoder (
        .profile(stream_profile_q),
        .window_valid, .window_pc, .window_count,
        .window_words, .window_faults,
        .decode_valid, .decode_need_more,
        .decode_words,
        .decode_uop(instruction_uop),
        .decode_exception(instruction_exception)
    );

    assign instruction_valid = decode_valid && consume_ready && !redirect_valid;
    assign instruction_words = decode_words;
    assign consume_valid = instruction_valid && instruction_ready;

    property instruction_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            instruction_valid && !instruction_ready && !redirect_valid
            |=> redirect_valid ||
                (instruction_valid && $stable(instruction_words) &&
                 $stable(instruction_uop) && $stable(instruction_exception));
    endproperty
    assert property (instruction_stable_while_blocked);

    property incomplete_instruction_does_not_issue;
        @(posedge clk) disable iff (!rst_n)
            decode_need_more |-> !instruction_valid;
    endproperty
    assert property (incomplete_instruction_does_not_issue);

    property issued_record_has_one_outcome;
        @(posedge clk) disable iff (!rst_n)
            instruction_valid |->
                (instruction_uop.valid ^ instruction_exception.valid);
    endproperty
    assert property (issued_record_has_one_outcome);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            perf_instructions_decoded <= '0;
            stream_profile_q <= mx68k_arch_pkg::MX_PROFILE_M00;
        end else begin
            if (redirect_valid)
                stream_profile_q <= profile;
            if (instruction_valid && instruction_ready)
                perf_instructions_decoded <= perf_instructions_decoded + 1'b1;
        end
    end
endmodule
