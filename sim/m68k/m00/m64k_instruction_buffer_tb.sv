module m64k_instruction_buffer_tb;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;
    import m64k_uop_pkg::*;

    localparam int unsigned DEPTH_WORDS = 8;
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH_WORDS + 1);

    logic clk;
    logic rst_n;
    logic flush;
    logic input_valid;
    logic input_ready;
    logic [31:0] input_pc;
    logic [15:0] input_data;
    m64k_mem_fault_t input_fault;
    logic window_valid;
    logic [31:0] window_pc;
    logic [$clog2(DEPTH_WORDS+1)-1:0] window_count;
    logic [DEPTH_WORDS*16-1:0] window_words;
    logic [DEPTH_WORDS*4-1:0] window_faults;
    logic consume_valid;
    logic consume_ready;
    logic [$clog2(DEPTH_WORDS+1)-1:0] consume_words;

    m64k_instruction_buffer #(.DEPTH_WORDS(DEPTH_WORDS)) buffer (
        .clk, .rst_n, .flush,
        .input_valid, .input_ready, .input_pc, .input_data, .input_fault,
        .window_valid, .window_pc, .window_count,
        .window_words, .window_faults,
        .consume_valid, .consume_ready, .consume_words
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic send_word(
        input logic [31:0] pc,
        input logic [15:0] data,
        input m64k_mem_fault_t fault
    );
        logic accepted;
        begin
            @(negedge clk);
            input_pc = pc;
            input_data = data;
            input_fault = fault;
            input_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                accepted = input_ready;
            end
            @(negedge clk);
            input_valid = 1'b0;
        end
    endtask

    task automatic consume(input logic [COUNT_WIDTH-1:0] words);
        logic accepted;
        begin
            @(negedge clk);
            consume_words = words;
            consume_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                accepted = consume_ready;
            end
            @(negedge clk);
            consume_valid = 1'b0;
            consume_words = '0;
        end
    endtask

    task automatic flush_buffer;
        begin
            @(negedge clk);
            flush = 1'b1;
            @(negedge clk);
            flush = 1'b0;
        end
    endtask

    m64k_uop_t sample_uop;
    integer word_index;
    integer cycles;

    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 2000)
                $fatal(1, "M64K instruction buffer test timed out");
        end
    end

    initial begin
        rst_n = 1'b0;
        flush = 1'b0;
        input_valid = 1'b0;
        input_pc = '0;
        input_data = '0;
        input_fault = M64K_FAULT_NONE;
        consume_valid = 1'b0;
        consume_words = '0;
        cycles = 0;

        sample_uop = '0;
        sample_uop.valid = 1'b1;
        sample_uop.first = 1'b1;
        sample_uop.last = 1'b1;
        sample_uop.uop_class = M64K_UCLASS_LOAD;
        sample_uop.opcode = M64K_UOP_LOAD;
        sample_uop.size = M64K_OP_LONG;
        sample_uop.profile = M64K_PROFILE_M00;
        sample_uop.flags_write = M64K_FLAG_ALL;
        assert (m64k_uop_is_memory(sample_uop));
        assert (!m64k_uop_is_control(sample_uop));
        assert (m64k_uop_writes_flags(sample_uop));
        assert (M64K_FLAG_ALL == 5'b11111);
        assert ((M64K_FLAG_X | M64K_FLAG_N | M64K_FLAG_Z | M64K_FLAG_V | M64K_FLAG_C) ==
                M64K_FLAG_ALL);

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        send_word(32'h0000_0100, 16'h4e71, M64K_FAULT_NONE);
        send_word(32'h0000_0102, 16'h6000, M64K_FAULT_NONE);
        send_word(32'h0000_0104, 16'h0004, M64K_FAULT_NONE);
        send_word(32'h0000_0106, 16'h4afc, M64K_FAULT_NONE);
        assert (window_valid && window_count == 4);
        assert (window_pc == 32'h0000_0100);
        assert (window_words[0*16 +: 16] == 16'h4e71);
        assert (window_words[1*16 +: 16] == 16'h6000);
        assert (window_words[2*16 +: 16] == 16'h0004);
        assert (window_words[3*16 +: 16] == 16'h4afc);
        assert (window_words[DEPTH_WORDS*16-1:4*16] == '0);

        consume(1);
        assert (window_pc == 32'h0000_0102 && window_count == 3);
        assert (window_words[0*16 +: 16] == 16'h6000);
        consume(2);
        assert (window_pc == 32'h0000_0106 && window_count == 1);
        assert (window_words[0*16 +: 16] == 16'h4afc);
        consume(1);
        assert (!window_valid && window_count == 0);

        // An empty queue still remembers stream continuity until a flush.
        send_word(32'h0000_0108, 16'h4e71, M64K_FAULT_NONE);
        assert (window_pc == 32'h0000_0108);

        // Flush creates a new PC stream and faults remain attached to their
        // exact extension word.
        flush_buffer();
        send_word(32'h0000_0200, 16'h6000, M64K_FAULT_NONE);
        send_word(32'h0000_0202, 16'h0000, M64K_FAULT_ACCESS);
        assert (window_count == 2);
        assert (window_faults[0*4 +: 4] == M64K_FAULT_NONE);
        assert (window_faults[1*4 +: 4] == M64K_FAULT_ACCESS);
        assert (window_faults[DEPTH_WORDS*4-1:2*4] == '0);
        consume(2);

        // Fill the circular queue, hold one producer word under backpressure,
        // then free two entries and accept it without changing the payload.
        flush_buffer();
        for (word_index = 0; word_index < DEPTH_WORDS; word_index = word_index + 1)
            send_word(32'h0000_0300 + word_index*2,
                      16'(16'h1000 + word_index), M64K_FAULT_NONE);
        assert (!input_ready && window_count == COUNT_WIDTH'(DEPTH_WORDS));

        @(negedge clk);
        input_pc = 32'h0000_0310;
        input_data = 16'h1008;
        input_fault = M64K_FAULT_NONE;
        input_valid = 1'b1;
        repeat (2) @(posedge clk);
        assert (!input_ready);

        @(negedge clk);
        consume_words = 2;
        consume_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        consume_valid = 1'b0;
        consume_words = '0;
        input_valid = 1'b0;

        assert (window_count == 7);
        assert (window_pc == 32'h0000_0304);
        assert (window_words[0*16 +: 16] == 16'h1002);
        assert (window_words[6*16 +: 16] == 16'h1008);

        $display("PASS: M64K typed uops and variable instruction buffer");
        $finish;
    end
endmodule
