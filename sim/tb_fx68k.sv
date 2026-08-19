`timescale 1ns/1ps

module tb_fx68k;

    logic clk = 0;

    logic extReset = 1;
    logic pwrUp = 1;

    logic [1:0] clkDivisor = 0;

    wire enPhi1 = (clkDivisor == 2'b11);
    wire enPhi2 = (clkDivisor == 2'b01);

    wire eRWn;
    wire ASn;
    wire LDSn;
    wire UDSn;

    wire E;
    wire VMAn;

    wire FC0;
    wire FC1;
    wire FC2;

    wire BGn;
    wire oRESETn;
    wire oHALTEDn;

    wire [23:1] eab;
    wire [15:0] oEdb;

    logic [15:0] iEdb;

    logic DTACKn = 0;
    logic VPAn   = 1;
    logic BERRn  = 1;

    logic BRn    = 1;
    logic BGACKn = 1;

    logic IPL0n = 1;
    logic IPL1n = 1;
    logic IPL2n = 1;

    logic HALTn = 1;

    integer cycles = 0;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        clkDivisor <= clkDivisor + 1'b1;
        cycles <= cycles + 1;

        if (cycles == 8) begin
            extReset <= 0;
            pwrUp <= 0;
            $display("Reset liberado");
        end

        if (!ASn) begin
            $display(
                "BUS addr=%06x rw=%d uds=%d lds=%d data_in=%04x data_out=%04x",
                {eab, 1'b0},
                eRWn,
                UDSn,
                LDSn,
                iEdb,
                oEdb
            );
        end

        if (cycles > 5000) begin
            $display("Fim da simulacao");
            $finish;
        end
    end

    /*
     * Memória mínima.
     *
     * 000000: initial SSP = 00001000
     * 000004: initial PC  = 00000100
     *
     * 000100: NOP
     * 000102: BRA.S 000102
     */
    always_comb begin
        case ({eab, 1'b0})

            24'h000000: iEdb = 16'h0000;
            24'h000002: iEdb = 16'h1000;

            24'h000004: iEdb = 16'h0000;
            24'h000006: iEdb = 16'h0100;

            24'h000100: iEdb = 16'h4E71; // NOP
            24'h000102: iEdb = 16'h60FE; // BRA.S *

            default:    iEdb = 16'h4E71;

        endcase
    end

    fx68k cpu (
        .clk(clk),

        .HALTn(HALTn),

        .extReset(extReset),
        .pwrUp(pwrUp),

        .enPhi1(enPhi1),
        .enPhi2(enPhi2),

        .eRWn(eRWn),
        .ASn(ASn),
        .LDSn(LDSn),
        .UDSn(UDSn),

        .E(E),
        .VMAn(VMAn),

        .FC0(FC0),
        .FC1(FC1),
        .FC2(FC2),

        .BGn(BGn),

        .oRESETn(oRESETn),
        .oHALTEDn(oHALTEDn),

        .DTACKn(DTACKn),
        .VPAn(VPAn),
        .BERRn(BERRn),

        .BRn(BRn),
        .BGACKn(BGACKn),

        .IPL0n(IPL0n),
        .IPL1n(IPL1n),
        .IPL2n(IPL2n),

        .iEdb(iEdb),
        .oEdb(oEdb),

        .eab(eab)
    );

endmodule
