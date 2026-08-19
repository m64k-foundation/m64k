module mx68k_core_shift_tb;
    import mx68k_arch_pkg::*;
    import mx68k_shift_reference_pkg::*;

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

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    mx68k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n,
        .stopped, .faulted, .terminal_exception,
        .retire_valid, .retire_pc, .retire_instruction_id,
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp,
        .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    mx68k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(.MEM_BYTES(512)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer cycles;
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 5000)
                $fatal(1, "MX68K register shift test timed out");
        end
    end

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        begin
            data_ram.storage[address + 0] = value[31:24];
            data_ram.storage[address + 1] = value[23:16];
            data_ram.storage[address + 2] = value[15:8];
            data_ram.storage[address + 3] = value[7:0];
        end
    endtask

    task automatic set_word(input integer address,
                            input logic [15:0] value);
        begin
            instruction_ram.storage[address + 0] = value[15:8];
            instruction_ram.storage[address + 1] = value[7:0];
        end
    endtask

    task automatic wait_retire(input logic [31:0] expected_pc);
        begin
            while (!(retire_valid && (retire_pc == expected_pc)))
                @(negedge clk);
        end
    endtask

    task automatic run_opcode_case(
        input integer size_index,
        input integer direction_index,
        input integer count_source_index,
        input integer kind_index,
        input integer count_field,
        input integer destination_index
    );
        logic [31:0] operand_value;
        logic [31:0] count_register_value;
        logic [31:0] result_mask;
        logic [31:0] expected_register;
        logic [5:0] effective_count;
        logic [15:0] shift_opcode;
        logic [15:0] expected_sr;
        mx_alu_result_t expected_shift;
        integer next_pc;
        integer shift_pc;
        integer case_cycles;
        begin
            operand_value = 32'ha55a_81a5;
            count_register_value = 32'h0000_0041; // modulo-64 count one
            case (size_index)
                0: result_mask = 32'h0000_00ff;
                1: result_mask = 32'h0000_ffff;
                default: result_mask = 32'hffff_ffff;
            endcase

            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0200);
            set_data_long(4, 32'h0000_0100);
            set_word(16'h100,
                16'(16'h203c | (destination_index << 9)));
            set_word(16'h102, operand_value[31:16]);
            set_word(16'h104, operand_value[15:0]);
            next_pc = 16'h106;

            if ((count_source_index != 0) &&
                (count_field != destination_index)) begin
                set_word(next_pc,
                    16'(16'h203c | (count_field << 9)));
                set_word(next_pc + 2, count_register_value[31:16]);
                set_word(next_pc + 4, count_register_value[15:0]);
                next_pc = next_pc + 6;
                effective_count = count_register_value[5:0];
            end else if (count_source_index != 0) begin
                // Same-register alias: the operand is also the count source.
                effective_count = operand_value[5:0];
            end else begin
                effective_count = (count_field == 0) ? 6'd8 :
                                                      6'(count_field);
            end

            set_word(next_pc, 16'h44fc); // MOVE.W #$0010,CCR
            set_word(next_pc + 2, 16'h0010);
            shift_pc = next_pc + 4;
            shift_opcode = 16'(16'he000 | (count_field << 9) |
                               (direction_index << 8) |
                               (size_index << 6) |
                               (count_source_index << 5) |
                               (kind_index << 3) |
                               destination_index);
            set_word(shift_pc, shift_opcode);
            set_word(shift_pc + 2, 16'h4e72);
            set_word(shift_pc + 4, 16'h2700);

            expected_shift = reference_shift(
                operand_value, mx_operand_size_t'(size_index),
                effective_count, direction_index[0], kind_index[1:0], 1'b1);
            expected_register = (operand_value & ~result_mask) |
                                (expected_shift.result & result_mask);
            expected_sr = 16'h2700;
            expected_sr[MX_SR_X] = expected_shift.flags.x;
            expected_sr[MX_SR_N] = expected_shift.flags.n;
            expected_sr[MX_SR_Z] = expected_shift.flags.z;
            expected_sr[MX_SR_V] = expected_shift.flags.v;
            expected_sr[MX_SR_C] = expected_shift.flags.c;

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            case_cycles = 0;
            while (!(retire_valid && (retire_pc == shift_pc))) begin
                @(negedge clk);
                case_cycles = case_cycles + 1;
                if (case_cycles > 300)
                    $fatal(1,
                        "register shift timeout opcode=%04x", shift_opcode);
            end
            assert (debug_data_registers[destination_index*32 +: 32] ==
                    expected_register)
                else $fatal(1,
                    "register shift result opcode=%04x actual=%08x expected=%08x",
                    shift_opcode,
                    debug_data_registers[destination_index*32 +: 32],
                    expected_register);
            assert (debug_sr == expected_sr)
                else $fatal(1,
                    "register shift flags opcode=%04x actual=%04x expected=%04x",
                    shift_opcode, debug_sr, expected_sr);
            if ((count_source_index != 0) &&
                (count_field != destination_index))
                assert (debug_data_registers[count_field*32 +: 32] ==
                        count_register_value);
            wait (stopped || faulted);
            assert (stopped && !faulted && !terminal_exception.valid);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);
        set_data_long(0, 32'h0000_0200);
        set_data_long(4, 32'h0000_0100);

        // M68000PRM 4-20..4-23: ASL sets V if the sign changes at any
        // point and sends the last shifted bit to both C and X.
        set_word(16'h100, 16'h203c); // MOVE.L #$12345640,D0
        set_word(16'h102, 16'h1234);
        set_word(16'h104, 16'h5640);
        set_word(16'h106, 16'he300); // ASL.B #1,D0

        set_word(16'h108, 16'h103c); // MOVE.B #$81,D0
        set_word(16'h10a, 16'h0081);
        set_word(16'h10c, 16'he200); // ASR.B #1,D0

        // PRM 4-112..4-114: an immediate count field of zero encodes 8.
        set_word(16'h10e, 16'h303c); // MOVE.W #$0180,D0
        set_word(16'h110, 16'h0180);
        set_word(16'h112, 16'he148); // LSL.W #8,D0

        // A register count is modulo 64.  A resulting zero count clears C,
        // preserves X, and still derives N/Z from the unchanged operand.
        set_word(16'h114, 16'h203c); // MOVE.L #$80000001,D0
        set_word(16'h116, 16'h8000);
        set_word(16'h118, 16'h0001);
        set_word(16'h11a, 16'h7200); // MOVEQ #0,D1
        set_word(16'h11c, 16'h003c); // ORI #$10,CCR: X=1
        set_word(16'h11e, 16'h0010);
        set_word(16'h120, 16'he2a8); // LSR.L D1,D0 (count 0)

        // PRM 4-162..4-165: ROX with zero count copies X to C.
        set_word(16'h122, 16'h103c); // MOVE.B #1,D0
        set_word(16'h124, 16'h0001);
        set_word(16'h126, 16'he230); // ROXR.B D1,D0 (count 0)

        // PRM 4-159..4-162: RO without extend clears C for zero count and
        // never changes X.
        set_word(16'h128, 16'h7000); // MOVEQ #0,D0
        set_word(16'h12a, 16'he238); // ROR.B D1,D0 (count 0)

        // A register count of 65 is equivalent to one.  ROL preserves X.
        set_word(16'h12c, 16'h7000); // MOVEQ #0,D0
        set_word(16'h12e, 16'h103c); // MOVE.B #$81,D0
        set_word(16'h130, 16'h0081);
        set_word(16'h132, 16'h7241); // MOVEQ #65,D1
        set_word(16'h134, 16'he338); // ROL.B D1,D0

        // ROXL uses the old X as the incoming bit and publishes the outgoing
        // bit in both C and X.
        set_word(16'h136, 16'h023c); // ANDI #$ef,CCR: X=0
        set_word(16'h138, 16'h00ef);
        set_word(16'h13a, 16'h203c); // MOVE.L #$80000000,D0
        set_word(16'h13c, 16'h8000);
        set_word(16'h13e, 16'h0000);
        set_word(16'h140, 16'he390); // ROXL.L #1,D0

        set_word(16'h142, 16'h4e72); // STOP #$2700
        set_word(16'h144, 16'h2700);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        wait_retire(32'h0000_0106);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_5680);
        assert (debug_sr == 16'h270a); // N=1,V=1,C=X=0

        wait_retire(32'h0000_010c);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_56c0);
        assert (debug_sr == 16'h2719); // X=N=C=1,V=0

        wait_retire(32'h0000_0112);
        assert (debug_data_registers[0*32 +: 32] == 32'h1234_8000);
        assert (debug_sr == 16'h2719); // immediate zero field really shifted 8

        wait_retire(32'h0000_0120);
        assert (debug_data_registers[0*32 +: 32] == 32'h8000_0001);
        assert (debug_sr == 16'h2718); // X,N set; C clear

        wait_retire(32'h0000_0126);
        assert (debug_data_registers[0*32 +: 32] == 32'h8000_0001);
        assert (debug_sr == 16'h2711); // X copied to C

        wait_retire(32'h0000_012a);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_0000);
        assert (debug_sr == 16'h2714); // X,Z set; C clear

        wait_retire(32'h0000_0134);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_0003);
        assert (debug_sr == 16'h2711); // count 65 -> 1; X preserved

        wait_retire(32'h0000_0140);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_0000);
        assert (debug_sr == 16'h2715); // X=Z=C=1, V=N=0

        wait (stopped || faulted);
        assert (stopped && !faulted && !terminal_exception.valid);

        // Exhaust all 3072 legal register-shift opcode words through the
        // complete core path.  The independent iterative oracle above is
        // shared with the 49,152-vector standalone shifter regression.
        for (int size_index = 0; size_index < 3; size_index++)
            for (int direction_index = 0; direction_index < 2;
                 direction_index++)
                for (int count_source_index = 0; count_source_index < 2;
                     count_source_index++)
                    for (int kind_index = 0; kind_index < 4; kind_index++)
                        for (int count_field = 0; count_field < 8;
                             count_field++)
                            for (int destination_index = 0;
                                 destination_index < 8;
                                 destination_index++)
                                run_opcode_case(
                                    size_index, direction_index,
                                    count_source_index, kind_index,
                                    count_field, destination_index);

        $display("PASS: all 3072 M00 register shifts/rotates match the documented oracle");
        $finish;
    end
endmodule
