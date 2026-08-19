module mx68k_router_tb;
    import mx68k_pkg::*;

    logic clk;
    logic rst_n;
    mx68k_mem_if upstream(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if port0(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if port1(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if port2(.clk(clk), .rst_n(rst_n));

    mx68k_router_3 #(
        .PORT0_BASE(32'h0000_0000), .PORT0_MASK(32'hffff_ff00),
        .PORT1_BASE(32'h1000_0000), .PORT1_MASK(32'hffff_ff00),
        .PORT2_BASE(32'hffff_0000), .PORT2_MASK(32'hffff_ff00)
    ) router (
        .clk, .rst_n, .upstream, .port0, .port1, .port2
    );

    mx68k_ram #(.BASE_ADDR(32'h0000_0000), .MEM_BYTES(256)) ram0 (
        .clk, .rst_n, .mem(port0)
    );
    mx68k_ram #(.BASE_ADDR(32'h1000_0000), .MEM_BYTES(256)) ram1 (
        .clk, .rst_n, .mem(port1)
    );
    mx68k_ram #(.BASE_ADDR(32'hffff_0000), .MEM_BYTES(256)) ram2 (
        .clk, .rst_n, .mem(port2)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic transact(
        input mx_mem_req_t request_value,
        input integer response_stall,
        output mx_mem_rsp_t response_value
    );
        integer stall;
        logic accepted;
        begin
            @(negedge clk);
            upstream.req = request_value;
            upstream.req_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                accepted = upstream.req_ready;
            end
            @(negedge clk);
            upstream.req_valid = 1'b0;

            upstream.rsp_ready = 1'b0;
            while (!upstream.rsp_valid)
                @(negedge clk);
            for (stall = 0; stall < response_stall; stall = stall + 1)
                @(posedge clk);

            response_value = upstream.rsp;
            @(negedge clk);
            upstream.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            upstream.rsp_ready = 1'b0;
        end
    endtask

    task automatic write_byte(
        input logic [31:0] address,
        input logic [7:0] value,
        input logic [3:0] transaction_id
    );
        mx_mem_req_t request_value;
        mx_mem_rsp_t response_value;
        begin
            request_value = '0;
            request_value.command = MX_MEM_WRITE;
            request_value.size = MX_SIZE_BYTE;
            request_value.addr = address;
            request_value.wstrb[address[3:0]] = 1'b1;
            request_value.wdata[address[3:0]*8 +: 8] = value;
            request_value.txn_id = transaction_id;
            request_value.source = 4'h5;
            transact(request_value, 1, response_value);
            assert (response_value.fault == MX_FAULT_NONE);
            assert (response_value.txn_id == transaction_id);
            assert (response_value.source == 4'h5);
            assert (response_value.rdata == '0);
            assert (!response_value.atomic_success);
        end
    endtask

    mx_mem_req_t request_value;
    mx_mem_rsp_t response_value;

    initial begin
        rst_n = 1'b0;
        upstream.req_valid = 1'b0;
        upstream.req = '0;
        upstream.rsp_ready = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        write_byte(32'h0000_0021, 8'h11, 4'h1);
        write_byte(32'h1000_0022, 8'h22, 4'h2);
        write_byte(32'hffff_0023, 8'h33, 4'h3);
        assert (ram0.storage[8'h21] == 8'h11);
        assert (ram1.storage[8'h22] == 8'h22);
        assert (ram2.storage[8'h23] == 8'h33);

        request_value = '0;
        request_value.command = MX_MEM_READ;
        request_value.size = MX_SIZE_LINE;
        request_value.addr = 32'h1000_0020;
        request_value.txn_id = 4'ha;
        request_value.source = 4'h5;
        transact(request_value, 3, response_value);
        assert (response_value.fault == MX_FAULT_NONE);
        assert (response_value.rdata[2*8 +: 8] == 8'h22);
        assert (response_value.txn_id == 4'ha);
        assert (!response_value.atomic_success);

        request_value = '0;
        request_value.command = MX_MEM_READ;
        request_value.size = MX_SIZE_LONG;
        request_value.addr = 32'h2000_0000;
        request_value.txn_id = 4'hd;
        request_value.source = 4'he;
        transact(request_value, 4, response_value);
        assert (response_value.fault == MX_FAULT_ACCESS);
        assert (response_value.txn_id == 4'hd);
        assert (response_value.source == 4'he);
        assert (!response_value.atomic_success);

        $display("PASS: MX68K three-port address router and unmapped faults");
        $finish;
    end
endmodule
