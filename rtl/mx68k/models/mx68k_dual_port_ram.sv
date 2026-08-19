// Behavioural coherent instruction/data RAM for simulation and FPGA-neutral
// platform models.  The instruction port is read-only; the data port owns all
// writes.  Independent response queues let instruction fetch and data traffic
// complete concurrently, matching the split-I/D MX68K core interface without
// duplicating the underlying bytes.
module mx68k_dual_port_ram #(
    parameter logic [31:0] BASE_ADDR = 32'h0000_0000,
    parameter int unsigned MEM_BYTES = 4096,
    parameter bit CLEAR_ON_INIT = 1'b1
) (
    input logic clk,
    input logic rst_n,
    mx68k_mem_if.slave imem,
    mx68k_mem_if.slave dmem
);
    import mx68k_pkg::*;

    logic [7:0] storage [0:MEM_BYTES-1];
    logic imem_rsp_valid_q;
    logic dmem_rsp_valid_q;
    mx_mem_rsp_t imem_rsp_q;
    mx_mem_rsp_t dmem_rsp_q;

    wire [31:0] imem_line = mx68k_line_base(imem.req.addr);
    wire [32:0] imem_delta = {1'b0, imem_line} - {1'b0, BASE_ADDR};
    wire [32:0] imem_end_offset = imem_delta + 33'd16;
    wire imem_in_range = !imem_delta[32] &&
                         (imem_end_offset <= {1'b0, MEM_BYTES});

    wire [31:0] dmem_line = mx68k_line_base(dmem.req.addr);
    wire [32:0] dmem_delta = {1'b0, dmem_line} - {1'b0, BASE_ADDR};
    wire [32:0] dmem_end_offset = dmem_delta + 33'd16;
    wire dmem_in_range = !dmem_delta[32] &&
                         (dmem_end_offset <= {1'b0, MEM_BYTES});

    mx_mem_rsp_t imem_response_for_request;
    mx_mem_rsp_t dmem_response_for_request;
    integer init_index;

    initial begin
        if ((MEM_BYTES == 0) || ((MEM_BYTES % MX68K_LINE_BYTES) != 0))
            $fatal(1, "mx68k_dual_port_ram MEM_BYTES must be a non-zero multiple of 16");
        if (BASE_ADDR[3:0] != 4'b0000)
            $fatal(1, "mx68k_dual_port_ram BASE_ADDR must be 16-byte aligned");
        if (CLEAR_ON_INIT)
            for (init_index = 0; init_index < MEM_BYTES; init_index = init_index + 1)
                storage[init_index] = 8'h00;
    end

    always_comb begin
        imem_response_for_request = '0;
        imem_response_for_request.txn_id = imem.req.txn_id;
        imem_response_for_request.source = imem.req.source;
        imem_response_for_request.fault = MX_FAULT_NONE;

        if (!imem_in_range) begin
            imem_response_for_request.fault = MX_FAULT_ACCESS;
        end else if (imem.req.command != MX_MEM_READ) begin
            imem_response_for_request.fault = MX_FAULT_UNSUPPORTED;
        end else begin
            for (int unsigned lane = 0; lane < MX68K_LINE_BYTES; lane = lane + 1)
                imem_response_for_request.rdata[lane*8 +: 8] =
                    storage[imem_delta[31:0] + lane];
        end
    end

    always_comb begin
        dmem_response_for_request = '0;
        dmem_response_for_request.txn_id = dmem.req.txn_id;
        dmem_response_for_request.source = dmem.req.source;
        dmem_response_for_request.fault = MX_FAULT_NONE;

        if (!dmem_in_range) begin
            dmem_response_for_request.fault = MX_FAULT_ACCESS;
        end else begin
            case (dmem.req.command)
                MX_MEM_READ: begin
                    for (int unsigned lane = 0; lane < MX68K_LINE_BYTES; lane = lane + 1)
                        dmem_response_for_request.rdata[lane*8 +: 8] =
                            storage[dmem_delta[31:0] + lane];
                end
                MX_MEM_WRITE,
                MX_MEM_FENCE: dmem_response_for_request.fault = MX_FAULT_NONE;
                MX_MEM_ATOMIC: begin
                    if (dmem.req.atomic_op == MX_ATOMIC_OR) begin
                        for (int unsigned lane = 0;
                             lane < MX68K_LINE_BYTES; lane = lane + 1)
                            dmem_response_for_request.rdata[lane*8 +: 8] =
                                storage[dmem_delta[31:0] + lane];
                        dmem_response_for_request.atomic_success = 1'b1;
                    end else begin
                        dmem_response_for_request.fault = MX_FAULT_UNSUPPORTED;
                    end
                end
                default: dmem_response_for_request.fault = MX_FAULT_UNSUPPORTED;
            endcase
        end
    end

    assign imem.req_ready = !imem_rsp_valid_q;
    assign imem.rsp_valid = imem_rsp_valid_q;
    assign imem.rsp = imem_rsp_q;
    assign dmem.req_ready = !dmem_rsp_valid_q;
    assign dmem.rsp_valid = dmem_rsp_valid_q;
    assign dmem.rsp = dmem_rsp_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_rsp_valid_q <= 1'b0;
            dmem_rsp_valid_q <= 1'b0;
            imem_rsp_q <= '0;
            dmem_rsp_q <= '0;
        end else begin
            if (imem_rsp_valid_q && imem.rsp_ready)
                imem_rsp_valid_q <= 1'b0;
            if (dmem_rsp_valid_q && dmem.rsp_ready)
                dmem_rsp_valid_q <= 1'b0;

            if (imem.req_valid && imem.req_ready) begin
                imem_rsp_q <= imem_response_for_request;
                imem_rsp_valid_q <= 1'b1;
            end

            if (dmem.req_valid && dmem.req_ready) begin
                dmem_rsp_q <= dmem_response_for_request;
                dmem_rsp_valid_q <= 1'b1;
                if (dmem_in_range && (dmem.req.command == MX_MEM_WRITE)) begin
                    for (int unsigned lane = 0; lane < MX68K_LINE_BYTES; lane = lane + 1)
                        if (dmem.req.wstrb[lane])
                            storage[dmem_delta[31:0] + lane] <=
                                dmem.req.wdata[lane*8 +: 8];
                end else if (dmem_in_range &&
                             (dmem.req.command == MX_MEM_ATOMIC) &&
                             (dmem.req.atomic_op == MX_ATOMIC_OR)) begin
                    for (int unsigned lane = 0;
                         lane < MX68K_LINE_BYTES; lane = lane + 1)
                        if (dmem.req.wstrb[lane])
                            storage[dmem_delta[31:0] + lane] <=
                                storage[dmem_delta[31:0] + lane] |
                                dmem.req.wdata[lane*8 +: 8];
                end
            end
        end
    end
endmodule
