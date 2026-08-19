module fx68k_mem_bridge #(
    parameter logic [3:0] SOURCE_ID = 4'd0,
    parameter bit CACHEABLE = 1'b1
) (
    input logic clk,
    input logic rst_n,

    input logic cs_n,
    input logic as_n,
    input logic rw_n,
    input logic uds_n,
    input logic lds_n,
    input logic [23:1] addr,
    input logic [15:0] data_out,
    input logic [2:0] fc,

    output logic [15:0] data_in,
    output logic dtack_n,
    output logic berr_n,

    m64k_mem_if.master mem
);
    import m64k_pkg::*;

    typedef enum logic [2:0] {
        BRIDGE_IDLE,
        BRIDGE_SEND,
        BRIDGE_WAIT,
        BRIDGE_ACK,
        BRIDGE_ERROR
    } bridge_state_t;

    bridge_state_t state_q;
    m64k_mem_req_t request_q;
    m64k_mem_req_t request_from_bus;
    logic [15:0] read_data_q;
    logic [3:0] lane_q;

    wire cycle_active = !cs_n && !as_n && (!uds_n || !lds_n);
    wire [31:0] byte_addr = {8'b0, addr, 1'b0};
    wire [3:0] bus_lane = byte_addr[3:0];
    wire instruction_cycle = (fc == 3'b010) || (fc == 3'b110);

    always_comb begin
        request_from_bus = '0;
        request_from_bus.command = rw_n ? M64K_MEM_READ : M64K_MEM_WRITE;
        request_from_bus.size = (!uds_n && !lds_n) ? M64K_SIZE_WORD : M64K_SIZE_BYTE;
        request_from_bus.atomic_op = M64K_ATOMIC_NONE;
        request_from_bus.addr = byte_addr;
        request_from_bus.source = SOURCE_ID;
        request_from_bus.instruction = instruction_cycle;
        request_from_bus.supervisor = fc[2];
        request_from_bus.cacheable = CACHEABLE;
        request_from_bus.ordered = 1'b0;
        request_from_bus.lock = 1'b0;

        if (!uds_n) begin
            request_from_bus.wstrb[bus_lane] = 1'b1;
            request_from_bus.wdata[bus_lane*8 +: 8] = data_out[15:8];
        end
        if (!lds_n) begin
            request_from_bus.wstrb[bus_lane + 1'b1] = 1'b1;
            request_from_bus.wdata[(bus_lane + 1'b1)*8 +: 8] = data_out[7:0];
        end
    end

    assign mem.req_valid = (state_q == BRIDGE_SEND);
    assign mem.req = request_q;
    assign mem.rsp_ready = (state_q == BRIDGE_WAIT);

    assign data_in = read_data_q;
    assign dtack_n = (state_q == BRIDGE_ACK) ? 1'b0 : 1'b1;
    assign berr_n = (state_q == BRIDGE_ERROR) ? 1'b0 : 1'b1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= BRIDGE_IDLE;
            request_q <= '0;
            read_data_q <= '0;
            lane_q <= '0;
        end else begin
            case (state_q)
                BRIDGE_IDLE: begin
                    if (cycle_active) begin
                        request_q <= request_from_bus;
                        lane_q <= bus_lane;
                        state_q <= BRIDGE_SEND;
                    end
                end

                BRIDGE_SEND: begin
                    if (mem.req_valid && mem.req_ready)
                        state_q <= BRIDGE_WAIT;
                end

                BRIDGE_WAIT: begin
                    if (mem.rsp_valid && mem.rsp_ready) begin
                        read_data_q <= {
                            mem.rsp.rdata[lane_q*8 +: 8],
                            mem.rsp.rdata[(lane_q + 1'b1)*8 +: 8]
                        };
                        if (mem.rsp.fault == M64K_FAULT_NONE)
                            state_q <= BRIDGE_ACK;
                        else
                            state_q <= BRIDGE_ERROR;
                    end
                end

                BRIDGE_ACK,
                BRIDGE_ERROR: begin
                    if (as_n || cs_n)
                        state_q <= BRIDGE_IDLE;
                end

                default: state_q <= BRIDGE_IDLE;
            endcase
        end
    end
endmodule
