// Legacy Mackerel-F: BOOT goes high after four reset-vector word reads.
module boot_signal(
    input RESET_n,
    input AS_n,
    output reg BOOT = 1'b0
);

localparam [2:0] BOOT_CYCLE_MAX = 3'd4;

reg [2:0] bus_cycles = 0;

always @(posedge AS_n or negedge RESET_n) begin
    if (!RESET_n) begin
        bus_cycles <= 3'd0;
        BOOT <= 1'b0;
    end else if (!BOOT) begin
        if (bus_cycles == BOOT_CYCLE_MAX - 1'b1)
            BOOT <= 1'b1;
        else
            bus_cycles <= bus_cycles + 1'b1;
    end
end

endmodule
