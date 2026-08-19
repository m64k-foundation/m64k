module m64k_ram_protocol_tb;
    import m64k_pkg::*;

    logic clk;
    logic rst_n;
    m64k_mem_if mem_bus(.clk(clk), .rst_n(rst_n));

    m64k_ram #(
        .BASE_ADDR(32'h1000_0000),
        .MEM_BYTES(256),
        .REQUEST_STALL_CYCLES(1),
        .INJECT_FAULT_ENABLE(1'b1),
        .INJECT_FAULT_WRITE(1'b1),
        .INJECT_FAULT_WRITE_ADDR(32'h1000_0043)
    ) ram (
        .clk, .rst_n, .mem(mem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic send_request(input m64k_mem_req_t request_value);
        logic accepted;
        begin
            @(negedge clk);
            mem_bus.req = request_value;
            mem_bus.req_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                accepted = mem_bus.req_ready;
            end
            @(negedge clk);
            mem_bus.req_valid = 1'b0;
        end
    endtask

    task automatic receive_response(
        input integer blocked_cycles,
        output m64k_mem_rsp_t response_value
    );
        integer blocked;
        m64k_mem_rsp_t held_response;
        begin
            mem_bus.rsp_ready = 1'b0;
            while (!mem_bus.rsp_valid)
                @(negedge clk);

            held_response = mem_bus.rsp;
            for (blocked = 0; blocked < blocked_cycles; blocked = blocked + 1) begin
                @(posedge clk);
                assert (mem_bus.rsp_valid)
                    else $fatal(1, "RAM dropped blocked response");
                assert (mem_bus.rsp == held_response)
                    else $fatal(1, "RAM changed blocked response");
            end

            @(negedge clk);
            mem_bus.rsp_ready = 1'b1;
            @(posedge clk);
            response_value = mem_bus.rsp;
            @(negedge clk);
            mem_bus.rsp_ready = 1'b0;
        end
    endtask

    m64k_mem_req_t request_value;
    m64k_mem_rsp_t response_value;

    initial begin
        rst_n = 1'b0;
        mem_bus.req_valid = 1'b0;
        mem_bus.req = '0;
        mem_bus.rsp_ready = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        request_value = '0;
        request_value.command = M64K_MEM_WRITE;
        request_value.size = M64K_SIZE_BYTE;
        request_value.addr = 32'h1000_0023;
        request_value.wstrb[3] = 1'b1;
        request_value.wdata[3*8 +: 8] = 8'h25;
        request_value.txn_id = 4'h9;
        request_value.source = 4'h3;
        send_request(request_value);
        receive_response(3, response_value);
        assert (response_value.fault == M64K_FAULT_NONE);
        assert (!response_value.atomic_success);
        assert (response_value.txn_id == 4'h9 && response_value.source == 4'h3);

        request_value = '0;
        request_value.command = M64K_MEM_READ;
        request_value.size = M64K_SIZE_LINE;
        request_value.addr = 32'h1000_0020;
        request_value.txn_id = 4'ha;
        request_value.source = 4'h3;
        send_request(request_value);
        receive_response(2, response_value);
        assert (response_value.fault == M64K_FAULT_NONE);
        assert (!response_value.atomic_success);
        assert (response_value.rdata[3*8 +: 8] == 8'h25);
        assert (response_value.txn_id == 4'ha && response_value.source == 4'h3);

        // The endpoint performs TAS's OR as one indivisible transaction and
        // returns the complete line from before the update.
        request_value = '0;
        request_value.command = M64K_MEM_ATOMIC;
        request_value.size = M64K_SIZE_BYTE;
        request_value.atomic_op = M64K_ATOMIC_OR;
        request_value.addr = 32'h1000_0023;
        request_value.wstrb[3] = 1'b1;
        request_value.wdata[3*8 +: 8] = 8'h80;
        request_value.txn_id = 4'hb;
        request_value.source = 4'h3;
        request_value.ordered = 1'b1;
        request_value.lock = 1'b1;
        send_request(request_value);
        receive_response(1, response_value);
        assert (response_value.fault == M64K_FAULT_NONE);
        assert (response_value.atomic_success);
        assert (response_value.rdata[3*8 +: 8] == 8'h25);

        request_value = '0;
        request_value.command = M64K_MEM_READ;
        request_value.size = M64K_SIZE_LINE;
        request_value.addr = 32'h1000_0020;
        send_request(request_value);
        receive_response(0, response_value);
        assert (response_value.rdata[3*8 +: 8] == 8'ha5);

        request_value = '0;
        request_value.command = M64K_MEM_ATOMIC;
        request_value.size = M64K_SIZE_BYTE;
        request_value.atomic_op = M64K_ATOMIC_SWAP;
        request_value.addr = 32'h1000_0023;
        request_value.wstrb[3] = 1'b1;
        request_value.wdata[3*8 +: 8] = 8'h00;
        send_request(request_value);
        receive_response(0, response_value);
        assert (response_value.fault == M64K_FAULT_UNSUPPORTED);
        assert (!response_value.atomic_success);

        // A faulting atomic is one failed transaction: it must neither report
        // success nor perform the indivisible update. Fault injection treats
        // atomics as write-classified accesses, matching the core's group-0
        // frame classification for TAS.
        ram.storage[8'h43] = 8'h11;
        request_value = '0;
        request_value.command = M64K_MEM_ATOMIC;
        request_value.size = M64K_SIZE_BYTE;
        request_value.atomic_op = M64K_ATOMIC_OR;
        request_value.addr = 32'h1000_0043;
        request_value.wstrb[3] = 1'b1;
        request_value.wdata[3*8 +: 8] = 8'h80;
        request_value.ordered = 1'b1;
        request_value.lock = 1'b1;
        send_request(request_value);
        receive_response(0, response_value);
        assert (response_value.fault == M64K_FAULT_ACCESS);
        assert (!response_value.atomic_success);
        assert (ram.storage[8'h43] == 8'h11);

        $display("PASS: M64K RAM backpressure, indivisible atomic OR and fault suppression");
        $finish;
    end
endmodule
