module mx68k_instruction_buffer #(
    parameter int unsigned DEPTH_WORDS = 16
) (
    input logic clk,
    input logic rst_n,
    input logic flush,

    input logic input_valid,
    output logic input_ready,
    input logic [31:0] input_pc,
    input logic [15:0] input_data,
    input mx68k_pkg::mx_mem_fault_t input_fault,

    output logic window_valid,
    output logic [31:0] window_pc,
    output logic [$clog2(DEPTH_WORDS+1)-1:0] window_count,
    output logic [DEPTH_WORDS*16-1:0] window_words,
    output logic [DEPTH_WORDS*4-1:0] window_faults,

    input logic consume_valid,
    output logic consume_ready,
    input logic [$clog2(DEPTH_WORDS+1)-1:0] consume_words
);
    import mx68k_pkg::*;

    localparam int unsigned POINTER_WIDTH = $clog2(DEPTH_WORDS);
    localparam int unsigned COUNT_WIDTH = $clog2(DEPTH_WORDS + 1);

    logic [15:0] data_memory [0:DEPTH_WORDS-1];
    logic [31:0] pc_memory [0:DEPTH_WORDS-1];
    mx_mem_fault_t fault_memory [0:DEPTH_WORDS-1];
    logic [POINTER_WIDTH-1:0] read_pointer_q;
    logic [POINTER_WIDTH-1:0] write_pointer_q;
    logic [COUNT_WIDTH-1:0] count_q;
    logic sequence_started_q;
    logic [31:0] expected_input_pc_q;

    wire push = input_valid && input_ready;
    wire pop = consume_valid && consume_ready;

    integer output_index;
    logic [POINTER_WIDTH-1:0] buffer_index;

    initial begin
        if (DEPTH_WORDS < 2)
            $fatal(1, "mx68k_instruction_buffer DEPTH_WORDS must be at least two");
        if ((DEPTH_WORDS & (DEPTH_WORDS - 1)) != 0)
            $fatal(1, "mx68k_instruction_buffer DEPTH_WORDS must be a power of two");
    end

    always_comb begin
        input_ready = !flush && ((count_q < COUNT_WIDTH'(DEPTH_WORDS)) || pop);
        consume_ready = !flush && (consume_words != 0) &&
                        (consume_words <= count_q);
        window_valid = (count_q != 0);
        window_count = count_q;
        window_pc = window_valid ? pc_memory[read_pointer_q] : 32'd0;
        window_words = '0;
        window_faults = '0;

        for (output_index = 0; output_index < DEPTH_WORDS;
             output_index = output_index + 1) begin
            buffer_index = read_pointer_q + POINTER_WIDTH'(output_index);
            if (output_index < count_q) begin
                window_words[output_index*16 +: 16] = data_memory[buffer_index];
                window_faults[output_index*4 +: 4] = fault_memory[buffer_index];
            end
        end
    end

    property input_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            input_valid && !input_ready && !flush
            |=> flush || (input_valid && $stable(input_pc) &&
                          $stable(input_data) && $stable(input_fault));
    endproperty
    assert property (input_stable_while_blocked);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_pointer_q <= '0;
            write_pointer_q <= '0;
            count_q <= '0;
            sequence_started_q <= 1'b0;
            expected_input_pc_q <= '0;
        end else if (flush) begin
            read_pointer_q <= '0;
            write_pointer_q <= '0;
            count_q <= '0;
            sequence_started_q <= 1'b0;
            expected_input_pc_q <= '0;
        end else begin
            if (push) begin
                if (sequence_started_q && (input_pc != expected_input_pc_q))
                    $error("mx68k_instruction_buffer non-sequential PC: expected %08x, got %08x",
                           expected_input_pc_q, input_pc);
                data_memory[write_pointer_q] <= input_data;
                pc_memory[write_pointer_q] <= input_pc;
                fault_memory[write_pointer_q] <= input_fault;
                write_pointer_q <= write_pointer_q + 1'b1;
                expected_input_pc_q <= input_pc + 32'd2;
                sequence_started_q <= 1'b1;
            end

            if (pop)
                read_pointer_q <= read_pointer_q + consume_words[POINTER_WIDTH-1:0];

            case ({push, pop})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - consume_words;
                2'b11: count_q <= count_q + 1'b1 - consume_words;
                default: begin end
            endcase
        end
    end
endmodule
