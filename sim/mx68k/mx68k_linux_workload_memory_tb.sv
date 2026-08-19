module mx68k_linux_workload_memory_tb;
    import mx68k_pkg::*;

    localparam logic [31:0] DUART_BASE = 32'h003f_c000;

    logic clk;
    logic rst_n;
    logic tx_valid;
    logic [7:0] tx_data;
    logic rx_valid;
    logic [7:0] rx_data;
    logic rx_ready;
    logic irq;
    logic [7:0] irq_vector;
    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));

    mx68k_linux_workload_memory #(
        .MEM_BYTES(4 * 1024 * 1024),
        .TIMER_CYCLES(8)
    ) dut (
        .clk,
        .rst_n,
        .m08_compat_enable(1'b1),
        .rx_valid,
        .rx_data,
        .rx_ready,
        .tx_valid,
        .tx_data,
        .irq,
        .irq_vector,
        .imem(imem_bus),
        .dmem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic transact(
        input mx_mem_command_t command,
        input logic [31:0] address,
        input logic [7:0] write_byte,
        output mx_mem_rsp_t response
    );
        mx_mem_req_t request;
        logic accepted;
        begin
            request = '0;
            request.command = command;
            request.size = MX_SIZE_BYTE;
            request.addr = address;
            request.txn_id = 4'ha;
            request.source = 4'h3;
            if (command inside {MX_MEM_WRITE, MX_MEM_ATOMIC}) begin
                request.wstrb[address[3:0]] = 1'b1;
                request.wdata[address[3:0]*8 +: 8] = write_byte;
            end
            if (command == MX_MEM_ATOMIC) begin
                request.atomic_op = MX_ATOMIC_OR;
                request.ordered = 1'b1;
                request.lock = 1'b1;
            end

            @(negedge clk);
            dmem_bus.req = request;
            dmem_bus.req_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                accepted = dmem_bus.req_ready;
            end
            @(negedge clk);
            dmem_bus.req_valid = 1'b0;
            while (!dmem_bus.rsp_valid)
                @(negedge clk);
            response = dmem_bus.rsp;
            dmem_bus.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            dmem_bus.rsp_ready = 1'b0;
        end
    endtask

    task automatic receive_byte(input logic [7:0] value);
        begin
            @(negedge clk);
            rx_data = value;
            rx_valid = 1'b1;
            while (!rx_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            rx_valid = 1'b0;
        end
    endtask

    mx_mem_rsp_t response;

    initial begin
        rst_n = 1'b0;
        imem_bus.req_valid = 1'b0;
        imem_bus.req = '0;
        imem_bus.rsp_ready = 1'b0;
        dmem_bus.req_valid = 1'b0;
        dmem_bus.req = '0;
        dmem_bus.rsp_ready = 1'b0;
        rx_valid = 1'b0;
        rx_data = '0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Main RAM implements the same pre-update-return atomic endpoint used
        // by the complete simulator. MMIO does not silently emulate atomics.
        transact(MX_MEM_WRITE, 32'h0000_0103, 8'h25, response);
        transact(MX_MEM_ATOMIC, 32'h0000_0103, 8'h80, response);
        assert (response.fault == MX_FAULT_NONE && response.atomic_success);
        assert (response.rdata[3*8 +: 8] == 8'h25);
        transact(MX_MEM_READ, 32'h0000_0103, 8'h00, response);
        assert (response.rdata[3*8 +: 8] == 8'ha5);
        transact(MX_MEM_ATOMIC, DUART_BASE + 32'h05, 8'h80, response);
        assert (response.fault == MX_FAULT_UNSUPPORTED);

        // IMR[3] enables the counter/timer interrupt; IVR supplies vector 65.
        transact(MX_MEM_WRITE, DUART_BASE + 32'h0b, 8'h08, response);
        transact(MX_MEM_WRITE, DUART_BASE + 32'h19, 8'h41, response);
        transact(MX_MEM_READ, DUART_BASE + 32'h1d, 8'h00, response);

        wait (irq);
        assert (irq_vector == 8'h41);

        // MC68681UM 4.3.15.5: ISR[3] reports C/T ready. Reading ISR does
        // not acknowledge it.
        transact(MX_MEM_READ, DUART_BASE + 32'h05, 8'h00, response);
        assert (response.rdata[5*8 +: 8] == 8'h08);
        assert (irq);

        // Reading the stop-counter command clears ISR[3]. In timer mode the
        // periodic source remains active and will assert again later.
        transact(MX_MEM_READ, DUART_BASE + 32'h1f, 8'h00, response);
        assert (!irq);

        // MC68681UM sections 4.3.7.4, 4.3.9.8 and 4.3.15.3:
        // enabling receiver B permits FIFO input, RxRDY appears in SRB[0]
        // and ISR[5], and reading RBB pops the character and clears RxRDY
        // when the FIFO becomes empty.
        transact(MX_MEM_WRITE, DUART_BASE + 32'h15, 8'h01, response);
        transact(MX_MEM_WRITE, DUART_BASE + 32'h0b, 8'h20, response);
        assert (rx_ready);
        // XR68C681 datasheet table 2: commands 8/A set the extended
        // receiver/transmitter BRG select bits. They do not alias the
        // standard commands 0/2 in the four-bit miscellaneous field.
        transact(MX_MEM_WRITE, DUART_BASE + 32'h15, 8'h80, response);
        transact(MX_MEM_WRITE, DUART_BASE + 32'h15, 8'ha0, response);
        assert (rx_ready);
        receive_byte(8'h61);
        assert (irq);
        transact(MX_MEM_READ, DUART_BASE + 32'h05, 8'h00, response);
        assert ((response.rdata[5*8 +: 8] & 8'h20) == 8'h20);
        transact(MX_MEM_READ, DUART_BASE + 32'h13, 8'h00, response);
        assert (response.rdata[3*8 +: 8] == 8'h05);
        transact(MX_MEM_READ, DUART_BASE + 32'h17, 8'h00, response);
        assert (response.rdata[7*8 +: 8] == 8'h61);
        assert (!irq);

        // MR1B[6] selects FFULL instead of RxRDY as the receive interrupt
        // source. The FIFO remains readable and RxRDY remains asserted after
        // one of three queued bytes is popped.
        transact(MX_MEM_WRITE, DUART_BASE + 32'h15, 8'h10, response);
        transact(MX_MEM_WRITE, DUART_BASE + 32'h11, 8'h40, response);
        receive_byte(8'h62);
        receive_byte(8'h63);
        assert (!irq);
        receive_byte(8'h64);
        assert (irq && !rx_ready);
        transact(MX_MEM_READ, DUART_BASE + 32'h13, 8'h00, response);
        assert (response.rdata[3*8 +: 8] == 8'h07);
        transact(MX_MEM_READ, DUART_BASE + 32'h17, 8'h00, response);
        assert (response.rdata[7*8 +: 8] == 8'h62);
        assert (!irq && rx_ready);

        // Reset Receiver disables B and empties/reinitializes its FIFO.
        transact(MX_MEM_WRITE, DUART_BASE + 32'h15, 8'h20, response);
        assert (!rx_ready);
        transact(MX_MEM_READ, DUART_BASE + 32'h13, 8'h00, response);
        assert (response.rdata[3*8 +: 8] == 8'h04);

        $display("PASS: workload RAM atomics and Mackerel-08 DUART contract");
        $finish;
    end
endmodule
