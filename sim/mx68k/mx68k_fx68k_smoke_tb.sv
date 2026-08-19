module mx68k_fx68k_smoke_tb;
    import mx68k_pkg::*;

    logic clk;
    logic reset;
    logic phase;
    wire en_phi1 = phase;
    wire en_phi2 = !phase;

    wire cpu_rw_n;
    wire cpu_as_n;
    wire cpu_lds_n;
    wire cpu_uds_n;
    wire [23:1] cpu_addr;
    wire [15:0] cpu_data_out;
    wire [15:0] cpu_data_in;
    wire cpu_dtack_n;
    wire cpu_berr_n;
    wire fc0;
    wire fc1;
    wire fc2;

    mx68k_mem_if mem_bus(.clk(clk), .rst_n(!reset));

    fx68k cpu (
        .clk,
        .HALTn(1'b1),
        .extReset(reset),
        .pwrUp(reset),
        .enPhi1(en_phi1),
        .enPhi2(en_phi2),
        .eRWn(cpu_rw_n),
        .ASn(cpu_as_n),
        .LDSn(cpu_lds_n),
        .UDSn(cpu_uds_n),
        .E(),
        .VMAn(),
        .FC0(fc0),
        .FC1(fc1),
        .FC2(fc2),
        .BGn(),
        .oRESETn(),
        .oHALTEDn(),
        .DTACKn(cpu_dtack_n),
        .VPAn(1'b1),
        .BERRn(cpu_berr_n),
        .BRn(1'b1),
        .BGACKn(1'b1),
        .IPL0n(1'b1),
        .IPL1n(1'b1),
        .IPL2n(1'b1),
        .iEdb(cpu_data_in),
        .oEdb(cpu_data_out),
        .eab(cpu_addr)
    );

    fx68k_mem_bridge bridge (
        .clk,
        .rst_n(!reset),
        .cs_n(1'b0),
        .as_n(cpu_as_n),
        .rw_n(cpu_rw_n),
        .uds_n(cpu_uds_n),
        .lds_n(cpu_lds_n),
        .addr(cpu_addr),
        .data_out(cpu_data_out),
        .fc({fc2, fc1, fc0}),
        .data_in(cpu_data_in),
        .dtack_n(cpu_dtack_n),
        .berr_n(cpu_berr_n),
        .mem(mem_bus)
    );

    mx68k_ram #(
        .BASE_ADDR(32'h0000_0000),
        .MEM_BYTES(4096),
        .REQUEST_STALL_CYCLES(1)
    ) ram (
        .clk,
        .rst_n(!reset),
        .mem(mem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (reset)
            phase <= 1'b0;
        else
            phase <= !phase;
    end

    integer cycle_count;
    integer loop_fetches;

    always_ff @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
            loop_fetches <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (mem_bus.req_valid && mem_bus.req_ready &&
                mem_bus.req.command == MX_MEM_READ &&
                mem_bus.req.instruction &&
                mem_bus.req.addr == 32'h0000_0102) begin
                loop_fetches <= loop_fetches + 1;
                if (loop_fetches == 2) begin
                    $display("PASS: fx68k executed reset vectors, NOP and BRA through MX68K fabric");
                    $finish;
                end
            end

            if (cycle_count > 20000)
                $fatal(1, "fx68k did not reach the loop through MX68K fabric");
        end
    end

    initial begin
        reset = 1'b1;
        phase = 1'b0;
        cycle_count = 0;
        loop_fetches = 0;

        repeat (2) @(negedge clk);
        // Initial SSP = 0x00001000 and initial PC = 0x00000100.
        ram.storage[0] = 8'h00;
        ram.storage[1] = 8'h00;
        ram.storage[2] = 8'h10;
        ram.storage[3] = 8'h00;
        ram.storage[4] = 8'h00;
        ram.storage[5] = 8'h00;
        ram.storage[6] = 8'h01;
        ram.storage[7] = 8'h00;

        // NOP; BRA.S *
        ram.storage[16'h0100] = 8'h4e;
        ram.storage[16'h0101] = 8'h71;
        ram.storage[16'h0102] = 8'h60;
        ram.storage[16'h0103] = 8'hfe;

        repeat (8) @(negedge clk);
        reset = 1'b0;
    end
endmodule
