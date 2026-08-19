module m64k_register_file_tb;
    import m64k_arch_pkg::*;

    logic clk;
    logic rst_n;
    m64k_profile_t profile;
    logic [2:0] data_read_index_a;
    logic [2:0] data_read_index_b;
    logic [31:0] data_read_value_a;
    logic [31:0] data_read_value_b;
    logic [2:0] address_read_index_a;
    logic [2:0] address_read_index_b;
    logic [31:0] address_read_value_a;
    logic [31:0] address_read_value_b;
    logic boot_valid;
    logic [31:0] boot_ssp;
    logic [31:0] boot_pc;
    logic commit_valid;
    logic data_write_enable;
    logic [2:0] data_write_index;
    logic [31:0] data_write_value;
    logic data_write_enable_b;
    logic [2:0] data_write_index_b;
    logic [31:0] data_write_value_b;
    logic address_write_enable;
    logic [2:0] address_write_index;
    logic [31:0] address_write_value;
    logic address_write_enable_b;
    logic [2:0] address_write_index_b;
    logic [31:0] address_write_value_b;
    logic sr_write_enable;
    logic [15:0] sr_write_value;
    logic pc_write_enable;
    logic [31:0] pc_write_value;
    logic usp_write_enable;
    logic [31:0] usp_write_value;
    logic ssp_write_enable;
    logic [31:0] ssp_write_value;
    logic [15:0] sr;
    logic [31:0] pc;
    logic [31:0] usp;
    logic [31:0] ssp;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;

    m64k_register_file registers (.*);

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic commit_cycle;
        begin
            @(negedge clk);
            commit_valid = 1'b1;
            @(negedge clk);
            commit_valid = 1'b0;
            data_write_enable = 1'b0;
            data_write_enable_b = 1'b0;
            address_write_enable = 1'b0;
            address_write_enable_b = 1'b0;
            sr_write_enable = 1'b0;
            pc_write_enable = 1'b0;
            usp_write_enable = 1'b0;
            ssp_write_enable = 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        profile = M64K_PROFILE_M00;
        data_read_index_a = 0;
        data_read_index_b = 7;
        address_read_index_a = 0;
        address_read_index_b = 7;
        boot_valid = 0;
        boot_ssp = 0;
        boot_pc = 0;
        commit_valid = 0;
        data_write_enable = 0;
        data_write_index = 0;
        data_write_value = 0;
        data_write_enable_b = 0;
        data_write_index_b = 0;
        data_write_value_b = 0;
        address_write_enable = 0;
        address_write_index = 0;
        address_write_value = 0;
        address_write_enable_b = 0;
        address_write_index_b = 0;
        address_write_value_b = 0;
        sr_write_enable = 0;
        sr_write_value = 0;
        pc_write_enable = 0;
        pc_write_value = 0;
        usp_write_enable = 0;
        usp_write_value = 0;
        ssp_write_enable = 0;
        ssp_write_value = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        assert (sr == 16'h2700 && pc == 0 && ssp == 0);

        @(negedge clk);
        boot_ssp = 32'h0010_0000;
        boot_pc = 32'h0000_0100;
        boot_valid = 1'b1;
        @(negedge clk);
        boot_valid = 1'b0;
        assert (pc == 32'h100 && ssp == 32'h0010_0000);
        assert (address_read_value_b == 32'h0010_0000);

        data_write_enable = 1'b1;
        data_write_index = 3'd7;
        data_write_value = 32'hdead_beef;
        address_write_enable = 1'b1;
        address_write_index = 3'd0;
        address_write_value = 32'h1234_5678;
        pc_write_enable = 1'b1;
        pc_write_value = 32'h104;
        commit_cycle();
        assert (data_read_value_b == 32'hdead_beef);
        assert (address_read_value_a == 32'h1234_5678);
        assert (pc == 32'h104);

        // EXG requires two architectural writes in the same retirement.
        data_write_enable = 1'b1;
        data_write_index = 3'd1;
        data_write_value = 32'h1111_2222;
        data_write_enable_b = 1'b1;
        data_write_index_b = 3'd2;
        data_write_value_b = 32'h3333_4444;
        commit_cycle();
        data_read_index_a = 3'd1;
        data_read_index_b = 3'd2;
        #1;
        assert (data_read_value_a == 32'h1111_2222);
        assert (data_read_value_b == 32'h3333_4444);

        // Install user SP explicitly, then leave supervisor mode.
        usp_write_enable = 1'b1;
        usp_write_value = 32'h0000_8000;
        sr_write_enable = 1'b1;
        sr_write_value = 16'h0000;
        commit_cycle();
        assert (!sr[M64K_SR_S] && address_read_value_b == 32'h0000_8000);

        // Simultaneous A7 and SR writes update the pre-commit (user) bank.
        address_write_enable = 1'b1;
        address_write_index = 3'd7;
        address_write_value = 32'h0000_7ffc;
        sr_write_enable = 1'b1;
        sr_write_value = 16'h2000;
        commit_cycle();
        assert (sr[M64K_SR_S] && address_read_value_b == 32'h0010_0000);
        assert (usp == 32'h0000_7ffc);

        // M00 strips M20-only T0/M state while retaining defined T1/S/CCR.
        sr_write_enable = 1'b1;
        sr_write_value = 16'hffff;
        commit_cycle();
        assert (sr == M64K_SR_M00_DEFINED_MASK);
        assert (debug_data_registers[7*32 +: 32] == 32'hdead_beef);
        assert (debug_address_registers[7*32 +: 32] == ssp);

        $display("PASS: M64K banked M00 architectural register file");
        $finish;
    end
endmodule
