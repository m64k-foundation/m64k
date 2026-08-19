module mx68k_uart_16550_model #(
    parameter logic [31:0] BASE_ADDR = 32'h00ff_f900,
    parameter bit PRINT_TX = 1'b0
) (
    input logic clk,
    input logic rst_n,
    output logic tx_valid,
    output logic [7:0] tx_data,
    mx68k_mem_if.slave mem
);
    import mx68k_pkg::*;

    localparam logic [7:0] LSR_THRE_TEMT = 8'h60;

    logic rsp_valid_q;
    mx_mem_rsp_t rsp_q;
    logic [7:0] divisor_low_q;
    logic [7:0] divisor_high_q;
    logic [7:0] interrupt_enable_q;
    logic [7:0] fifo_control_q;
    logic [7:0] line_control_q;
    mx_mem_rsp_t response_for_request;
    logic request_in_range;
    logic [31:0] request_line;
    logic [31:0] byte_address;
    logic [7:0] read_byte;

    function automatic logic [7:0] read_register(input logic [7:0] offset);
        case (offset)
            8'd0:  return line_control_q[7] ? divisor_low_q : 8'd0;
            8'd2:  return line_control_q[7] ? divisor_high_q :
                                             interrupt_enable_q;
            8'd4:  return 8'h01; // no interrupt pending
            8'd6:  return line_control_q;
            8'd10: return LSR_THRE_TEMT;
            default: return 8'd0;
        endcase
    endfunction

    always_comb begin
        request_line = mx68k_line_base(mem.req.addr);
        request_in_range = (request_line >= BASE_ADDR) &&
                           (request_line < (BASE_ADDR + 32'h100));
        response_for_request = '0;
        response_for_request.txn_id = mem.req.txn_id;
        response_for_request.source = mem.req.source;
        response_for_request.fault = request_in_range ? MX_FAULT_NONE :
                                                        MX_FAULT_ACCESS;
        byte_address = '0;
        read_byte = '0;

        if (request_in_range && (mem.req.command == MX_MEM_READ)) begin
            for (int unsigned lane = 0; lane < MX68K_LINE_BYTES;
                 lane = lane + 1) begin
                byte_address = request_line + lane;
                read_byte = read_register(byte_address[7:0] - BASE_ADDR[7:0]);
                response_for_request.rdata[lane*8 +: 8] = read_byte;
            end
        end else if (request_in_range &&
                     (mem.req.command != MX_MEM_WRITE) &&
                     (mem.req.command != MX_MEM_FENCE)) begin
            response_for_request.fault = MX_FAULT_UNSUPPORTED;
        end
    end

    assign mem.req_ready = !rsp_valid_q;
    assign mem.rsp_valid = rsp_valid_q;
    assign mem.rsp = rsp_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rsp_valid_q <= 1'b0;
            rsp_q <= '0;
            divisor_low_q <= 8'd1;
            divisor_high_q <= 8'd0;
            interrupt_enable_q <= 8'd0;
            fifo_control_q <= 8'd0;
            line_control_q <= 8'h03;
            tx_valid <= 1'b0;
            tx_data <= '0;
        end else begin
            tx_valid <= 1'b0;
            if (rsp_valid_q && mem.rsp_ready)
                rsp_valid_q <= 1'b0;

            if (mem.req_valid && mem.req_ready) begin
                rsp_q <= response_for_request;
                rsp_valid_q <= 1'b1;

                if (request_in_range && (mem.req.command == MX_MEM_WRITE)) begin
                    for (int unsigned lane = 0; lane < MX68K_LINE_BYTES;
                         lane = lane + 1) begin
                        if (mem.req.wstrb[lane]) begin
                            case ((request_line + lane) - BASE_ADDR)
                                32'd0: begin
                                    if (line_control_q[7]) begin
                                        divisor_low_q <= mem.req.wdata[lane*8 +: 8];
                                    end else begin
                                        tx_valid <= 1'b1;
                                        tx_data <= mem.req.wdata[lane*8 +: 8];
                                        if (PRINT_TX)
                                            $write("%c", mem.req.wdata[lane*8 +: 8]);
                                    end
                                end
                                32'd2: begin
                                    if (line_control_q[7])
                                        divisor_high_q <= mem.req.wdata[lane*8 +: 8];
                                    else
                                        interrupt_enable_q <= mem.req.wdata[lane*8 +: 8];
                                end
                                32'd4: fifo_control_q <= mem.req.wdata[lane*8 +: 8];
                                32'd6: line_control_q <= mem.req.wdata[lane*8 +: 8];
                                default: begin end
                            endcase
                        end
                    end
                end
            end
        end
    end
endmodule
