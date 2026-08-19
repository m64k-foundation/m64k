module m64k_peripherals_tb;
    import m64k_pkg::*;

    localparam logic [31:0] UART_BASE = 32'h00f0_0000;
    localparam logic [31:0] TIMER_BASE = 32'h00f0_1000;
    localparam logic [31:0] SYSINFO_BASE = 32'h00f0_2000;

    logic clk;
    logic rst_n;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic uart_tx_ready;
    logic uart_rx_valid;
    logic [7:0] uart_rx_data;
    logic uart_rx_ready;
    logic uart_irq_pending;
    logic timer_irq_pending;
    logic uart_tx_seen;
    logic [7:0] uart_tx_seen_data;
    integer uart_tx_count;
    integer cycles;
    integer test_stage;

    m64k_mem_if uart_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if timer_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if sysinfo_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if error_bus(.clk(clk), .rst_n(rst_n));

    m64k_uart #(.BASE_ADDR(UART_BASE)) uart (
        .clk, .rst_n,
        .tx_valid(uart_tx_valid), .tx_data(uart_tx_data),
        .tx_ready(uart_tx_ready),
        .rx_valid(uart_rx_valid), .rx_data(uart_rx_data),
        .rx_ready(uart_rx_ready), .irq_pending(uart_irq_pending),
        .mem(uart_bus)
    );

    m64k_timer #(.BASE_ADDR(TIMER_BASE)) timer (
        .clk, .rst_n, .irq_pending(timer_irq_pending), .mem(timer_bus)
    );

    m64k_sysinfo #(
        .BASE_ADDR(SYSINFO_BASE),
        .CORE_COUNT(4), .CORE_ID(2), .THREAD_ID(1),
        .PHYS_ADDR_WIDTH(32), .RAM_BYTES(4 * 1024 * 1024)
    ) sysinfo (
        .clk, .rst_n, .mem(sysinfo_bus)
    );

    m64k_error_slave #(.FAULT(M64K_FAULT_TIMEOUT)) error_target (
        .clk, .rst_n, .mem(error_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            uart_tx_seen <= 1'b0;
            uart_tx_seen_data <= '0;
            uart_tx_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (uart_tx_valid && uart_tx_ready) begin
                uart_tx_seen <= 1'b1;
                uart_tx_seen_data <= uart_tx_data;
                uart_tx_count <= uart_tx_count + 1;
            end
            if (cycles > 500)
                $fatal(1, "M64K platform peripheral test timed out at stage %0d",
                       test_stage);
        end
    end

    function automatic logic [31:0] line_be32(
        input logic [M64K_LINE_BITS-1:0] rdata,
        input int unsigned lane
    );
        return {rdata[(lane + 0)*8 +: 8],
                rdata[(lane + 1)*8 +: 8],
                rdata[(lane + 2)*8 +: 8],
                rdata[(lane + 3)*8 +: 8]};
    endfunction

    task automatic uart_transaction(
        input m64k_mem_req_t request,
        output m64k_mem_rsp_t response
    );
        begin
            @(negedge clk);
            uart_bus.req = request;
            uart_bus.req_valid = 1'b1;
            uart_bus.rsp_ready = 1'b0;
            while (!uart_bus.req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            uart_bus.req_valid = 1'b0;
            while (!uart_bus.rsp_valid)
                @(negedge clk);
            response = uart_bus.rsp;
            uart_bus.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            uart_bus.rsp_ready = 1'b0;
        end
    endtask

    task automatic timer_transaction(
        input m64k_mem_req_t request,
        output m64k_mem_rsp_t response
    );
        begin
            @(negedge clk);
            timer_bus.req = request;
            timer_bus.req_valid = 1'b1;
            timer_bus.rsp_ready = 1'b0;
            while (!timer_bus.req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            timer_bus.req_valid = 1'b0;
            while (!timer_bus.rsp_valid)
                @(negedge clk);
            response = timer_bus.rsp;
            timer_bus.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            timer_bus.rsp_ready = 1'b0;
        end
    endtask

    task automatic sysinfo_transaction(
        input m64k_mem_req_t request,
        output m64k_mem_rsp_t response
    );
        begin
            @(negedge clk);
            sysinfo_bus.req = request;
            sysinfo_bus.req_valid = 1'b1;
            sysinfo_bus.rsp_ready = 1'b0;
            while (!sysinfo_bus.req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            sysinfo_bus.req_valid = 1'b0;
            while (!sysinfo_bus.rsp_valid)
                @(negedge clk);
            response = sysinfo_bus.rsp;
            sysinfo_bus.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            sysinfo_bus.rsp_ready = 1'b0;
        end
    endtask

    task automatic error_transaction(
        input m64k_mem_req_t request,
        output m64k_mem_rsp_t response
    );
        begin
            @(negedge clk);
            error_bus.req = request;
            error_bus.req_valid = 1'b1;
            error_bus.rsp_ready = 1'b0;
            while (!error_bus.req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            error_bus.req_valid = 1'b0;
            while (!error_bus.rsp_valid)
                @(negedge clk);
            response = error_bus.rsp;
            error_bus.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            error_bus.rsp_ready = 1'b0;
        end
    endtask

    initial begin
        m64k_mem_req_t request;
        m64k_mem_rsp_t response;

        rst_n = 1'b0;
        cycles = 0;
        test_stage = 0;
        uart_rx_valid = 1'b0;
        uart_rx_data = '0;
        uart_tx_ready = 1'b1;
        uart_bus.req_valid = 1'b0;
        uart_bus.req = '0;
        uart_bus.rsp_ready = 1'b0;
        timer_bus.req_valid = 1'b0;
        timer_bus.req = '0;
        timer_bus.rsp_ready = 1'b0;
        sysinfo_bus.req_valid = 1'b0;
        sysinfo_bus.req = '0;
        sysinfo_bus.rsp_ready = 1'b0;
        error_bus.req_valid = 1'b0;
        error_bus.req = '0;
        error_bus.rsp_ready = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        request = '0;
        test_stage = 1;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_BYTE;
        request.addr = UART_BASE + 32'd8;
        request.txn_id = 4'h1;
        request.source = 4'h2;
        uart_transaction(request, response);
        assert (response.fault == M64K_FAULT_NONE);
        assert (response.txn_id == 4'h1 && response.source == 4'h2);
        assert (response.rdata[8*8 +: 8] == 8'h01);

        request = '0;
        test_stage = 2;
        request.command = M64K_MEM_WRITE;
        request.size = M64K_SIZE_BYTE;
        request.addr = UART_BASE;
        request.wstrb[0] = 1'b1;
        request.wdata[7:0] = "M";
        uart_transaction(request, response);
        assert (response.fault == M64K_FAULT_NONE);
        assert (uart_tx_seen && uart_tx_seen_data == "M");
        assert (uart_tx_count == 1);

        // A first byte may occupy the transmit holding register.  A second
        // write must then remain blocked, with a stable request, until the
        // downstream transmitter accepts the buffered byte.
        uart_tx_ready = 1'b0;
        request.wdata = '0;
        request.wdata[7:0] = "B";
        uart_transaction(request, response);
        assert (response.fault == M64K_FAULT_NONE);
        assert (uart_tx_valid && uart_tx_data == "B");
        assert (uart_tx_count == 1);

        request.wdata[7:0] = "C";
        fork
            begin
                uart_transaction(request, response);
            end
            begin
                repeat (3) @(posedge clk);
                assert (uart_bus.req_valid && !uart_bus.req_ready);
                assert (uart_tx_valid && uart_tx_data == "B");
                #1;
                uart_tx_ready = 1'b1;
            end
        join
        repeat (2) @(negedge clk);
        assert (response.fault == M64K_FAULT_NONE);
        assert (uart_tx_count == 3 && uart_tx_seen_data == "C");

        request = '0;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_BYTE;
        request.addr = UART_BASE + 32'd1;
        uart_transaction(request, response);
        assert (response.fault == M64K_FAULT_ACCESS);

        request.wstrb = '0;
        test_stage = 3;
        request.wdata = '0;
        request.command = M64K_MEM_WRITE;
        request.size = M64K_SIZE_BYTE;
        request.addr = UART_BASE + 32'd12;
        request.wstrb[12] = 1'b1;
        request.wdata[12*8] = 1'b1;
        uart_transaction(request, response);
        assert (!uart_irq_pending);

        @(negedge clk);
        test_stage = 4;
        assert (uart_rx_ready);
        uart_rx_data = "R";
        uart_rx_valid = 1'b1;
        @(negedge clk);
        uart_rx_valid = 1'b0;
        assert (!uart_rx_ready && uart_irq_pending);

        request = '0;
        test_stage = 5;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_BYTE;
        request.addr = UART_BASE + 32'd4;
        uart_transaction(request, response);
        assert (response.rdata[4*8 +: 8] == "R");
        @(negedge clk);
        assert (uart_rx_ready && !uart_irq_pending);

        request = '0;
        test_stage = 6;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_LONG;
        request.addr = TIMER_BASE;
        timer_transaction(request, response);
        assert (response.fault == M64K_FAULT_NONE);
        assert (!response.atomic_success);

        request = '0;
        test_stage = 7;
        request.command = M64K_MEM_WRITE;
        request.size = M64K_SIZE_LONG;
        request.addr = TIMER_BASE + 32'd4;
        request.wstrb[7:4] = 4'hf;
        request.wdata[4*8 +: 8] = 8'h00;
        request.wdata[5*8 +: 8] = 8'h00;
        request.wdata[6*8 +: 8] = 8'h00;
        request.wdata[7*8 +: 8] = 8'h06;
        timer_transaction(request, response);

        request = '0;
        test_stage = 8;
        request.command = M64K_MEM_WRITE;
        request.size = M64K_SIZE_BYTE;
        request.addr = TIMER_BASE + 32'd8;
        request.wstrb[8] = 1'b1;
        request.wdata[8*8 +: 8] = 8'b0000_0101;
        timer_transaction(request, response);
        wait (timer_irq_pending);
        assert (timer_irq_pending);

        request = '0;
        test_stage = 9;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_BYTE;
        request.addr = TIMER_BASE + 32'd12;
        timer_transaction(request, response);
        assert (response.rdata[12*8] == 1'b1);

        request = '0;
        test_stage = 10;
        request.command = M64K_MEM_WRITE;
        request.size = M64K_SIZE_BYTE;
        request.addr = TIMER_BASE + 32'd12;
        request.wstrb[12] = 1'b1;
        request.wdata[12*8] = 1'b1;
        timer_transaction(request, response);
        @(negedge clk);
        assert (!timer_irq_pending);

        request = '0;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_LONG;
        request.addr = TIMER_BASE + 32'd12;
        timer_transaction(request, response);
        assert (response.fault == M64K_FAULT_ACCESS);

        request.command = M64K_MEM_ATOMIC;
        request.size = M64K_SIZE_BYTE;
        request.atomic_op = M64K_ATOMIC_OR;
        timer_transaction(request, response);
        assert (response.fault == M64K_FAULT_UNSUPPORTED);

        request = '0;
        test_stage = 11;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_LONG;
        request.addr = SYSINFO_BASE;
        sysinfo_transaction(request, response);
        assert (response.fault == M64K_FAULT_NONE);
        assert (line_be32(response.rdata, 0) == 32'h4d36_344b);
        assert (response.rdata[4*8 +: 8] == 8'h00 &&
                response.rdata[5*8 +: 8] == 8'h01);
        assert (line_be32(response.rdata, 8) == 32'h0000_0001);
        assert (line_be32(response.rdata, 12) == 32'd4);

        request.addr = SYSINFO_BASE + 32'h04;
        request.size = M64K_SIZE_WORD;
        sysinfo_transaction(request, response);
        assert (response.fault == M64K_FAULT_NONE);
        assert ({response.rdata[4*8 +: 8], response.rdata[5*8 +: 8]} ==
                16'h0001);

        request.addr = SYSINFO_BASE + 32'h10;
        request.size = M64K_SIZE_LONG;
        test_stage = 12;
        sysinfo_transaction(request, response);
        assert (line_be32(response.rdata, 0) == 32'd2);
        assert (line_be32(response.rdata, 4) == 32'd1);
        assert (line_be32(response.rdata, 8) == 32'd32);
        assert (line_be32(response.rdata, 12) == 32'h0040_0000);

        request.command = M64K_MEM_WRITE;
        test_stage = 13;
        request.size = M64K_SIZE_LONG;
        request.addr = SYSINFO_BASE;
        request.wstrb[3:0] = 4'hf;
        sysinfo_transaction(request, response);
        assert (response.fault == M64K_FAULT_ACCESS);

        request.command = M64K_MEM_ATOMIC;
        request.atomic_op = M64K_ATOMIC_OR;
        sysinfo_transaction(request, response);
        assert (response.fault == M64K_FAULT_UNSUPPORTED);

        request = '0;
        test_stage = 14;
        request.command = M64K_MEM_READ;
        request.size = M64K_SIZE_LONG;
        request.addr = 32'hdead_beef;
        request.txn_id = 4'ha;
        request.source = 4'hb;
        error_transaction(request, response);
        assert (response.fault == M64K_FAULT_TIMEOUT);
        assert (response.txn_id == 4'ha && response.source == 4'hb);

        $display("PASS: M64K UART, timer, sysinfo and error-slave contracts");
        $finish;
    end
endmodule
