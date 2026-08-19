module mx68k_core_tst_matrix_tb;
    import mx68k_arch_pkg::*;
    import mx68k_m00_decode_table_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
    logic stopped;
    logic faulted;
    mx_exception_t terminal_exception;
    logic retire_valid;
    logic [31:0] retire_pc;
    logic [7:0] retire_instruction_id;
    logic [31:0] debug_pc;
    logic [15:0] debug_sr;
    logic [31:0] debug_usp;
    logic [31:0] debug_ssp;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    logic [7:0] baseline [0:31];

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    mx68k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n, .stopped, .faulted,
        .terminal_exception, .retire_valid, .retire_pc,
        .retire_instruction_id, .debug_pc, .debug_sr, .debug_usp,
        .debug_ssp, .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    mx68k_ram #(.MEM_BYTES(1024)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(.MEM_BYTES(1024)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic set_instruction_word(input integer address,
                                        input logic [15:0] value);
        instruction_ram.storage[address] = value[15:8];
        instruction_ram.storage[address + 1] = value[7:0];
    endtask

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        data_ram.storage[address] = value[31:24];
        data_ram.storage[address + 1] = value[23:16];
        data_ram.storage[address + 2] = value[15:8];
        data_ram.storage[address + 3] = value[7:0];
    endtask

    function automatic integer operand_step(input integer size_index,
                                             input integer register_index);
        if (size_index == 0)
            return (register_index == 7) ? 2 : 1;
        if (size_index == 1)
            return 2;
        return 4;
    endfunction

    task automatic run_tst_case(input integer size_index,
                                input integer ea_mode,
                                input integer ea_register);
        integer base_address;
        integer effective_address;
        integer expected_address;
        integer extension_count;
        integer stop_pc;
        integer case_cycles;
        logic [15:0] tst_opcode;
        logic [31:0] register_operand;
        begin
            base_address = 16'h0220;
            effective_address = base_address;
            expected_address = base_address;
            extension_count = 0;
            register_operand = (size_index == 0) ? 32'h1234_5680 :
                               (size_index == 1) ? 32'h1234_8000 :
                                                   32'h8000_0000;

            if (ea_mode == 3)
                expected_address = base_address +
                    operand_step(size_index, ea_register);
            else if (ea_mode == 4) begin
                effective_address = base_address -
                    operand_step(size_index, ea_register);
                expected_address = effective_address;
            end
            if ((ea_mode == 5) || (ea_mode == 6) ||
                ((ea_mode == 7) && (ea_register == 0)))
                extension_count = 1;
            else if ((ea_mode == 7) && (ea_register == 1))
                extension_count = 2;

            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);

            for (int byte_index = 0; byte_index < 32; byte_index++)
                data_ram.storage[16'h210 + byte_index] =
                    8'(8'h40 + byte_index);
            if (ea_mode != 0) begin
                if (size_index == 0)
                    data_ram.storage[effective_address] = 8'h80;
                else if (size_index == 1) begin
                    data_ram.storage[effective_address] = 8'h80;
                    data_ram.storage[effective_address + 1] = 8'h00;
                end else
                    set_data_long(effective_address, 32'h8000_0000);
            end
            for (int byte_index = 0; byte_index < 32; byte_index++)
                baseline[byte_index] =
                    data_ram.storage[16'h210 + byte_index];

            if (ea_mode == 0) begin
                set_instruction_word(16'h100,
                    16'(16'h203c | (ea_register << 9)));
                set_instruction_word(16'h102, register_operand[31:16]);
                set_instruction_word(16'h104, register_operand[15:0]);
            end else begin
                set_instruction_word(16'h100,
                    16'(16'h207c | (ea_register << 9)));
                set_instruction_word(16'h102, 16'h0000);
                set_instruction_word(16'h104, base_address[15:0]);
            end

            tst_opcode = 16'(16'h4a00 | (size_index << 6) |
                             (ea_mode << 3) | ea_register);
            set_instruction_word(16'h106, tst_opcode);
            if ((ea_mode == 5) || (ea_mode == 6))
                set_instruction_word(16'h108, 16'h0000);
            else if ((ea_mode == 7) && (ea_register == 0))
                set_instruction_word(16'h108, base_address[15:0]);
            else if ((ea_mode == 7) && (ea_register == 1)) begin
                set_instruction_word(16'h108, 16'h0000);
                set_instruction_word(16'h10a, base_address[15:0]);
            end
            stop_pc = 16'h108 + 2 * extension_count;
            set_instruction_word(stop_pc, 16'h4e72);
            set_instruction_word(stop_pc + 2, 16'h2700);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == 32'h0000_0106))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 300)
                    $fatal(1, "TST matrix case timed out: size=%0d ea=%0d/%0d",
                           size_index, ea_mode, ea_register);
            end

            assert (retire_instruction_id == MX_INSN_TST);
            assert (debug_sr == 16'h2708); // N=1; Z/V/C=0; X preserved
            if (ea_mode == 0)
                assert (debug_data_registers[ea_register*32 +: 32] ==
                        register_operand);
            else begin
                assert (debug_address_registers[ea_register*32 +: 32] ==
                        expected_address);
                for (int byte_index = 0; byte_index < 32; byte_index++)
                    assert (data_ram.storage[16'h210 + byte_index] ==
                            baseline[byte_index]);
            end

            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;

        // Exhaust all 150 legal M00 TST opcode words: three sizes times all
        // Dn, An-indirect, postincrement, predecrement, displacement, brief
        // indexed, absolute-word and absolute-long encodings.
        for (int size_index = 0; size_index < 3; size_index++) begin
            for (int register_index = 0; register_index < 8;
                 register_index++)
                run_tst_case(size_index, 0, register_index);
            for (int mode_index = 2; mode_index <= 6; mode_index++)
                for (int register_index = 0; register_index < 8;
                     register_index++)
                    run_tst_case(size_index, mode_index, register_index);
            run_tst_case(size_index, 7, 0);
            run_tst_case(size_index, 7, 1);
        end

        $display("PASS: all 150 legal M00 TST opcode words and EA side effects");
        $finish;
    end
endmodule
