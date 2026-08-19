module m64k_boot_rom_tb;
    import m64k_pkg::*;

    localparam logic [31:0] ROM_BASE = 32'h0000_0000;

    logic clk;
    logic rst_n;
    integer cycles;
    m64k_mem_if imem(.clk(clk), .rst_n(rst_n));
    m64k_mem_if dmem(.clk(clk), .rst_n(rst_n));

    m64k_dual_port_ram #(
        .BASE_ADDR(ROM_BASE),
        .MEM_BYTES(32),
        .READ_ONLY(1'b1),
        .INIT_FILE("m64k_boot_rom.hex")
    ) rom (
        .clk, .rst_n, .imem, .dmem
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 200)
                $fatal(1, "M64K boot ROM test timed out");
        end
    end

    task automatic imem_transaction(
        input m64k_mem_req_t request,
        input int unsigned blocked_cycles,
        output m64k_mem_rsp_t response
    );
        m64k_mem_rsp_t held_response;
        begin
            @(negedge clk);
            imem.req = request;
            imem.req_valid = 1'b1;
            imem.rsp_ready = 1'b0;
            while (!imem.req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            imem.req_valid = 1'b0;
            while (!imem.rsp_valid)
                @(negedge clk);
            held_response = imem.rsp;
            repeat (blocked_cycles) begin
                @(posedge clk);
                assert (imem.rsp_valid && imem.rsp == held_response)
                    else $fatal(1, "instruction ROM response changed under backpressure");
            end
            response = imem.rsp;
            @(negedge clk);
            imem.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            imem.rsp_ready = 1'b0;
        end
    endtask

    task automatic dmem_transaction(
        input m64k_mem_req_t request,
        input int unsigned blocked_cycles,
        output m64k_mem_rsp_t response
    );
        m64k_mem_rsp_t held_response;
        begin
            @(negedge clk);
            dmem.req = request;
            dmem.req_valid = 1'b1;
            dmem.rsp_ready = 1'b0;
            while (!dmem.req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            dmem.req_valid = 1'b0;
            while (!dmem.rsp_valid)
                @(negedge clk);
            held_response = dmem.rsp;
            repeat (blocked_cycles) begin
                @(posedge clk);
                assert (dmem.rsp_valid && dmem.rsp == held_response)
                    else $fatal(1, "data ROM response changed under backpressure");
            end
            response = dmem.rsp;
            @(negedge clk);
            dmem.rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            dmem.rsp_ready = 1'b0;
        end
    endtask

    initial begin
        m64k_mem_req_t instruction_request;
        m64k_mem_req_t data_request;
        m64k_mem_rsp_t instruction_response;
        m64k_mem_rsp_t data_response;

        rst_n = 1'b0;
        cycles = 0;
        imem.req_valid = 1'b0;
        imem.req = '0;
        imem.rsp_ready = 1'b0;
        dmem.req_valid = 1'b0;
        dmem.req = '0;
        dmem.rsp_ready = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        instruction_request = '0;
        instruction_request.command = M64K_MEM_READ;
        instruction_request.size = M64K_SIZE_LINE;
        instruction_request.addr = ROM_BASE;
        instruction_request.txn_id = 4'h1;
        instruction_request.source = 4'h2;
        instruction_request.instruction = 1'b1;

        data_request = '0;
        data_request.command = M64K_MEM_READ;
        data_request.size = M64K_SIZE_LINE;
        data_request.addr = ROM_BASE + 32'h10;
        data_request.txn_id = 4'h3;
        data_request.source = 4'h4;

        fork
            imem_transaction(instruction_request, 3, instruction_response);
            dmem_transaction(data_request, 2, data_response);
        join

        assert (instruction_response.fault == M64K_FAULT_NONE);
        assert (!instruction_response.atomic_success);
        assert (instruction_response.txn_id == 4'h1 &&
                instruction_response.source == 4'h2);
        assert (instruction_response.rdata[31:0] == 32'h0020_0000);
        assert (instruction_response.rdata[63:32] == 32'h1000_0000);
        assert (instruction_response.rdata[95:64] == 32'hfe60_714e);
        assert (data_response.fault == M64K_FAULT_NONE);
        assert (data_response.txn_id == 4'h3 && data_response.source == 4'h4);
        assert (data_response.rdata[7:0] == 8'h10);
        assert (data_response.rdata[127:120] == 8'h1f);

        data_request = '0;
        data_request.command = M64K_MEM_WRITE;
        data_request.size = M64K_SIZE_BYTE;
        data_request.addr = ROM_BASE + 32'h0c;
        data_request.wstrb[12] = 1'b1;
        data_request.wdata[12*8 +: 8] = 8'hff;
        dmem_transaction(data_request, 0, data_response);
        assert (data_response.fault == M64K_FAULT_ACCESS);

        data_request.command = M64K_MEM_ATOMIC;
        data_request.atomic_op = M64K_ATOMIC_OR;
        dmem_transaction(data_request, 0, data_response);
        assert (data_response.fault == M64K_FAULT_ACCESS);
        assert (!data_response.atomic_success);

        data_request = '0;
        data_request.command = M64K_MEM_READ;
        data_request.size = M64K_SIZE_LINE;
        data_request.addr = ROM_BASE;
        dmem_transaction(data_request, 0, data_response);
        assert (data_response.rdata[12*8 +: 8] == 8'ha5);

        instruction_request.command = M64K_MEM_WRITE;
        imem_transaction(instruction_request, 0, instruction_response);
        assert (instruction_response.fault == M64K_FAULT_UNSUPPORTED);

        instruction_request.command = M64K_MEM_READ;
        instruction_request.addr = ROM_BASE + 32'h20;
        imem_transaction(instruction_request, 0, instruction_response);
        assert (instruction_response.fault == M64K_FAULT_ACCESS);

        $display("PASS: M64K boot ROM initialization, dual-port reads and read-only protection");
        $finish;
    end
endmodule
