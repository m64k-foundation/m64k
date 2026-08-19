module mx68k_high_model_irq_tb;
    import mx68k_pkg::*;

    logic clk;
    logic rst_n;
    logic rx_valid;
    logic [7:0] rx_data;
    logic rx_ready;
    logic tx_valid;
    logic [7:0] tx_data;
    logic uart_irq;
    logic timer_irq;
    logic [31:0] timer_time_scale;
    mx68k_mem_if mem_bus(.clk(clk), .rst_n(rst_n));

    mx68k_mackerel_f_high_model #(
        .CLOCK_HZ(1000)
    ) model (
        .clk, .rst_n, .timer_time_scale,
        .rx_valid, .rx_data, .rx_ready,
        .tx_valid, .tx_data,
        .uart_irq, .timer_irq,
        .mem(mem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic transact(
        input mx_mem_req_t request_value,
        output mx_mem_rsp_t response_value
    );
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
            while (!mem_bus.rsp_valid)
                @(negedge clk);
            response_value = mem_bus.rsp;
            mem_bus.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            mem_bus.rsp_ready = 1'b0;
        end
    endtask

    task automatic write_byte(
        input logic [31:0] address,
        input logic [7:0] value
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
            request_value.txn_id = 4'h3;
            request_value.source = 4'h7;
            transact(request_value, response_value);
            assert (response_value.fault == MX_FAULT_NONE);
        end
    endtask

    task automatic read_line(
        input logic [31:0] address,
        output mx_mem_rsp_t response_value
    );
        mx_mem_req_t request_value;
        begin
            request_value = '0;
            request_value.command = MX_MEM_READ;
            request_value.size = MX_SIZE_LINE;
            request_value.addr = address;
            request_value.txn_id = 4'h4;
            request_value.source = 4'h7;
            transact(request_value, response_value);
            assert (response_value.fault == MX_FAULT_NONE);
        end
    endtask

    mx_mem_rsp_t response_value;
    initial begin
        rst_n = 1'b0;
        timer_time_scale = 32'd1;
        rx_valid = 1'b0;
        rx_data = '0;
        mem_bus.req_valid = 1'b0;
        mem_bus.req = '0;
        mem_bus.rsp_ready = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        assert (!uart_irq && !timer_irq && rx_ready);

        // RX data alone does not interrupt until IER.RDA is enabled.
        rx_data = 8'h41;
        rx_valid = 1'b1;
        @(negedge clk);
        rx_valid = 1'b0;
        assert (!uart_irq && !rx_ready);
        write_byte(32'h00ff_f902, 8'h01);
        assert (uart_irq);
        read_line(32'h00ff_f900, response_value);
        assert (response_value.rdata[7:0] == 8'h41);
        @(negedge clk);
        assert (!uart_irq && rx_ready);

        // OpenCores 16550 THRE is a one-shot pending source: enabling IER[1]
        // while empty raises it, an identifying IIR read clears it, and a
        // completed THR write rearms it because this model transmits at once.
        write_byte(32'h00ff_f902, 8'h02);
        assert (uart_irq);
        read_line(32'h00ff_f904, response_value);
        assert (response_value.rdata[4*8 +: 8] == 8'hc2);
        @(negedge clk);
        assert (!uart_irq);
        write_byte(32'h00ff_f900, 8'h5a);
        repeat (2) @(negedge clk);
        assert (uart_irq);
        read_line(32'h00ff_f904, response_value);
        assert (response_value.rdata[4*8 +: 8] == 8'hc2);
        @(negedge clk);
        assert (!uart_irq);
        write_byte(32'h00ff_f902, 8'h00);

        // 100 Hz at a 1 kHz model clock raises a level IRQ after ten clocks.
        write_byte(32'h00ff_fa00, 8'h31);
        while (!timer_irq)
            @(negedge clk);
        read_line(32'h00ff_fa00, response_value);
        assert (response_value.rdata[2*8] == 1'b1);
        write_byte(32'h00ff_fa02, 8'h00);
        assert (!timer_irq);
        write_byte(32'h00ff_fa00, 8'h00);
        repeat (12) @(negedge clk);
        assert (!timer_irq);

        // Both physical tiny-SPI slots expose the documented idle/ready
        // status.  Linux registers both controllers during platform probe.
        read_line(32'h00ff_fb08, response_value);
        assert (response_value.rdata[8*8 +: 8] == 8'h03);
        read_line(32'h00ff_fc08, response_value);
        assert (response_value.rdata[8*8 +: 8] == 8'h03);

        $display("PASS: Mackerel high-window UART/timer/SPI contract");
        $finish;
    end
endmodule
