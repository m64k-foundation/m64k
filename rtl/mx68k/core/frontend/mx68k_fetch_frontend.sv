module mx68k_fetch_frontend #(
    parameter logic [3:0] SOURCE_ID = 4'd0,
    parameter int unsigned EPOCH_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    input logic redirect_valid,
    input logic [31:0] redirect_pc,
    input logic supervisor,

    output logic word_valid,
    input logic word_ready,
    output logic [31:0] word_pc,
    output logic [15:0] word_data,
    output mx68k_pkg::mx_mem_fault_t word_fault,

    output logic [31:0] perf_line_requests,
    output logic [31:0] perf_stale_responses,
    output logic [31:0] perf_words_delivered,
    output logic [31:0] perf_redirects,

    mx68k_mem_if.master mem
);
    import mx68k_pkg::*;

    typedef enum logic [1:0] {
        FETCH_IDLE,
        FETCH_SEND,
        FETCH_WAIT
    } fetch_state_t;

    fetch_state_t state_q;
    logic active_q;
    logic [EPOCH_WIDTH-1:0] epoch_q;
    logic [31:0] next_line_q;
    logic [31:0] request_line_q;
    logic [EPOCH_WIDTH-1:0] request_epoch_q;
    logic request_supervisor_q;
    logic stream_supervisor_q;
    logic [31:0] fetch_pc_q;

    logic slot0_valid_q;
    logic [31:0] slot0_line_q;
    logic [127:0] slot0_data_q;
    mx_mem_fault_t slot0_fault_q;

    logic slot1_valid_q;
    logic [31:0] slot1_line_q;
    logic [127:0] slot1_data_q;
    mx_mem_fault_t slot1_fault_q;

    mx_mem_req_t memory_request;
    mx_mem_fault_t response_fault;

    wire [31:0] current_line = mx68k_line_base(fetch_pc_q);
    wire [3:0] current_lane = fetch_pc_q[3:0];
    wire slot0_is_current = slot0_valid_q && (slot0_line_q == current_line);
    wire buffered_fault = (slot0_valid_q && (slot0_fault_q != MX_FAULT_NONE)) ||
                          (slot1_valid_q && (slot1_fault_q != MX_FAULT_NONE));
    wire queue_has_space = !slot0_valid_q || !slot1_valid_q;
    wire pop_word = word_valid && word_ready;
    wire pop_line = pop_word && (current_lane == 4'he);
    wire response_handshake = (state_q == FETCH_WAIT) &&
                              mem.rsp_valid && mem.rsp_ready;
    wire response_is_current = response_handshake && !redirect_valid &&
                               (request_epoch_q == epoch_q);
    wire response_ids_match = (mem.rsp.txn_id == request_epoch_q[3:0]) &&
                              (mem.rsp.source == SOURCE_ID);

    initial begin
        if (EPOCH_WIDTH < 4)
            $fatal(1, "mx68k_fetch_frontend EPOCH_WIDTH must be at least four");
    end

    always_comb begin
        memory_request = '0;
        memory_request.command = MX_MEM_READ;
        memory_request.size = MX_SIZE_LINE;
        memory_request.addr = request_line_q;
        memory_request.txn_id = request_epoch_q[3:0];
        memory_request.source = SOURCE_ID;
        memory_request.instruction = 1'b1;
        memory_request.supervisor = request_supervisor_q;
        memory_request.cacheable = 1'b1;

        response_fault = response_ids_match ? mem.rsp.fault : MX_FAULT_BUS;

        word_valid = slot0_is_current && !redirect_valid;
        word_pc = fetch_pc_q;
        word_fault = slot0_fault_q;
        word_data = 16'h0000;
        if (slot0_is_current && (slot0_fault_q == MX_FAULT_NONE)) begin
            word_data = {
                slot0_data_q[current_lane*8 +: 8],
                slot0_data_q[(current_lane + 1'b1)*8 +: 8]
            };
        end
    end

    assign mem.req_valid = (state_q == FETCH_SEND);
    assign mem.req = memory_request;
    assign mem.rsp_ready = (state_q == FETCH_WAIT);

    property output_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            word_valid && !word_ready && !redirect_valid
            |=> redirect_valid ||
                (word_valid && $stable(word_pc) &&
                 $stable(word_data) && $stable(word_fault));
    endproperty
    assert property (output_stable_while_blocked);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= FETCH_IDLE;
            active_q <= 1'b0;
            epoch_q <= '0;
            next_line_q <= '0;
            request_line_q <= '0;
            request_epoch_q <= '0;
            request_supervisor_q <= 1'b1;
            stream_supervisor_q <= 1'b1;
            fetch_pc_q <= '0;
            slot0_valid_q <= 1'b0;
            slot0_line_q <= '0;
            slot0_data_q <= '0;
            slot0_fault_q <= MX_FAULT_NONE;
            slot1_valid_q <= 1'b0;
            slot1_line_q <= '0;
            slot1_data_q <= '0;
            slot1_fault_q <= MX_FAULT_NONE;
            perf_line_requests <= '0;
            perf_stale_responses <= '0;
            perf_words_delivered <= '0;
            perf_redirects <= '0;
        end else begin
            // Request engine. A blocked request is never withdrawn on redirect;
            // its old epoch makes the eventual response harmless.
            case (state_q)
                FETCH_IDLE: begin
                    if (active_q && queue_has_space && !buffered_fault) begin
                        request_line_q <= next_line_q;
                        request_epoch_q <= epoch_q;
                        request_supervisor_q <= stream_supervisor_q;
                        next_line_q <= next_line_q + 32'd16;
                        state_q <= FETCH_SEND;
                    end
                end

                FETCH_SEND: begin
                    if (mem.req_valid && mem.req_ready) begin
                        perf_line_requests <= perf_line_requests + 1'b1;
                        state_q <= FETCH_WAIT;
                    end
                end

                FETCH_WAIT: begin
                    if (mem.rsp_valid && mem.rsp_ready)
                        state_q <= FETCH_IDLE;
                end

                default: state_q <= FETCH_IDLE;
            endcase

            if (pop_word) begin
                perf_words_delivered <= perf_words_delivered + 1'b1;
                fetch_pc_q <= fetch_pc_q + 32'd2;

                if (slot0_fault_q != MX_FAULT_NONE) begin
                    // A fault token terminates this stream until exception
                    // handling supplies a redirect.
                    slot0_valid_q <= 1'b0;
                    slot1_valid_q <= 1'b0;
                    active_q <= 1'b0;
                end else if (pop_line) begin
                    slot0_valid_q <= slot1_valid_q;
                    slot0_line_q <= slot1_line_q;
                    slot0_data_q <= slot1_data_q;
                    slot0_fault_q <= slot1_fault_q;
                    slot1_valid_q <= 1'b0;
                end
            end

            if (response_handshake) begin
                if (!response_is_current) begin
                    perf_stale_responses <= perf_stale_responses + 1'b1;
                end else if (pop_line && !slot1_valid_q &&
                             (slot0_fault_q == MX_FAULT_NONE)) begin
                    // The decoder consumed the final word of slot 0 on the
                    // same edge that its prefetched successor arrived.
                    slot0_valid_q <= 1'b1;
                    slot0_line_q <= request_line_q;
                    slot0_data_q <= mem.rsp.rdata;
                    slot0_fault_q <= response_fault;
                    slot1_valid_q <= 1'b0;
                end else if (!slot0_valid_q) begin
                    slot0_valid_q <= 1'b1;
                    slot0_line_q <= request_line_q;
                    slot0_data_q <= mem.rsp.rdata;
                    slot0_fault_q <= response_fault;
                end else if (!slot1_valid_q) begin
                    slot1_valid_q <= 1'b1;
                    slot1_line_q <= request_line_q;
                    slot1_data_q <= mem.rsp.rdata;
                    slot1_fault_q <= response_fault;
                end else begin
                    $error("mx68k_fetch_frontend received a line with no queue space");
                end
            end

            if (redirect_valid) begin
                epoch_q <= epoch_q + 1'b1;
                next_line_q <= mx68k_line_base(redirect_pc);
                fetch_pc_q <= redirect_pc;
                stream_supervisor_q <= supervisor;
                slot0_valid_q <= redirect_pc[0];
                slot0_line_q <= mx68k_line_base(redirect_pc);
                slot0_data_q <= '0;
                slot0_fault_q <= redirect_pc[0] ?
                                 MX_FAULT_ALIGNMENT : MX_FAULT_NONE;
                slot1_valid_q <= 1'b0;
                active_q <= !redirect_pc[0];
                perf_redirects <= perf_redirects + 1'b1;

                // No request has escaped in IDLE, so cancel a speculative
                // state transition made earlier on this same edge.
                if (state_q == FETCH_IDLE)
                    state_q <= FETCH_IDLE;
            end
        end
    end
endmodule
