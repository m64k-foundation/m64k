module mx68k_register_file (
    input logic clk,
    input logic rst_n,
    input mx68k_arch_pkg::mx_profile_t profile,

    input logic [2:0] data_read_index_a,
    input logic [2:0] data_read_index_b,
    output logic [31:0] data_read_value_a,
    output logic [31:0] data_read_value_b,
    input logic [2:0] address_read_index_a,
    input logic [2:0] address_read_index_b,
    output logic [31:0] address_read_value_a,
    output logic [31:0] address_read_value_b,

    input logic boot_valid,
    input logic [31:0] boot_ssp,
    input logic [31:0] boot_pc,

    input logic commit_valid,
    input logic data_write_enable,
    input logic [2:0] data_write_index,
    input logic [31:0] data_write_value,
    input logic data_write_enable_b,
    input logic [2:0] data_write_index_b,
    input logic [31:0] data_write_value_b,
    input logic address_write_enable,
    input logic [2:0] address_write_index,
    input logic [31:0] address_write_value,
    input logic address_write_enable_b,
    input logic [2:0] address_write_index_b,
    input logic [31:0] address_write_value_b,
    input logic sr_write_enable,
    input logic [15:0] sr_write_value,
    input logic pc_write_enable,
    input logic [31:0] pc_write_value,

    input logic usp_write_enable,
    input logic [31:0] usp_write_value,
    input logic ssp_write_enable,
    input logic [31:0] ssp_write_value,

    output logic [15:0] sr,
    output logic [31:0] pc,
    output logic [31:0] usp,
    output logic [31:0] ssp,
    output logic [8*32-1:0] debug_data_registers,
    output logic [8*32-1:0] debug_address_registers
);
    import mx68k_arch_pkg::*;

    logic [31:0] data_registers_q [0:7];
    logic [31:0] address_registers_q [0:6];
    logic [31:0] usp_q;
    logic [31:0] ssp_q;
    logic [15:0] sr_q;
    logic [31:0] pc_q;

    function automatic logic [31:0] read_address_register(
        input logic [2:0] index
    );
        if (index == 3'd7)
            return sr_q[MX_SR_S] ? ssp_q : usp_q;
        return address_registers_q[index];
    endfunction

    always_comb begin
        data_read_value_a = data_registers_q[data_read_index_a];
        data_read_value_b = data_registers_q[data_read_index_b];
        address_read_value_a = read_address_register(address_read_index_a);
        address_read_value_b = read_address_register(address_read_index_b);
        sr = sr_q;
        pc = pc_q;
        usp = usp_q;
        ssp = ssp_q;

        debug_data_registers = '0;
        debug_address_registers = '0;
        for (int unsigned index = 0; index < 8; index = index + 1) begin
            debug_data_registers[index*32 +: 32] = data_registers_q[index];
            debug_address_registers[index*32 +: 32] =
                (index == 7) ? read_address_register(3'd7) :
                               address_registers_q[index];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int unsigned index = 0; index < 8; index = index + 1)
                data_registers_q[index] <= '0;
            for (int unsigned index = 0; index < 7; index = index + 1)
                address_registers_q[index] <= '0;
            usp_q <= '0;
            ssp_q <= '0;
            sr_q <= 16'h2700;
            pc_q <= '0;
        end else begin
            if (boot_valid) begin
                ssp_q <= boot_ssp;
                pc_q <= boot_pc;
                sr_q <= mx_sr_sanitize(16'h2700, profile);
            end

            if (commit_valid) begin
                if (data_write_enable)
                    data_registers_q[data_write_index] <= data_write_value;
                if (data_write_enable_b)
                    data_registers_q[data_write_index_b] <= data_write_value_b;
                if (address_write_enable) begin
                    // An A7 write belongs to the mode visible before this
                    // commit. Explicit USP/SSP ports are used by exception
                    // entry when the target bank differs from current SR.S.
                    if (address_write_index == 3'd7) begin
                        if (sr_q[MX_SR_S])
                            ssp_q <= address_write_value;
                        else
                            usp_q <= address_write_value;
                    end else begin
                        address_registers_q[address_write_index] <=
                            address_write_value;
                    end
                end
                if (address_write_enable_b) begin
                    if (address_write_index_b == 3'd7) begin
                        if (sr_q[MX_SR_S])
                            ssp_q <= address_write_value_b;
                        else
                            usp_q <= address_write_value_b;
                    end else begin
                        address_registers_q[address_write_index_b] <=
                            address_write_value_b;
                    end
                end
                if (usp_write_enable)
                    usp_q <= usp_write_value;
                if (ssp_write_enable)
                    ssp_q <= ssp_write_value;
                if (sr_write_enable)
                    sr_q <= mx_sr_sanitize(sr_write_value, profile);
                if (pc_write_enable)
                    pc_q <= pc_write_value;
            end
        end
    end
endmodule
