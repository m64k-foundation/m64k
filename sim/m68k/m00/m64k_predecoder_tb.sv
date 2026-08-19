module m64k_predecoder_tb;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;
    import m64k_ea_pkg::*;
    import m64k_uop_pkg::*;
    import m64k_m00_decode_table_pkg::*;

    localparam int unsigned WINDOW_WORDS = 8;
    localparam int unsigned COUNT_WIDTH = $clog2(WINDOW_WORDS + 1);

    m64k_profile_t profile;
    logic window_valid;
    logic [31:0] window_pc;
    logic [COUNT_WIDTH-1:0] window_count;
    logic [WINDOW_WORDS*16-1:0] window_words;
    logic [WINDOW_WORDS*4-1:0] window_faults;
    logic decode_valid;
    logic decode_need_more;
    logic [COUNT_WIDTH-1:0] decode_words;
    m64k_uop_t decode_uop;
    m64k_exception_t decode_exception;
    logic [15:0] test_opcode;
    integer sr_ea_mode;
    integer sr_ea_register;
    integer sr_extension_words;
    integer sr_expected_words;
    logic sr_legal;

    m64k_predecoder #(.WINDOW_WORDS(WINDOW_WORDS)) decoder (.*);

    task automatic set_window(
        input m64k_profile_t new_profile,
        input logic [31:0] pc,
        input logic [COUNT_WIDTH-1:0] count,
        input logic [15:0] word_0,
        input logic [15:0] word_1,
        input logic [15:0] word_2
    );
        begin
            profile = new_profile;
            window_valid = 1'b1;
            window_pc = pc;
            window_count = count;
            window_words = '0;
            window_faults = '0;
            window_words[15:0] = word_0;
            window_words[31:16] = word_1;
            window_words[47:32] = word_2;
            #1;
        end
    endtask

    initial begin
        profile = M64K_PROFILE_M00;
        window_valid = 1'b0;
        window_pc = '0;
        window_count = '0;
        window_words = '0;
        window_faults = '0;
        #1;
        assert (!decode_valid && !decode_need_more);

        set_window(M64K_PROFILE_M00, 32'h100, COUNT_WIDTH'(1),
                   16'h4e71, 16'd0, 16'd0);
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_NOP);
        assert (decode_uop.instruction_id == M64K_INSN_NOP);
        assert (decode_uop.sequential_pc == 32'h102);

        set_window(M64K_PROFILE_M00, 32'h180, COUNT_WIDTH'(1),
                   16'h76a5, 16'd0, 16'd0);
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE);
        assert (decode_uop.instruction_id == M64K_INSN_MOVEQ);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.index == 3);
        assert (decode_uop.immediate == 32'hffff_ffa5);
        assert (decode_uop.flags_write == (M64K_FLAG_N | M64K_FLAG_Z |
                                           M64K_FLAG_V | M64K_FLAG_C));

        set_window(M64K_PROFILE_M00, 32'h190, COUNT_WIDTH'(1),
                   16'h4e63, 16'd0, 16'd0); // MOVE A3,USP
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_MOVE_USP);
        assert (decode_uop.opcode == M64K_UOP_MOVE);
        assert (decode_uop.size == M64K_OP_LONG && decode_uop.privileged);
        assert (decode_uop.source_a.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.source_a.index == 3);
        assert (decode_uop.destination.kind == M64K_OPERAND_USP);
        assert (decode_uop.flags_write == 0);

        set_window(M64K_PROFILE_M00, 32'h192, COUNT_WIDTH'(1),
                   16'h4e6f, 16'd0, 16'd0); // MOVE USP,A7
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_MOVE_USP);
        assert (decode_uop.source_a.kind == M64K_OPERAND_USP);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.index == 7);
        assert (decode_uop.flags_write == 0);

        set_window(M64K_PROFILE_M00, 32'h1a0, COUNT_WIDTH'(3),
                   16'h13fc, 16'h004f, 16'hffff);
        assert (!decode_valid && decode_need_more);
        window_count = COUNT_WIDTH'(4);
        window_words[63:48] = 16'hf800;
        #1;
        assert (decode_valid && decode_words == 4 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE);
        assert (decode_uop.size == M64K_OP_BYTE && decode_uop.memory_write);
        assert (decode_uop.immediate == 32'h4f);
        assert (decode_uop.memory_address == 32'hffff_f800);
        assert (decode_uop.source_ea.kind == M64K_EA_IMMEDIATE);
        assert (decode_uop.destination_ea.kind == M64K_EA_ABSOLUTE_LONG);
        assert (decode_uop.sequential_pc == 32'h1a8);
        window_faults[15:12] = M64K_FAULT_BUS;
        #1;
        assert (!decode_uop.valid && decode_exception.valid);
        assert (decode_words == 4 && decode_exception.next_pc == 32'h1a6);

        // Representative reset/startup sequence emitted by the M68K GCC port.
        set_window(M64K_PROFILE_M00, 32'hff00f0, COUNT_WIDTH'(1),
                   16'h2f0a, 16'd0, 16'd0); // MOVE.L A2,-(SP)
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE && decode_uop.memory_write);
        assert (decode_uop.source_ea.kind == M64K_EA_ADDRESS_REGISTER);
        assert (decode_uop.source_ea.register_index == 2);
        assert (decode_uop.destination_ea.kind == M64K_EA_PREDECREMENT);
        assert (decode_uop.destination_ea.register_index == 7);

        set_window(M64K_PROFILE_M00, 32'hff00f4, COUNT_WIDTH'(3),
                   16'h4eb9, 16'h00ff, 16'h03ac); // JSR abs.l
        assert (decode_valid && decode_words == 3 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_JUMP_SUBROUTINE);
        assert (decode_uop.destination_ea.kind == M64K_EA_ABSOLUTE_LONG);

        set_window(M64K_PROFILE_M00, 32'hff20d4, COUNT_WIDTH'(2),
                   16'h802a, 16'h000c, 16'd0); // OR.B 12(A2),D0
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_OR);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.source_ea.kind == M64K_EA_DISPLACEMENT);

        set_window(M64K_PROFILE_M00, 32'hff0b06, COUNT_WIDTH'(1),
                   16'hd1c0, 16'd0, 16'd0); // ADDA.L D0,A0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ADD);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd0);

        set_window(M64K_PROFILE_M00, 32'hff61c4, COUNT_WIDTH'(2),
                   16'hc0ef, 16'h000a, 16'd0); // MULU.W 10(SP),D0
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MULTIPLY);
        assert (!decode_uop.condition[0]);
        assert (decode_uop.source_ea.kind == M64K_EA_DISPLACEMENT);

        set_window(M64K_PROFILE_M00, 32'hff61c8, COUNT_WIDTH'(1),
                   16'h85c1, 16'd0, 16'd0); // DIVS.W D1,D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_DIVIDE);
        assert (decode_uop.condition[0]);
        assert (decode_uop.source_ea.kind == M64K_EA_DATA_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd2);

        set_window(M64K_PROFILE_M00, 32'hff61ca, COUNT_WIDTH'(1),
                   16'h43bc, 16'd0, 16'd0); // CHK.W #10,D1
        assert (!decode_valid && decode_need_more);
        set_window(M64K_PROFILE_M00, 32'hff61ca, COUNT_WIDTH'(2),
                   16'h43bc, 16'h000a, 16'd0);
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_CHK_W);
        assert (decode_uop.opcode == M64K_UOP_CHECK_BOUNDS);
        assert (decode_uop.size == M64K_OP_WORD);
        assert (decode_uop.source_ea.kind == M64K_EA_IMMEDIATE);
        assert (decode_uop.destination.index[2:0] == 3'd1);
        assert (decode_uop.exception_vector == M64K_VECTOR_CHK);

        set_window(M64K_PROFILE_M00, 32'hff61ce, COUNT_WIDTH'(1),
                   16'h4188, 16'd0, 16'd0); // CHK.W A0,D0 is illegal
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff4b06, COUNT_WIDTH'(2),
                   16'hd5ae, 16'hff94, 16'd0); // ADD.L D2,-108(A6)
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ADD);
        assert (decode_uop.size == M64K_OP_LONG && decode_uop.memory_write);
        assert (decode_uop.source_a.index[2:0] == 3'd2);
        assert (decode_uop.destination_ea.kind == M64K_EA_DISPLACEMENT);

        set_window(M64K_PROFILE_M00, 32'h00019798, COUNT_WIDTH'(1),
                   16'h9986, 16'd0, 16'd0); // SUBX.L D6,D4
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT_EXTEND);
        assert (decode_uop.size == M64K_OP_LONG && decode_uop.condition[0]);
        assert (decode_uop.source_a.index[2:0] == 3'd6);
        assert (decode_uop.destination.index[2:0] == 3'd4);
        assert (decode_uop.flags_read == (M64K_FLAG_X | M64K_FLAG_Z));
        assert (decode_uop.flags_write == M64K_FLAG_ALL);

        set_window(M64K_PROFILE_M00, 32'h0001979a, COUNT_WIDTH'(1),
                   16'hd108, 16'd0, 16'd0); // ADDX.B -(A0),-(A0)
        assert (decode_valid && decode_uop.valid &&
                !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_ADDX_MEM_B);
        assert (decode_uop.opcode == M64K_UOP_ADD_EXTEND);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.source_ea.kind == M64K_EA_PREDECREMENT &&
                decode_uop.source_ea.register_index == 3'd0);
        assert (decode_uop.destination_ea.kind == M64K_EA_PREDECREMENT &&
                decode_uop.destination_ea.register_index == 3'd0);
        assert (decode_uop.may_fault && decode_uop.memory_write);
        assert (decode_uop.flags_read == (M64K_FLAG_X | M64K_FLAG_Z));
        assert (decode_uop.flags_write == M64K_FLAG_ALL);

        set_window(M64K_PROFILE_M00, 32'h0001979c, COUNT_WIDTH'(1),
                   16'h974a, 16'd0, 16'd0); // SUBX.W -(A2),-(A3)
        assert (decode_valid && decode_uop.valid &&
                !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_SUBX_MEM_W);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT_EXTEND &&
                decode_uop.condition[0]);
        assert (decode_uop.size == M64K_OP_WORD);
        assert (decode_uop.source_ea.register_index == 3'd2);
        assert (decode_uop.destination_ea.register_index == 3'd3);

        set_window(M64K_PROFILE_M00, 32'h0001979e, COUNT_WIDTH'(1),
                   16'hc501, 16'd0, 16'd0); // ABCD D1,D2
        assert (decode_valid && decode_uop.valid &&
                !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_ABCD);
        assert (decode_uop.opcode == M64K_UOP_ADD_EXTEND);
        assert (decode_uop.size == M64K_OP_BYTE && decode_uop.condition[1]);
        assert (!decode_uop.condition[0] && !decode_uop.memory_write);
        assert (decode_uop.source_a.index[2:0] == 3'd1);
        assert (decode_uop.destination.index[2:0] == 3'd2);
        assert (decode_uop.flags_write ==
                (M64K_FLAG_X | M64K_FLAG_Z | M64K_FLAG_C));

        set_window(M64K_PROFILE_M00, 32'h000197a0, COUNT_WIDTH'(1),
                   16'h870a, 16'd0, 16'd0); // SBCD -(A2),-(A3)
        assert (decode_valid && decode_uop.valid &&
                !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_SBCD);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT_EXTEND);
        assert (decode_uop.condition[1] && decode_uop.condition[0]);
        assert (decode_uop.source_ea.kind == M64K_EA_PREDECREMENT &&
                decode_uop.source_ea.register_index == 3'd2);
        assert (decode_uop.destination_ea.kind == M64K_EA_PREDECREMENT &&
                decode_uop.destination_ea.register_index == 3'd3);
        assert (decode_uop.may_fault && decode_uop.memory_write);

        set_window(M64K_PROFILE_M00, 32'h000197a2, COUNT_WIDTH'(1),
                   16'h4823, 16'd0, 16'd0); // NBCD -(A3)
        assert (decode_valid && decode_uop.valid &&
                !decode_exception.valid);
        assert (decode_uop.instruction_id == M64K_INSN_NBCD);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT_EXTEND);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (!decode_uop.condition[0] && decode_uop.condition[1]);
        assert (decode_uop.destination_ea.kind == M64K_EA_PREDECREMENT &&
                decode_uop.destination_ea.register_index == 3'd3);
        assert (decode_uop.flags_read == (M64K_FLAG_X | M64K_FLAG_Z));
        assert (decode_uop.flags_write ==
                (M64K_FLAG_X | M64K_FLAG_Z | M64K_FLAG_C));

        set_window(M64K_PROFILE_M00, 32'h000197a4, COUNT_WIDTH'(1),
                   16'h4808, 16'd0, 16'd0); // NBCD A0 is illegal
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'h0008dda6, COUNT_WIDTH'(1),
                   16'h904c, 16'd0, 16'd0); // SUB.W A4,D0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT);
        assert (decode_uop.size == M64K_OP_WORD);
        assert (decode_uop.source_a.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.source_a.index[2:0] == 3'd4);
        assert (decode_uop.destination.index[2:0] == 3'd0);

        set_window(M64K_PROFILE_M00, 32'h0001979a, COUNT_WIDTH'(1),
                   16'hd541, 16'd0, 16'd0); // ADDX.W D1,D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ADD_EXTEND);
        assert (decode_uop.size == M64K_OP_WORD && !decode_uop.condition[0]);
        assert (decode_uop.source_a.index[2:0] == 3'd1);
        assert (decode_uop.destination.index[2:0] == 3'd2);

        set_window(M64K_PROFILE_M00, 32'hff3d1e, COUNT_WIDTH'(1),
                   16'hb400, 16'd0, 16'd0); // CMP.B D0,D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_COMPARE);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.source_a.index[2:0] == 3'd0);
        assert (decode_uop.destination.index[2:0] == 3'd2);

        set_window(M64K_PROFILE_M00, 32'hff3fe8, COUNT_WIDTH'(3),
                   16'h0280, 16'h0000, 16'h0003); // ANDI.L #3,D0
        assert (decode_valid && decode_words == 3 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_AND);
        assert (decode_uop.immediate == 3);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.sequential_pc == 32'hff3fee);

        set_window(M64K_PROFILE_M00, 32'hff4034, COUNT_WIDTH'(2),
                   16'h51c9, 16'hfffc, 16'd0); // DBF D1,$ff4032
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_DBCC);
        assert (decode_uop.condition == 4'h1);
        assert (decode_uop.destination.index[2:0] == 3'd1);
        assert (decode_uop.immediate == 32'hff4032);
        assert (decode_uop.sequential_pc == 32'hff4038);

        set_window(M64K_PROFILE_M00, 32'hff023c, COUNT_WIDTH'(3),
                   16'h0481, 16'h00ff, 16'hc540); // SUBI.L #$ffc540,D1
        assert (decode_valid && decode_words == 3 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.immediate == 32'h00ffc540);
        assert (decode_uop.destination.index[2:0] == 3'd1);
        assert (decode_uop.flags_write == M64K_FLAG_ALL);

        set_window(M64K_PROFILE_M00, 32'hff3f68, COUNT_WIDTH'(2),
                   16'h48e7, 16'h3020, 16'd0); // MOVEM.L D2-D3/A2,-(SP)
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE_MULTIPLE);
        assert (!decode_uop.condition[0] && decode_uop.memory_write);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.immediate[15:0] == 16'h3020);
        assert (decode_uop.source_ea.kind == M64K_EA_PREDECREMENT);

        set_window(M64K_PROFILE_M00, 32'hff3fa6, COUNT_WIDTH'(2),
                   16'h4cdf, 16'h040c, 16'd0); // MOVEM.L (SP)+,D2-D3/A2
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE_MULTIPLE);
        assert (decode_uop.condition[0] && !decode_uop.memory_write);
        assert (decode_uop.source_ea.kind == M64K_EA_POSTINCREMENT);

        set_window(M64K_PROFILE_M00, 32'hff3a14, COUNT_WIDTH'(2),
                   16'h4e56, 16'hfff8, 16'd0); // LINK A6,#-8
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_LINK);
        assert (decode_uop.source_ea.register_index == 3'd6);
        assert (decode_uop.immediate == 32'hfffffff8);

        set_window(M64K_PROFILE_M00, 32'hff3a62, COUNT_WIDTH'(2),
                   16'hb4fc, 16'h0000, 16'd0); // CMPA.W #0,A2
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_COMPARE);
        assert (decode_uop.size == M64K_OP_WORD);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd2);

        set_window(M64K_PROFILE_M00, 32'hff06fe, COUNT_WIDTH'(4),
                   16'h0839, 16'h0005, 16'h00ff); // BTST #5,$00fff90a
        window_words[63:48] = 16'hf90a;
        #1;
        assert (decode_valid && decode_words == 4 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_BIT_TEST);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.immediate == 5);
        assert (decode_uop.destination_ea.kind == M64K_EA_ABSOLUTE_LONG);
        assert (decode_uop.condition[1:0] == 2'b00 &&
                !decode_uop.condition[2]);

        set_window(M64K_PROFILE_M00, 32'h00003dde, COUNT_WIDTH'(1),
                   16'h03d0, 16'd0, 16'd0); // BSET D1,(A0)
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_BIT_TEST);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.source_a.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.source_a.index[2:0] == 3'd1);
        assert (decode_uop.destination_ea.kind == M64K_EA_INDIRECT);
        assert (decode_uop.condition[2:0] == 3'b111);

        set_window(M64K_PROFILE_M00, 32'hff5524, COUNT_WIDTH'(1),
                   16'h44c1, 16'd0, 16'd0); // MOVE.W D1,CCR
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE);
        assert (decode_uop.source_ea.kind == M64K_EA_DATA_REGISTER);
        assert (decode_uop.destination.kind == M64K_OPERAND_SR);
        assert (decode_uop.condition[0]);

        set_window(M64K_PROFILE_M00, 32'h00000400, COUNT_WIDTH'(2),
                   16'h46fc, 16'h2700, 16'd0); // MOVE.W #$2700,SR
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE);
        assert (decode_uop.source_ea.kind == M64K_EA_IMMEDIATE);
        assert (decode_uop.destination.kind == M64K_OPERAND_SR);
        assert (!decode_uop.condition[0] && decode_uop.privileged);
        assert (decode_uop.immediate == 32'h0000_2700);

        set_window(M64K_PROFILE_M00, 32'h0001a6ba, COUNT_WIDTH'(1),
                   16'h40c7, 16'd0, 16'd0); // MOVE.W SR,D7
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_MOVE && !decode_uop.privileged);
        assert (decode_uop.source_a.kind == M64K_OPERAND_SR);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd7);

        set_window(M64K_PROFILE_M00, 32'h0008d1a4, COUNT_WIDTH'(2),
                   16'h50ea, 16'h0004, 16'd0); // ST 4(A2)
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SET_CONDITION);
        assert (decode_uop.condition == 4'h0);
        assert (decode_uop.size == M64K_OP_BYTE && decode_uop.memory_write);
        assert (decode_uop.destination_ea.kind == M64K_EA_DISPLACEMENT);

        set_window(M64K_PROFILE_M00, 32'h00000400, COUNT_WIDTH'(1),
                   16'h46c8, 16'd0, 16'd0); // reserved MOVE.W A0,SR
        assert (decode_valid && decode_words == 1 && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        // Motorola M68000 Family Programmer's Reference Manual (1992),
        // MOVE to CCR pp. 4-123--4-124 and MOVE to SR pp. 6-19--6-20:
        // both accept exactly the M00 word data-source table (53 words).
        // MOVE from SR p. 4-125 accepts the 50 word data-alterable EAs.
        for (int sr_family = 0; sr_family < 3; sr_family++) begin
            for (int sr_ea = 0; sr_ea < 64; sr_ea++) begin
                sr_ea_mode = sr_ea >> 3;
                sr_ea_register = sr_ea & 7;
                if (sr_ea_mode inside {5, 6})
                    sr_extension_words = 1;
                else if (sr_ea_mode == 7) begin
                    if (sr_ea_register == 1)
                        sr_extension_words = 2;
                    else if ((sr_family != 2) && (sr_ea_register <= 4))
                        sr_extension_words = 1;
                    else if ((sr_family == 2) && (sr_ea_register == 0))
                        sr_extension_words = 1;
                    else
                        sr_extension_words = 0;
                end else
                    sr_extension_words = 0;
                sr_expected_words = 1 + sr_extension_words;

                if (sr_family == 2)
                    sr_legal = (sr_ea_mode == 0) ||
                               (sr_ea_mode inside {2, 3, 4, 5, 6}) ||
                               ((sr_ea_mode == 7) &&
                                (sr_ea_register <= 1));
                else
                    sr_legal = (sr_ea_mode == 0) ||
                               (sr_ea_mode inside {2, 3, 4, 5, 6}) ||
                               ((sr_ea_mode == 7) &&
                                (sr_ea_register <= 4));

                test_opcode = 16'(((sr_family == 0) ? 16'h44c0 :
                                   (sr_family == 1) ? 16'h46c0 : 16'h40c0) |
                                  sr_ea);
                set_window(M64K_PROFILE_M00, 32'h00000ce0,
                           COUNT_WIDTH'(3), test_opcode, 16'h0010,
                           16'h0180);
                assert (decode_valid);
                if (!sr_legal) begin
                    assert (decode_exception.valid);
                    assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
                end else begin
                    assert (!decode_exception.valid);
                    assert (decode_words ==
                            COUNT_WIDTH'(sr_expected_words));
                    assert (decode_uop.opcode == M64K_UOP_MOVE);
                    assert (decode_uop.size == M64K_OP_WORD);
                    if (sr_family == 0) begin
                        assert (decode_uop.instruction_id ==
                                M64K_INSN_MOVE_TO_CCR);
                        assert (decode_uop.destination.kind ==
                                M64K_OPERAND_SR);
                        assert (decode_uop.condition[0] &&
                                !decode_uop.privileged);
                    end else if (sr_family == 1) begin
                        assert (decode_uop.instruction_id ==
                                M64K_INSN_MOVE_TO_SR);
                        assert (decode_uop.destination.kind ==
                                M64K_OPERAND_SR);
                        assert (!decode_uop.condition[0] &&
                                decode_uop.privileged);
                    end else begin
                        assert (decode_uop.instruction_id ==
                                M64K_INSN_MOVE_FROM_SR);
                        assert (decode_uop.source_a.kind == M64K_OPERAND_SR);
                        assert (!decode_uop.privileged);
                    end

                    if (sr_extension_words != 0) begin
                        window_faults[7:4] = M64K_FAULT_BUS;
                        #1;
                        assert (decode_exception.valid &&
                                !decode_uop.valid);
                        assert (decode_exception.next_pc == 32'h00000ce2);
                        assert (decode_words == COUNT_WIDTH'(2));
                    end
                    if ((sr_ea_mode == 7) && (sr_ea_register == 1)) begin
                        set_window(M64K_PROFILE_M00, 32'h00000ce0,
                                   COUNT_WIDTH'(3), test_opcode, 16'h0010,
                                   16'h0180);
                        window_faults[11:8] = M64K_FAULT_BUS;
                        #1;
                        assert (decode_exception.valid &&
                                !decode_uop.valid);
                        assert (decode_exception.next_pc == 32'h00000ce4);
                        assert (decode_words == COUNT_WIDTH'(3));
                    end
                end
            end
        end

        set_window(M64K_PROFILE_M00, 32'hff06a8, COUNT_WIDTH'(1),
                   16'h4882, 16'd0, 16'd0); // EXT.W D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SIGN_EXTEND);
        assert (decode_uop.size == M64K_OP_WORD);
        assert (decode_uop.destination.index[2:0] == 3'd2);

        set_window(M64K_PROFILE_M00, 32'hff3a56, COUNT_WIDTH'(1),
                   16'h4e5e, 16'd0, 16'd0); // UNLK A6
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_UNLINK);
        assert (decode_uop.source_ea.register_index == 3'd6);

        set_window(M64K_PROFILE_M00, 32'hff405a, COUNT_WIDTH'(1),
                   16'he188, 16'd0, 16'd0); // LSL.L #8,D0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SHIFT);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.condition == 4'b1010);
        assert (decode_uop.immediate == 8);

        set_window(M64K_PROFILE_M00, 32'hff4060, COUNT_WIDTH'(1),
                   16'h4840, 16'd0, 16'd0); // SWAP D0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SWAP);
        assert (decode_uop.destination.index[2:0] == 3'd0);

        set_window(M64K_PROFILE_M00, 32'hff4062, COUNT_WIDTH'(1),
                   16'hc141, 16'd0, 16'd0); // EXG D1,D0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_EXCHANGE);
        assert (decode_uop.size == M64K_OP_LONG && decode_uop.flags_write == 0);
        assert (decode_uop.source_a.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.source_a.index[2:0] == 3'd1);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd0);

        set_window(M64K_PROFILE_M00, 32'hff4064, COUNT_WIDTH'(1),
                   16'hc14f, 16'd0, 16'd0); // EXG A7,A0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_EXCHANGE);
        assert (decode_uop.source_a.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.source_a.index[2:0] == 3'd7);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd0);

        set_window(M64K_PROFILE_M00, 32'hff4066, COUNT_WIDTH'(1),
                   16'hc589, 16'd0, 16'd0); // EXG A1,D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_EXCHANGE);
        assert (decode_uop.source_a.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.source_a.index[2:0] == 3'd1);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd2);

        set_window(M64K_PROFILE_M00, 32'hff4068, COUNT_WIDTH'(1),
                   16'h4ac3, 16'd0, 16'd0); // TAS D3
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ATOMIC);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.index[2:0] == 3'd3);
        assert (!decode_uop.memory_atomic && !decode_uop.memory_write);
        assert (decode_uop.flags_write ==
                (M64K_FLAG_N | M64K_FLAG_Z | M64K_FLAG_V | M64K_FLAG_C));

        set_window(M64K_PROFILE_M00, 32'hff406a, COUNT_WIDTH'(1),
                   16'h4ae8, 16'd0, 16'd0); // TAS 4(A0), missing extension
        assert (!decode_valid && decode_need_more && decode_words == 0);

        set_window(M64K_PROFILE_M00, 32'hff406a, COUNT_WIDTH'(2),
                   16'h4ae8, 16'h0004, 16'd0); // TAS 4(A0)
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ATOMIC);
        assert (decode_uop.destination_ea.kind == M64K_EA_DISPLACEMENT);
        assert (decode_uop.memory_atomic && decode_uop.memory_ordered);
        assert (decode_uop.memory_write && decode_uop.may_fault);

        window_faults[7:4] = M64K_FAULT_BUS;
        #1;
        assert (decode_valid && !decode_uop.valid && decode_words == 2);
        assert (decode_exception.vector == M64K_VECTOR_ACCESS_FAULT);
        assert (decode_exception.next_pc == 32'hff406c);

        set_window(M64K_PROFILE_M00, 32'hff406e, COUNT_WIDTH'(1),
                   16'h4ac8, 16'd0, 16'd0); // TAS A0 -- illegal
        assert (decode_valid && decode_words == 1 && decode_exception.valid);
        assert (!decode_uop.valid && decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff4070, COUNT_WIDTH'(2),
                   16'h4afa, 16'h0004, 16'd0); // TAS 4(PC) -- illegal
        assert (decode_valid && decode_words == 1 && decode_exception.valid);
        assert (!decode_uop.valid && decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff4072, COUNT_WIDTH'(2),
                   16'h4afb, 16'h0004, 16'd0); // TAS 4(PC,D0.W) -- illegal
        assert (decode_valid && decode_words == 1 && decode_exception.valid);
        assert (!decode_uop.valid && decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff4066, COUNT_WIDTH'(1),
                   16'h4482, 16'd0, 16'd0); // NEG.L D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_NEGATE);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.flags_write == M64K_FLAG_ALL);

        set_window(M64K_PROFILE_M00, 32'hff61f8, COUNT_WIDTH'(1),
                   16'h4242, 16'd0, 16'd0); // CLR.W D2
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_CLEAR);
        assert (decode_uop.size == M64K_OP_WORD);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.index == 2);
        assert (decode_uop.destination_ea.kind == M64K_EA_DATA_REGISTER);

        set_window(M64K_PROFILE_M00, 32'hff03ac, COUNT_WIDTH'(2),
                   16'h4a2f, 16'h0007, 16'd0); // TST.B 7(SP)
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_TEST);
        assert (decode_uop.source_ea.kind == M64K_EA_DISPLACEMENT);
        assert (decode_uop.source_ea.register_index == 7);

        set_window(M64K_PROFILE_M00, 32'hff03b8, COUNT_WIDTH'(2),
                   16'h007c, 16'h0700, 16'd0); // ORI.W #$700,SR
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_OR && decode_uop.privileged);
        assert (decode_uop.destination.kind == M64K_OPERAND_SR);

        set_window(M64K_PROFILE_M00, 32'hff0100, COUNT_WIDTH'(3),
                   16'h45f9, 16'h00ff, 16'h5c12); // LEA abs.l,A2
        assert (decode_valid && decode_words == 3 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_CALCULATE_EA);
        assert (decode_uop.source_ea.kind == M64K_EA_ABSOLUTE_LONG);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.index == 2);

        set_window(M64K_PROFILE_M00, 32'hff0110, COUNT_WIDTH'(2),
                   16'h487a, 16'h0010, 16'd0); // PEA 16(PC)
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_PUSH_EFFECTIVE_ADDRESS);
        assert (decode_uop.source_ea.kind == M64K_EA_PC_DISPLACEMENT);
        assert (decode_uop.memory_write);

        set_window(M64K_PROFILE_M00, 32'hff03c4, COUNT_WIDTH'(1),
                   16'hd080, 16'd0, 16'd0); // ADD.L D0,D0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ADD);
        assert (decode_uop.size == M64K_OP_LONG);
        assert (decode_uop.source_a.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.flags_write == M64K_FLAG_ALL);

        set_window(M64K_PROFILE_M00, 32'hff019a, COUNT_WIDTH'(1),
                   16'h4600, 16'd0, 16'd0); // NOT.B D0
        assert (decode_valid && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_NOT);
        assert (decode_uop.size == M64K_OP_BYTE);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);

        set_window(M64K_PROFILE_M00, 32'hff019c, COUNT_WIDTH'(1),
                   16'hc082, 16'd0, 16'd0); // AND.L D2,D0
        assert (decode_valid && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_AND);
        assert (decode_uop.source_a.index == 2);
        assert (decode_uop.destination.index == 0);

        set_window(M64K_PROFILE_M00, 32'hff01d8, COUNT_WIDTH'(3),
                   16'h0c82, 16'h0000, 16'h0100); // CMPI.L #256,D2
        assert (decode_valid && decode_words == 3 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_COMPARE);
        assert (decode_uop.immediate == 256);
        assert (decode_uop.destination.index == 2);

        set_window(M64K_PROFILE_M00, 32'hff021a, COUNT_WIDTH'(3),
                   16'h4ef9, 16'h00ff, 16'h1418); // JMP abs.l
        assert (decode_valid && decode_words == 3 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_JUMP);
        assert (decode_uop.source_ea.kind == M64K_EA_ABSOLUTE_LONG);

        set_window(M64K_PROFILE_M00, 32'hff0190, COUNT_WIDTH'(1),
                   16'h508f, 16'd0, 16'd0); // ADDQ.L #8,SP
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_ADD);
        assert (decode_uop.immediate == 8);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.index == 7);
        assert (decode_uop.flags_write == 0);

        // M68000PRM effective-address tables: TST does not gain An,
        // PC-relative or immediate forms until later family members; unary
        // modify and quick destinations must be alterable, and ADDQ.B An is
        // never legal.  Broad opcode masks must still reject these holes.
        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(1),
                   16'h4a48, 16'd0, 16'd0); // TST.W A0 (M20+ only)
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(2),
                   16'h4a3a, 16'h0002, 16'd0); // TST.B 2(PC), not M00
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(2),
                   16'h4a3c, 16'h0012, 16'd0); // TST.B #$12, not M00
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(1),
                   16'h4448, 16'd0, 16'd0); // NEG.W A0
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(2),
                   16'h46ba, 16'h0002, 16'd0); // NOT.L 2(PC)
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(1),
                   16'h5208, 16'd0, 16'd0); // ADDQ.B #1,A0
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(2),
                   16'h527a, 16'h0002, 16'd0); // ADDQ.W #1,2(PC)
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        // Immediate arithmetic/logical destinations follow the M00 data-
        // alterable tables.  CMPI is read-only but still does not acquire
        // An or PC-relative destinations until later family members.
        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(2),
                   16'h0648, 16'h0001, 16'd0); // ADDI.W #1,A0
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(3),
                   16'h003a, 16'h0001, 16'h0002); // ORI.B #1,2(PC)
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(2),
                   16'h0c48, 16'h0001, 16'd0); // CMPI.W #1,A0
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(3),
                   16'h0c3a, 16'h0001, 16'h0002); // CMPI.B #1,2(PC)
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        // MUL/DIV word source tables allow Dn, memory, PC-relative and
        // immediate data, but explicitly exclude address-register direct.
        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(1),
                   16'hc0c8, 16'd0, 16'd0); // MULU.W A0,D0
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0191, COUNT_WIDTH'(1),
                   16'h80c8, 16'd0, 16'd0); // DIVU.W A0,D0
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        set_window(M64K_PROFILE_M00, 32'hff0192, COUNT_WIDTH'(1),
                   16'h5380, 16'd0, 16'd0); // SUBQ.L #1,D0
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_SUBTRACT);
        assert (decode_uop.immediate == 1);
        assert (decode_uop.destination.kind == M64K_OPERAND_DATA_REGISTER);
        assert (decode_uop.flags_write == M64K_FLAG_ALL);

        set_window(M64K_PROFILE_M00, 32'h200, COUNT_WIDTH'(1),
                   16'hffff, 16'd0, 16'd0);
        assert (decode_valid && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        assert (decode_exception.opcode == 16'hffff);

        set_window(M64K_PROFILE_M00, 32'h300, COUNT_WIDTH'(1),
                   16'h4e4f, 16'd0, 16'd0);
        assert (decode_uop.opcode == M64K_UOP_TRAP);
        assert (decode_uop.exception_vector == 8'd47);

        set_window(M64K_PROFILE_M00, 32'h400, COUNT_WIDTH'(1),
                   16'h6002, 16'd0, 16'd0);
        assert (decode_uop.opcode == M64K_UOP_BRANCH);
        assert (decode_uop.immediate == 32'h404 && decode_words == 1);

        set_window(M64K_PROFILE_M00, 32'h500, COUNT_WIDTH'(1),
                   16'h61fc, 16'd0, 16'd0);
        assert (decode_uop.opcode == M64K_UOP_BRANCH_SUBROUTINE);
        assert (decode_uop.immediate == 32'h4fe);

        set_window(M64K_PROFILE_M00, 32'h600, COUNT_WIDTH'(1),
                   16'h6600, 16'd0, 16'd0);
        assert (!decode_valid && decode_need_more && decode_words == 0);

        set_window(M64K_PROFILE_M00, 32'h600, COUNT_WIDTH'(2),
                   16'h6600, 16'hfffa, 16'd0);
        assert (decode_valid && decode_words == 2);
        assert (decode_uop.condition == 4'h6);
        assert (decode_uop.immediate == 32'h5fc);
        assert (decode_uop.sequential_pc == 32'h604);

        window_faults[7:4] = M64K_FAULT_BUS;
        #1;
        assert (decode_valid && !decode_uop.valid && decode_words == 2);
        assert (decode_exception.vector == M64K_VECTOR_ACCESS_FAULT);
        assert (decode_exception.next_pc == 32'h602);

        // 0xff is an eight-bit displacement on M00/M10, but introduces a
        // 32-bit extension only on M20/M40.
        set_window(M64K_PROFILE_M00, 32'h700, COUNT_WIDTH'(1),
                   16'h60ff, 16'd0, 16'd0);
        assert (decode_valid && decode_words == 1);
        assert (decode_uop.immediate == 32'h701);

        set_window(M64K_PROFILE_M20, 32'h700, COUNT_WIDTH'(2),
                   16'h60ff, 16'h0000, 16'd0);
        assert (!decode_valid && decode_need_more);

        set_window(M64K_PROFILE_M20, 32'h700, COUNT_WIDTH'(3),
                   16'h60ff, 16'hffff, 16'hfff8);
        assert (decode_valid && decode_words == 3);
        assert (decode_uop.immediate == 32'h6fa);
        assert (decode_uop.sequential_pc == 32'h706);

        window_faults[11:8] = M64K_FAULT_PAGE;
        #1;
        assert (decode_valid && !decode_uop.valid && decode_words == 3);
        assert (decode_exception.next_pc == 32'h704);
        assert (decode_exception.rerunnable);

        set_window(M64K_PROFILE_M00, 32'h800, COUNT_WIDTH'(1),
                   16'h4e72, 16'd0, 16'd0);
        assert (!decode_valid && decode_need_more);
        set_window(M64K_PROFILE_M00, 32'h800, COUNT_WIDTH'(2),
                   16'h4e72, 16'h2700, 16'd0);
        assert (decode_valid && decode_words == 2);
        assert (decode_uop.opcode == M64K_UOP_STOP && decode_uop.privileged);
        assert (decode_uop.immediate == 32'h2700);

        set_window(M64K_PROFILE_M00, 32'h900, COUNT_WIDTH'(1),
                   16'h4e73, 16'd0, 16'd0);
        assert (decode_uop.opcode == M64K_UOP_EXCEPTION_RETURN);
        assert (decode_uop.privileged && decode_uop.may_fault);

        set_window(M64K_PROFILE_M00, 32'ha00, COUNT_WIDTH'(1),
                   16'h4e76, 16'd0, 16'd0);
        assert (decode_uop.opcode == M64K_UOP_TRAP);
        assert (decode_uop.condition == 4'h9);
        assert (decode_uop.flags_read == M64K_FLAG_V);

        set_window(M64K_PROFILE_M00, 32'hb00, COUNT_WIDTH'(1),
                   16'h4e71, 16'd0, 16'd0);
        window_faults[3:0] = M64K_FAULT_ALIGNMENT;
        #1;
        assert (decode_valid && decode_words == 1 && !decode_uop.valid);
        assert (decode_exception.vector == M64K_VECTOR_ADDRESS_ERROR);
        assert (!decode_exception.rerunnable);

        // PRM 4-107..4-110: JMP, JSR and LEA accept control EAs only.
        // Dn and postincrement are deliberately holes in the broad masks.
        set_window(M64K_PROFILE_M00, 32'hb10, COUNT_WIDTH'(1),
                   16'h4e80, 16'd0, 16'd0); // JSR D0 -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb12, COUNT_WIDTH'(1),
                   16'h4ed8, 16'd0, 16'd0); // JMP (A0)+ -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb14, COUNT_WIDTH'(1),
                   16'h41c0, 16'd0, 16'd0); // LEA D0,A0 -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        // PRM source-EA tables: generic encodings permit immediate data,
        // while AND/OR categorically exclude An even for word/long.
        set_window(M64K_PROFILE_M00, 32'hb20, COUNT_WIDTH'(2),
                   16'hc07c, 16'h0ff0, 16'd0); // AND.W #$0ff0,D0
        assert (decode_valid && decode_words == 2 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_AND);
        assert (decode_uop.source_a.kind == M64K_OPERAND_IMMEDIATE);
        assert (decode_uop.immediate == 32'h0000_0ff0);
        set_window(M64K_PROFILE_M00, 32'hb24, COUNT_WIDTH'(1),
                   16'hc048, 16'd0, 16'd0); // AND.W A0,D0 -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb26, COUNT_WIDTH'(1),
                   16'h8289, 16'd0, 16'd0); // OR.L A1,D1 -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb28, COUNT_WIDTH'(1),
                   16'hb2c8, 16'd0, 16'd0); // CMPA.W A0,A1 -- legal
        assert (decode_valid && decode_words == 1 && !decode_exception.valid);
        assert (decode_uop.opcode == M64K_UOP_COMPARE);
        assert (decode_uop.source_a.kind == M64K_OPERAND_ADDRESS_REGISTER);
        assert (decode_uop.destination.kind == M64K_OPERAND_ADDRESS_REGISTER);

        // PRM 4-115..4-119: MOVE.B cannot use An, and a MOVE destination
        // must be alterable.  PRM 4-128/4-129 additionally rejects
        // PC-relative register-to-memory MOVEM and direction-incompatible
        // pre/postincrement modes.
        set_window(M64K_PROFILE_M00, 32'hb2a, COUNT_WIDTH'(1),
                   16'h1008, 16'd0, 16'd0); // MOVE.B A0,D0 -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb2c, COUNT_WIDTH'(1),
                   16'h1040, 16'd0, 16'd0); // MOVE.B D0,A0 -- illegal
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb2e, COUNT_WIDTH'(3),
                   16'h48ba, 16'h0001, 16'h0004); // MOVEM.W D0,disp(PC)
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb34, COUNT_WIDTH'(2),
                   16'h4ca0, 16'h0001, 16'd0); // MOVEM.W -(A0),D0
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
        set_window(M64K_PROFILE_M00, 32'hb38, COUNT_WIDTH'(2),
                   16'h4898, 16'h0001, 16'd0); // MOVEM.W D0,(A0)+
        assert (decode_valid && !decode_uop.valid && decode_exception.valid);
        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);

        // M68000PRM 4-80/4-81: exhaust all 8x8 register combinations in
        // byte/word/long.  The superficially similar size=11 words belong to
        // the documented CMPA.L An,An encoding (PRM 4-78/4-79), not CMPM.
        for (int size_index = 0; size_index < 3; size_index++) begin
            for (int ax_index = 0; ax_index < 8; ax_index++) begin
                for (int ay_index = 0; ay_index < 8; ay_index++) begin
                    test_opcode = {4'b1011, ax_index[2:0], 1'b1,
                                   size_index[1:0], 3'b001,
                                   ay_index[2:0]};
                    set_window(M64K_PROFILE_M00, 32'hc00,
                               COUNT_WIDTH'(1), test_opcode, 16'd0, 16'd0);
                    assert (decode_valid && decode_words == 1 &&
                            !decode_exception.valid && decode_uop.valid);
                    assert (decode_uop.opcode == M64K_UOP_COMPARE_MEMORY);
                    assert (decode_uop.size ==
                            m64k_operand_size_t'(size_index));
                    assert (decode_uop.source_ea.kind ==
                            M64K_EA_POSTINCREMENT);
                    assert (decode_uop.source_ea.register_index ==
                            ay_index[2:0]);
                    assert (decode_uop.destination_ea.kind ==
                            M64K_EA_POSTINCREMENT);
                    assert (decode_uop.destination_ea.register_index ==
                            ax_index[2:0]);
                    assert (decode_uop.flags_write ==
                            (M64K_FLAG_N | M64K_FLAG_Z | M64K_FLAG_V | M64K_FLAG_C));
                    assert (decode_uop.may_fault &&
                            decode_uop.memory_ordered &&
                            !decode_uop.memory_write);
                end
            end
        end
        for (int ax_index = 0; ax_index < 8; ax_index++) begin
            for (int ay_index = 0; ay_index < 8; ay_index++) begin
                test_opcode = {4'b1011, ax_index[2:0], 3'b111, 3'b001,
                               ay_index[2:0]};
                set_window(M64K_PROFILE_M00, 32'hc00, COUNT_WIDTH'(1),
                           test_opcode, 16'd0, 16'd0);
                assert (decode_valid && decode_words == 1 &&
                        !decode_exception.valid && decode_uop.valid);
                assert (decode_uop.opcode == M64K_UOP_COMPARE);
                assert (decode_uop.size == M64K_OP_LONG);
                assert (decode_uop.source_ea.kind == M64K_EA_ADDRESS_REGISTER);
                assert (decode_uop.source_ea.register_index ==
                        ay_index[2:0]);
                assert (decode_uop.destination_ea.kind ==
                        M64K_EA_ADDRESS_REGISTER);
                assert (decode_uop.destination_ea.register_index ==
                        ax_index[2:0]);
            end
        end

        // PRM 4-20..4-23, 4-112..4-115 and 4-159..4-165: exhaust all
        // 3072 register-shift words.  Every field combination is legal for
        // each of the three sizes; count field zero means immediate eight,
        // while register counts select the complete Dn and are reduced
        // modulo 64 by execution.
        for (int size_index = 0; size_index < 3; size_index++) begin
            for (int direction_index = 0; direction_index < 2;
                 direction_index++) begin
                for (int count_source_index = 0; count_source_index < 2;
                     count_source_index++) begin
                    for (int kind_index = 0; kind_index < 4; kind_index++) begin
                        for (int count_field = 0; count_field < 8;
                             count_field++) begin
                            for (int destination_index = 0;
                                 destination_index < 8;
                                 destination_index++) begin
                                test_opcode = 16'(16'he000 |
                                    (count_field << 9) |
                                    (direction_index << 8) |
                                    (size_index << 6) |
                                    (count_source_index << 5) |
                                    (kind_index << 3) |
                                    destination_index);
                                set_window(M64K_PROFILE_M00, 32'hc40,
                                           COUNT_WIDTH'(1), test_opcode,
                                           16'd0, 16'd0);
                                assert (decode_valid && decode_words == 1 &&
                                        !decode_exception.valid &&
                                        decode_uop.valid);
                                assert (decode_uop.instruction_id ==
                                        M64K_INSN_SHIFT_REGISTER);
                                assert (decode_uop.opcode == M64K_UOP_SHIFT &&
                                        decode_uop.size ==
                                        m64k_operand_size_t'(size_index));
                                assert (decode_uop.condition ==
                                        {direction_index[0], kind_index[1:0],
                                         count_source_index[0]});
                                assert (decode_uop.destination.index[2:0] ==
                                        destination_index[2:0]);
                                if (count_source_index != 0) begin
                                    assert (decode_uop.source_a.kind ==
                                            M64K_OPERAND_DATA_REGISTER);
                                    assert (decode_uop.source_a.index[2:0] ==
                                            count_field[2:0]);
                                end else begin
                                    assert (decode_uop.source_a.kind ==
                                            M64K_OPERAND_IMMEDIATE);
                                    assert (decode_uop.immediate ==
                                            ((count_field == 0) ? 8 :
                                                                  count_field));
                                end
                                assert (decode_uop.flags_read == M64K_FLAG_X &&
                                        decode_uop.flags_write == M64K_FLAG_ALL);
                            end
                        end
                    end
                end
            end
        end

        // PRM 4-191/4-192: M00 TST has three sizes and exactly 50 legal
        // effective-address encodings per size.  Exhaust all 192 size/EA
        // combinations rather than sampling aliases: 150 are TST and 42 are
        // M20-only or otherwise illegal on M00.  The size=11 space is TAS and
        // is intentionally outside this TST matrix.
        for (int size_index = 0; size_index < 3; size_index++) begin
            for (int ea_index = 0; ea_index < 64; ea_index++) begin
                int ea_mode;
                int ea_register;
                int extension_count;
                logic legal_tst_ea;
                ea_mode = ea_index >> 3;
                ea_register = ea_index & 7;
                legal_tst_ea = (ea_mode == 0) ||
                               ((ea_mode >= 2) && (ea_mode <= 6)) ||
                               ((ea_mode == 7) && (ea_register <= 1));
                extension_count = ((ea_mode == 5) || (ea_mode == 6) ||
                                   ((ea_mode == 7) && (ea_register == 0))) ?
                                  1 :
                                  ((ea_mode == 7) && (ea_register == 1)) ?
                                  2 : 0;
                test_opcode = 16'('h4a00 | (size_index << 6) | ea_index);
                set_window(M64K_PROFILE_M00, 32'hc80,
                           COUNT_WIDTH'(1 + extension_count), test_opcode,
                           16'h0000, 16'h0220);
                if (legal_tst_ea) begin
                    assert (decode_valid && !decode_exception.valid &&
                            decode_uop.valid);
                    assert (decode_words == 1 + extension_count);
                    assert (decode_uop.instruction_id == M64K_INSN_TST &&
                            decode_uop.opcode == M64K_UOP_TEST);
                    assert (decode_uop.size == m64k_operand_size_t'(size_index));
                    assert (decode_uop.flags_write ==
                            (M64K_FLAG_N | M64K_FLAG_Z | M64K_FLAG_V | M64K_FLAG_C));
                    assert (!decode_uop.memory_write);
                    assert (decode_uop.may_fault == (ea_mode != 0));

                    // Every extension-bearing form reports an extension
                    // fetch fault before issuing the operand read.
                    if (extension_count != 0) begin
                        window_faults[7:4] = M64K_FAULT_BUS;
                        #1;
                        assert (!decode_uop.valid && decode_exception.valid);
                        assert (decode_words == 2);
                        assert (decode_exception.vector ==
                                M64K_VECTOR_ACCESS_FAULT);
                        assert (decode_exception.next_pc == 32'h0000_0c82);
                    end
                end else begin
                    assert (decode_valid && !decode_uop.valid &&
                            decode_exception.valid);
                    assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
                end
            end
        end

        // PRM 4-73/4-74, 4-142/4-143 and 4-147/4-148 give CLR, NEG and
        // NOT the same M00 data-alterable EA product as TST: 50 legal words
        // per size.  Exhaust the 576 size/EA candidates for all three
        // families (450 legal, 126 illegal) and every extension-fault path.
        for (int unary_index = 0; unary_index < 3; unary_index++) begin
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int ea_index = 0; ea_index < 64; ea_index++) begin
                    int ea_mode;
                    int ea_register;
                    int extension_count;
                    int opcode_base;
                    logic legal_unary_ea;
                    ea_mode = ea_index >> 3;
                    ea_register = ea_index & 7;
                    legal_unary_ea = (ea_mode == 0) ||
                                     ((ea_mode >= 2) && (ea_mode <= 6)) ||
                                     ((ea_mode == 7) && (ea_register <= 1));
                    extension_count =
                        ((ea_mode == 5) || (ea_mode == 6) ||
                         ((ea_mode == 7) && (ea_register == 0))) ? 1 :
                        ((ea_mode == 7) && (ea_register == 1)) ? 2 : 0;
                    case (unary_index)
                        0: opcode_base = 16'h4200; // CLR
                        1: opcode_base = 16'h4400; // NEG
                        default: opcode_base = 16'h4600; // NOT
                    endcase
                    test_opcode = 16'(opcode_base | (size_index << 6) |
                                      ea_index);
                    set_window(M64K_PROFILE_M00, 32'hcc0,
                               COUNT_WIDTH'(1 + extension_count), test_opcode,
                               16'h0000, 16'h0220);
                    if (legal_unary_ea) begin
                        assert (decode_valid && !decode_exception.valid &&
                                decode_uop.valid);
                        assert (decode_words == 1 + extension_count);
                        assert (decode_uop.size ==
                                m64k_operand_size_t'(size_index));
                        assert (decode_uop.memory_write == (ea_mode != 0));
                        assert (decode_uop.may_fault == (ea_mode != 0));
                        case (unary_index)
                            0: begin
                                assert (decode_uop.instruction_id ==
                                        M64K_INSN_CLR);
                                assert (decode_uop.opcode == M64K_UOP_CLEAR);
                                assert (decode_uop.flags_write ==
                                    (M64K_FLAG_N | M64K_FLAG_Z |
                                     M64K_FLAG_V | M64K_FLAG_C));
                            end
                            1: begin
                                assert (decode_uop.instruction_id ==
                                        M64K_INSN_NEG);
                                assert (decode_uop.opcode == M64K_UOP_NEGATE);
                                assert (decode_uop.flags_write == M64K_FLAG_ALL);
                            end
                            default: begin
                                assert (decode_uop.instruction_id ==
                                        M64K_INSN_NOT);
                                assert (decode_uop.opcode == M64K_UOP_NOT);
                                assert (decode_uop.flags_write ==
                                    (M64K_FLAG_N | M64K_FLAG_Z |
                                     M64K_FLAG_V | M64K_FLAG_C));
                            end
                        endcase

                        if (extension_count != 0) begin
                            window_faults[7:4] = M64K_FAULT_BUS;
                            #1;
                            assert (!decode_uop.valid &&
                                    decode_exception.valid);
                            assert (decode_words == 2);
                            assert (decode_exception.vector ==
                                    M64K_VECTOR_ACCESS_FAULT);
                            assert (decode_exception.next_pc == 32'h0000_0cc2);
                        end
                    end else begin
                        assert (decode_valid && !decode_uop.valid &&
                                decode_exception.valid);
                        assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
                    end
                end
            end
        end

        // Motorola M68000 Family Programmer's Reference Manual (1992),
        // NBCD, pp. 4-140--4-142: byte-only data-alterable destination.
        // Exhaust all 64 EA encodings: 50 are legal and 14 are illegal.
        for (int ea_index = 0; ea_index < 64; ea_index++) begin
            int ea_mode;
            int ea_register;
            int extension_count;
            logic legal_nbcd_ea;
            ea_mode = ea_index >> 3;
            ea_register = ea_index & 7;
            legal_nbcd_ea = (ea_mode == 0) ||
                            ((ea_mode >= 2) && (ea_mode <= 6)) ||
                            ((ea_mode == 7) && (ea_register <= 1));
            extension_count =
                ((ea_mode == 5) || (ea_mode == 6) ||
                 ((ea_mode == 7) && (ea_register == 0))) ? 1 :
                ((ea_mode == 7) && (ea_register == 1)) ? 2 : 0;
            test_opcode = 16'(16'h4800 | ea_index);
            set_window(M64K_PROFILE_M00, 32'hce0,
                       COUNT_WIDTH'(1 + extension_count), test_opcode,
                       16'h0000, 16'h0220);
            if (legal_nbcd_ea) begin
                assert (decode_valid && !decode_exception.valid &&
                        decode_uop.valid);
                assert (decode_words == 1 + extension_count);
                assert (decode_uop.instruction_id == M64K_INSN_NBCD);
                assert (decode_uop.opcode == M64K_UOP_SUBTRACT_EXTEND);
                assert (decode_uop.size == M64K_OP_BYTE);
                assert (decode_uop.memory_write == (ea_mode != 0));
                assert (decode_uop.may_fault == (ea_mode != 0));
                assert (decode_uop.flags_read == (M64K_FLAG_X |
                                                   M64K_FLAG_Z));
                assert (decode_uop.flags_write == (M64K_FLAG_X |
                                                    M64K_FLAG_Z |
                                                    M64K_FLAG_C));
                if (extension_count != 0) begin
                    window_faults[7:4] = M64K_FAULT_BUS;
                    #1;
                    assert (!decode_uop.valid && decode_exception.valid);
                    assert (decode_words == 2);
                    assert (decode_exception.vector ==
                            M64K_VECTOR_ACCESS_FAULT);
                    assert (decode_exception.next_pc == 32'h0000_0ce2);
                end
            end else begin
                assert (decode_valid && !decode_uop.valid &&
                        decode_exception.valid);
                assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
            end
        end

        // PRM 4-10..4-12 and 4-180..4-182: exhaust the ADDQ/SUBQ
        // byte/word/long destination space.  Across both operations and all
        // eight quick fields this is 2,656 legal words and 416 illegal EA
        // combinations.  The size-11 plane is Scc/DBcc and is audited below.
        for (int quick_operation = 0; quick_operation < 2;
             quick_operation++) begin
            for (int quick_field = 0; quick_field < 8; quick_field++) begin
                for (int size_index = 0; size_index < 3; size_index++) begin
                    for (int ea_index = 0; ea_index < 64; ea_index++) begin
                        int ea_mode;
                        int ea_register;
                        int extension_count;
                        logic legal_data_ea;
                        logic legal_address_ea;
                        ea_mode = ea_index >> 3;
                        ea_register = ea_index & 7;
                        legal_data_ea = (ea_mode == 0) ||
                                        ((ea_mode >= 2) && (ea_mode <= 6)) ||
                                        ((ea_mode == 7) &&
                                         (ea_register <= 1));
                        legal_address_ea = (ea_mode == 1) &&
                                           (size_index != 0);
                        extension_count =
                            ((ea_mode == 5) || (ea_mode == 6) ||
                             ((ea_mode == 7) && (ea_register == 0))) ? 1 :
                            ((ea_mode == 7) && (ea_register == 1)) ? 2 : 0;
                        test_opcode = 16'(16'h5000 | (quick_field << 9) |
                            (quick_operation << 8) | (size_index << 6) |
                            ea_index);
                        set_window(M64K_PROFILE_M00, 32'hca0,
                            COUNT_WIDTH'(1 + extension_count), test_opcode,
                            16'h0000, 16'h0220);
                        if (legal_data_ea || legal_address_ea) begin
                            assert (decode_valid && !decode_exception.valid &&
                                    decode_uop.valid);
                            assert (decode_words == 1 + extension_count);
                            assert (decode_uop.instruction_id ==
                                (quick_operation ? M64K_INSN_SUBQ :
                                                   M64K_INSN_ADDQ));
                            assert (decode_uop.opcode ==
                                (quick_operation ? M64K_UOP_SUBTRACT :
                                                   M64K_UOP_ADD));
                            assert (decode_uop.size ==
                                    m64k_operand_size_t'(size_index));
                            assert (decode_uop.immediate ==
                                    ((quick_field == 0) ? 8 : quick_field));
                            assert (decode_uop.flags_write ==
                                    (legal_address_ea ? 5'd0 : M64K_FLAG_ALL));
                            assert (decode_uop.memory_write ==
                                    (legal_data_ea && (ea_mode != 0)));
                            assert (decode_uop.may_fault ==
                                    (legal_data_ea && (ea_mode != 0)));

                            if (extension_count != 0) begin
                                window_faults[7:4] = M64K_FAULT_BUS;
                                #1;
                                assert (!decode_uop.valid &&
                                        decode_exception.valid);
                                assert (decode_words == 2);
                                assert (decode_exception.vector ==
                                        M64K_VECTOR_ACCESS_FAULT);
                                assert (decode_exception.next_pc ==
                                        32'h0000_0ca2);
                            end
                        end else begin
                            assert (decode_valid && !decode_uop.valid &&
                                    decode_exception.valid);
                            assert (decode_exception.vector ==
                                    M64K_VECTOR_ILLEGAL);
                        end
                    end
                end
            end
        end

        // PRM 4-172/4-173: all 16 Scc conditions share the byte data-
        // alterable destination product.  Exhaust all 1,024 condition/EA
        // candidates: 800 Scc words, 128 overlapping DBcc words in the
        // mode-1 slots, and 96 genuinely illegal mode-7 holes.
        for (int condition_index = 0; condition_index < 16;
             condition_index++) begin
            for (int ea_index = 0; ea_index < 64; ea_index++) begin
                int ea_mode;
                int ea_register;
                int extension_count;
                logic legal_scc_ea;
                ea_mode = ea_index >> 3;
                ea_register = ea_index & 7;
                legal_scc_ea = (ea_mode == 0) ||
                               ((ea_mode >= 2) && (ea_mode <= 6)) ||
                               ((ea_mode == 7) && (ea_register <= 1));
                extension_count =
                    ((ea_mode == 5) || (ea_mode == 6) ||
                     ((ea_mode == 7) && (ea_register == 0))) ? 1 :
                    ((ea_mode == 7) && (ea_register == 1)) ? 2 : 0;
                test_opcode = 16'(16'h50c0 | (condition_index << 8) |
                                  ea_index);
                set_window(M64K_PROFILE_M00, 32'hce0,
                           COUNT_WIDTH'(1 + extension_count), test_opcode,
                           16'h0000, 16'h0220);
                if (legal_scc_ea) begin
                    assert (decode_valid && !decode_exception.valid &&
                            decode_uop.valid);
                    assert (decode_words == 1 + extension_count);
                    assert (decode_uop.instruction_id ==
                            8'(M64K_INSN_ST + condition_index) &&
                            decode_uop.opcode == M64K_UOP_SET_CONDITION);
                    assert (decode_uop.size == M64K_OP_BYTE);
                    assert (decode_uop.condition == condition_index[3:0]);
                    assert (decode_uop.flags_read ==
                            (M64K_FLAG_N | M64K_FLAG_Z | M64K_FLAG_V | M64K_FLAG_C));
                    assert (decode_uop.flags_write == 5'd0);
                    assert (decode_uop.memory_write == (ea_mode != 0));
                    assert (decode_uop.may_fault == (ea_mode != 0));

                    if (extension_count != 0) begin
                        window_faults[7:4] = M64K_FAULT_BUS;
                        #1;
                        assert (!decode_uop.valid && decode_exception.valid);
                        assert (decode_words == 2);
                        assert (decode_exception.vector ==
                                M64K_VECTOR_ACCESS_FAULT);
                        assert (decode_exception.next_pc == 32'h0000_0ce2);
                    end
                end else if (ea_mode == 1) begin
                    // 0101 cccc 11001 rrr is DBcc, not an illegal Scc An
                    // destination.  Its mandatory displacement is absent
                    // from this one-word window.
                    assert (!decode_valid && decode_need_more &&
                            !decode_exception.valid);
                end else begin
                    assert (decode_valid && !decode_uop.valid &&
                            decode_exception.valid);
                    assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
                end
            end
        end

        // PRM 4-22/4-23 and 4-161/4-165: exhaust the complete 512-word
        // memory-shift subspace.  Eight operations share 42 legal memory
        // alterable EAs; register, PC-relative and immediate holes are illegal.
        for (int operation_index = 0; operation_index < 8;
             operation_index++) begin
            for (int ea_index = 0; ea_index < 64; ea_index++) begin
                int ea_mode;
                int ea_register;
                int extension_count;
                logic legal_memory_ea;
                ea_mode = ea_index >> 3;
                ea_register = ea_index & 7;
                legal_memory_ea = ((ea_mode >= 2) && (ea_mode <= 6)) ||
                                  ((ea_mode == 7) && (ea_register <= 1));
                extension_count = ((ea_mode == 5) || (ea_mode == 6) ||
                                   ((ea_mode == 7) && (ea_register == 0))) ?
                                  1 :
                                  ((ea_mode == 7) && (ea_register == 1)) ?
                                  2 : 0;
                test_opcode = 16'('he0c0 | (operation_index << 8) |
                                  ea_index);
                set_window(M64K_PROFILE_M00, 32'hd00,
                           COUNT_WIDTH'(1 + extension_count), test_opcode,
                           16'h0200, 16'h0000);
                if (legal_memory_ea) begin
                    assert (decode_valid && !decode_exception.valid &&
                            decode_uop.valid);
                    assert (decode_words == 1 + extension_count);
                    assert (decode_uop.opcode == M64K_UOP_SHIFT &&
                            decode_uop.size == M64K_OP_WORD);
                    assert (decode_uop.condition[3] ==
                            operation_index[0]);
                    assert (decode_uop.condition[2:1] ==
                            operation_index[2:1]);
                    assert (decode_uop.immediate == 32'd1);
                    assert (decode_uop.memory_write &&
                            decode_uop.memory_ordered &&
                            decode_uop.may_fault);
                end else begin
                    assert (decode_valid && !decode_uop.valid &&
                            decode_exception.valid);
                    assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
                end
            end
        end

        // PRM 4-8/4-10, 4-15/4-19, 4-78/4-79, 4-101/4-103,
        // 4-152/4-154 and 4-178/4-180: classify every low-byte encoding
        // for the six generic immediate families.  Each has 150 generic
        // M00 words (three sizes times 50 data-alterable EAs).  The logical
        // families additionally own two exact CCR/SR encodings.
        for (int operation_index = 0; operation_index < 6;
             operation_index++) begin
            int generic_count;
            int special_count;
            int illegal_count;
            logic [15:0] operation_base;
            generic_count = 0;
            special_count = 0;
            illegal_count = 0;
            case (operation_index)
                0: operation_base = 16'h0000;
                1: operation_base = 16'h0200;
                2: operation_base = 16'h0400;
                3: operation_base = 16'h0600;
                4: operation_base = 16'h0a00;
                default: operation_base = 16'h0c00;
            endcase
            for (int low_byte = 0; low_byte < 256; low_byte++) begin
                int size_index;
                int ea_mode;
                int ea_register;
                int immediate_words;
                int extension_words;
                logic generic_legal;
                logic special_legal;
                logic [7:0] expected_id;
                size_index = low_byte >> 6;
                ea_mode = (low_byte >> 3) & 7;
                ea_register = low_byte & 7;
                immediate_words = (size_index == 2) ? 2 : 1;
                extension_words = ((ea_mode == 5) || (ea_mode == 6) ||
                                   ((ea_mode == 7) &&
                                    (ea_register == 0))) ? 1 :
                                  ((ea_mode == 7) &&
                                   (ea_register == 1)) ? 2 : 0;
                generic_legal = (size_index < 3) &&
                    ((ea_mode == 0) ||
                     ((ea_mode >= 2) && (ea_mode <= 6)) ||
                     ((ea_mode == 7) && (ea_register <= 1)));
                special_legal = ((operation_index == 0) ||
                                 (operation_index == 1) ||
                                 (operation_index == 4)) &&
                                ((low_byte == 8'h3c) ||
                                 (low_byte == 8'h7c));
                case (operation_index)
                    0: expected_id = M64K_INSN_ORI;
                    1: expected_id = M64K_INSN_ANDI;
                    2: expected_id = M64K_INSN_SUBI;
                    3: expected_id = M64K_INSN_ADDI;
                    4: expected_id = M64K_INSN_EORI;
                    default: expected_id = M64K_INSN_CMPI;
                endcase

                test_opcode = operation_base | 16'(low_byte);
                set_window(M64K_PROFILE_M00, 32'h0000_0e00,
                           COUNT_WIDTH'(1 + immediate_words +
                                        extension_words),
                           test_opcode, 16'h0001, 16'h0000);
                if (generic_legal) begin
                    generic_count = generic_count + 1;
                    assert (decode_valid && decode_uop.valid &&
                            !decode_exception.valid);
                    assert (decode_uop.instruction_id == expected_id);
                    assert (decode_words ==
                            1 + immediate_words + extension_words);
                    assert (decode_uop.size == m64k_operand_size_t'(size_index));
                    assert (decode_uop.flags_write ==
                            (((operation_index == 2) ||
                              (operation_index == 3)) ? M64K_FLAG_ALL :
                             (M64K_FLAG_N | M64K_FLAG_Z |
                              M64K_FLAG_V | M64K_FLAG_C)));
                    assert (decode_uop.memory_write ==
                            ((ea_mode != 0) && (operation_index != 5)));
                    assert (decode_uop.may_fault == (ea_mode != 0));
                end else if (special_legal) begin
                    special_count = special_count + 1;
                    assert (decode_valid && decode_uop.valid &&
                            !decode_exception.valid);
                    case (operation_index)
                        0: assert (decode_uop.instruction_id ==
                            ((low_byte == 8'h3c) ? M64K_INSN_ORI_CCR :
                                                   M64K_INSN_ORI_SR));
                        1: assert (decode_uop.instruction_id ==
                            ((low_byte == 8'h3c) ? M64K_INSN_ANDI_CCR :
                                                   M64K_INSN_ANDI_SR));
                        default: assert (decode_uop.instruction_id ==
                            ((low_byte == 8'h3c) ? M64K_INSN_EORI_CCR :
                                                   M64K_INSN_EORI_SR));
                    endcase
                end else begin
                    illegal_count = illegal_count + 1;
                    assert (decode_valid && !decode_uop.valid &&
                            decode_exception.valid);
                    assert (decode_exception.vector == M64K_VECTOR_ILLEGAL);
                end
            end
            assert (generic_count == 150);
            assert (special_count ==
                    (((operation_index == 0) || (operation_index == 1) ||
                      (operation_index == 4)) ? 2 : 0));
            assert (illegal_count == 256 - generic_count - special_count);
        end

        // PRM 4-3/4-5, 4-14/4-16, 4-74/4-76, 4-149/4-151 and
        // 4-173/4-175: exhaust all five <ea>,Dn binary planes.  ADD,
        // SUB and CMP accept An for word/long; AND and OR never do.
        for (int operation_index = 0; operation_index < 5;
             operation_index++) begin
            int legal_count;
            int illegal_count;
            logic [3:0] operation_nibble;
            legal_count = 0;
            illegal_count = 0;
            case (operation_index)
                0: operation_nibble = 4'hd;
                1: operation_nibble = 4'h9;
                2: operation_nibble = 4'hc;
                3: operation_nibble = 4'h8;
                default: operation_nibble = 4'hb;
            endcase
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int destination_register = 0;
                     destination_register < 8; destination_register++) begin
                    for (int ea_index = 0; ea_index < 64; ea_index++) begin
                        int ea_mode;
                        int ea_register;
                        int extension_words;
                        logic legal_source;
                        logic [7:0] expected_id;
                        ea_mode = ea_index >> 3;
                        ea_register = ea_index & 7;
                        extension_words =
                            ((ea_mode == 5) || (ea_mode == 6) ||
                             ((ea_mode == 7) &&
                              ((ea_register == 0) || (ea_register == 2) ||
                               (ea_register == 3)))) ? 1 :
                            (((ea_mode == 7) &&
                              ((ea_register == 1) ||
                               ((ea_register == 4) &&
                                (size_index == 2))))) ? 2 :
                            (((ea_mode == 7) && (ea_register == 4)) ? 1 : 0);
                        legal_source = (ea_mode <= 6) ||
                                       ((ea_mode == 7) &&
                                        (ea_register <= 4));
                        if (ea_mode == 1)
                            legal_source = (size_index != 0) &&
                                ((operation_index == 0) ||
                                 (operation_index == 1) ||
                                 (operation_index == 4));
                        case (operation_index)
                            0: expected_id =
                                8'(M64K_INSN_ADD_B + size_index);
                            1: expected_id = (size_index == 0) ?
                                M64K_INSN_SUB_B : (size_index == 1) ?
                                M64K_INSN_SUB_W : M64K_INSN_SUB_L;
                            2: expected_id = (size_index == 0) ?
                                M64K_INSN_AND_B : (size_index == 1) ?
                                M64K_INSN_AND_W : M64K_INSN_AND_L;
                            3: expected_id =
                                8'(M64K_INSN_OR_B + size_index);
                            default: expected_id = (size_index == 0) ?
                                M64K_INSN_CMP_B : (size_index == 1) ?
                                M64K_INSN_CMP_W : M64K_INSN_CMP_L;
                        endcase
                        test_opcode = {operation_nibble,
                            destination_register[2:0], 1'b0,
                            size_index[1:0], ea_index[5:0]};
                        set_window(M64K_PROFILE_M00, 32'h0000_1000,
                                   COUNT_WIDTH'(1 + extension_words),
                                   test_opcode, 16'h0000, 16'h0000);
                        if (legal_source) begin
                            legal_count = legal_count + 1;
                            assert (decode_valid && decode_uop.valid &&
                                    !decode_exception.valid);
                            assert (decode_uop.instruction_id == expected_id);
                            assert (decode_uop.destination.kind ==
                                    M64K_OPERAND_DATA_REGISTER);
                            assert (decode_uop.destination.index[2:0] ==
                                    destination_register[2:0]);
                            assert (!decode_uop.memory_write);
                        end else begin
                            illegal_count = illegal_count + 1;
                            assert (decode_valid && !decode_uop.valid &&
                                    decode_exception.valid);
                            assert (decode_exception.vector ==
                                    M64K_VECTOR_ILLEGAL);
                        end
                    end
                end
            end
            assert (legal_count ==
                    (((operation_index == 0) || (operation_index == 1) ||
                      (operation_index == 4)) ? 1400 : 1272));
            assert (illegal_count == 1536 - legal_count);
        end

        // PRM 4-6/4-7, 4-76/4-77 and 4-176/4-177: ADDA, SUBA
        // and CMPA accept every M00 source addressing mode in word/long.
        // Word sources are sign-extended and the operation is always 32-bit.
        for (int operation_index = 0; operation_index < 3;
             operation_index++) begin
            int legal_count;
            int illegal_count;
            logic [3:0] operation_nibble;
            legal_count = 0;
            illegal_count = 0;
            operation_nibble = (operation_index == 0) ? 4'hd :
                               (operation_index == 1) ? 4'h9 : 4'hb;
            for (int size_index = 0; size_index < 2; size_index++) begin
                for (int destination_register = 0;
                     destination_register < 8; destination_register++) begin
                    for (int ea_index = 0; ea_index < 64; ea_index++) begin
                        int ea_mode;
                        int ea_register;
                        int extension_words;
                        logic legal_source;
                        logic [7:0] expected_id;
                        ea_mode = ea_index >> 3;
                        ea_register = ea_index & 7;
                        extension_words =
                            ((ea_mode == 5) || (ea_mode == 6) ||
                             ((ea_mode == 7) &&
                              ((ea_register == 0) || (ea_register == 2) ||
                               (ea_register == 3)))) ? 1 :
                            (((ea_mode == 7) &&
                              ((ea_register == 1) ||
                               ((ea_register == 4) && size_index)))) ? 2 :
                            (((ea_mode == 7) && (ea_register == 4)) ? 1 : 0);
                        legal_source = (ea_mode <= 6) ||
                                       ((ea_mode == 7) &&
                                        (ea_register <= 4));
                        case (operation_index)
                            0: expected_id = size_index ? M64K_INSN_ADDA_L :
                                                        M64K_INSN_ADDA_W;
                            1: expected_id = size_index ? M64K_INSN_SUBA_L :
                                                        M64K_INSN_SUBA_W;
                            default: expected_id = size_index ? M64K_INSN_CMPA_L :
                                                              M64K_INSN_CMPA_W;
                        endcase
                        test_opcode = {operation_nibble,
                            destination_register[2:0], size_index[0], 2'b11,
                            ea_index[5:0]};
                        set_window(M64K_PROFILE_M00, 32'h0000_1200,
                                   COUNT_WIDTH'(1 + extension_words),
                                   test_opcode, 16'h0000, 16'h0000);
                        if (legal_source) begin
                            legal_count = legal_count + 1;
                            assert (decode_valid && decode_uop.valid &&
                                    !decode_exception.valid);
                            assert (decode_uop.instruction_id == expected_id);
                            assert (decode_uop.destination.kind ==
                                    M64K_OPERAND_ADDRESS_REGISTER);
                            assert (decode_uop.destination.index[2:0] ==
                                    destination_register[2:0]);
                            assert (decode_uop.size ==
                                    (size_index ? M64K_OP_LONG : M64K_OP_WORD));
                            assert (!decode_uop.memory_write);
                            assert (decode_uop.flags_write ==
                                    ((operation_index == 2) ?
                                     (M64K_FLAG_N | M64K_FLAG_Z |
                                      M64K_FLAG_V | M64K_FLAG_C) : 5'd0));
                        end else begin
                            illegal_count = illegal_count + 1;
                            assert (decode_valid && !decode_uop.valid &&
                                    decode_exception.valid);
                            assert (decode_exception.vector ==
                                    M64K_VECTOR_ILLEGAL);
                        end
                    end
                end
            end
            assert (legal_count == 976);
            assert (illegal_count == 48);
        end

        // The reverse direction has 5,232 generic words.  Its register and
        // address-register slots are not uniformly illegal: 1,408 are exact
        // ADDX/SUBX, ABCD/SBCD, EXG or CMPM encodings selected by the
        // generated specificity order.  Classify every word explicitly.
        for (int operation_index = 0; operation_index < 5;
             operation_index++) begin
            int generic_count;
            int overlap_count;
            int illegal_count;
            logic [3:0] operation_nibble;
            generic_count = 0;
            overlap_count = 0;
            illegal_count = 0;
            case (operation_index)
                0: operation_nibble = 4'hd;
                1: operation_nibble = 4'h9;
                2: operation_nibble = 4'hc;
                3: operation_nibble = 4'h8;
                default: operation_nibble = 4'hb;
            endcase
            for (int size_index = 0; size_index < 3; size_index++) begin
                for (int source_register = 0;
                     source_register < 8; source_register++) begin
                    for (int ea_index = 0; ea_index < 64; ea_index++) begin
                        int ea_mode;
                        int ea_register;
                        int extension_words;
                        logic generic_legal;
                        logic overlap_legal;
                        logic [7:0] expected_overlap_id;
                        ea_mode = ea_index >> 3;
                        ea_register = ea_index & 7;
                        extension_words =
                            ((ea_mode == 5) || (ea_mode == 6) ||
                             ((ea_mode == 7) && (ea_register == 0))) ? 1 :
                            (((ea_mode == 7) && (ea_register == 1)) ? 2 : 0);
                        generic_legal = ((ea_mode >= 2) &&
                                         (ea_mode <= 6)) ||
                                        ((ea_mode == 7) &&
                                         (ea_register <= 1)) ||
                                        ((operation_index == 4) &&
                                         (ea_mode == 0));
                        overlap_legal = 1'b0;
                        expected_overlap_id = '0;
                        if (((operation_index == 0) ||
                             (operation_index == 1)) &&
                            ((ea_mode == 0) || (ea_mode == 1))) begin
                            overlap_legal = 1'b1;
                            if (operation_index == 0)
                                expected_overlap_id = (ea_mode == 0) ?
                                    8'(M64K_INSN_ADDX_REG_B + size_index) :
                                    8'(M64K_INSN_ADDX_MEM_B + size_index);
                            else
                                expected_overlap_id = (ea_mode == 0) ?
                                    8'(M64K_INSN_SUBX_REG_B + size_index) :
                                    8'(M64K_INSN_SUBX_MEM_B + size_index);
                        end else if ((operation_index == 2) &&
                                     (size_index == 0) &&
                                     ((ea_mode == 0) || (ea_mode == 1))) begin
                            overlap_legal = 1'b1;
                            expected_overlap_id = M64K_INSN_ABCD;
                        end else if ((operation_index == 2) &&
                                     (size_index == 1) &&
                                     (ea_mode == 0)) begin
                            overlap_legal = 1'b1;
                            expected_overlap_id = M64K_INSN_EXG_DD;
                        end else if ((operation_index == 2) &&
                                     (size_index == 1) &&
                                     (ea_mode == 1)) begin
                            overlap_legal = 1'b1;
                            expected_overlap_id = M64K_INSN_EXG_AA;
                        end else if ((operation_index == 2) &&
                                     (size_index == 2) &&
                                     (ea_mode == 1)) begin
                            overlap_legal = 1'b1;
                            expected_overlap_id = M64K_INSN_EXG_DA;
                        end else if ((operation_index == 3) &&
                                     (size_index == 0) &&
                                     ((ea_mode == 0) || (ea_mode == 1))) begin
                            overlap_legal = 1'b1;
                            expected_overlap_id = M64K_INSN_SBCD;
                        end else if ((operation_index == 4) &&
                                     (ea_mode == 1)) begin
                            overlap_legal = 1'b1;
                            expected_overlap_id =
                                8'(M64K_INSN_CMPM_B + size_index);
                        end

                        test_opcode = {operation_nibble,
                            source_register[2:0], 1'b1,
                            size_index[1:0], ea_index[5:0]};
                        set_window(M64K_PROFILE_M00, 32'h0000_1200,
                                   COUNT_WIDTH'(1 + extension_words),
                                   test_opcode, 16'h0000, 16'h0000);
                        if (generic_legal) begin
                            generic_count = generic_count + 1;
                            assert (decode_valid && decode_uop.valid &&
                                    !decode_exception.valid);
                            assert (decode_uop.instruction_id ==
                                    8'(M64K_INSN_ADD_DN_EA_B +
                                       operation_index * 3 + size_index));
                            assert (decode_uop.memory_write ==
                                    (ea_mode != 0));
                        end else if (overlap_legal) begin
                            overlap_count = overlap_count + 1;
                            assert (decode_valid && decode_uop.valid &&
                                    !decode_exception.valid);
                            assert (decode_uop.instruction_id ==
                                    expected_overlap_id);
                        end else begin
                            illegal_count = illegal_count + 1;
                            assert (decode_valid && !decode_uop.valid &&
                                    decode_exception.valid);
                            assert (decode_exception.vector ==
                                    M64K_VECTOR_ILLEGAL);
                        end
                    end
                end
            end
            assert (generic_count ==
                    ((operation_index == 4) ? 1200 : 1008));
            case (operation_index)
                0, 1: assert (overlap_count == 384 &&
                              illegal_count == 144);
                2: assert (overlap_count == 320 &&
                           illegal_count == 208);
                3: assert (overlap_count == 128 &&
                           illegal_count == 400);
                default: assert (overlap_count == 192 &&
                                 illegal_count == 144);
            endcase
        end

        // M68000PRM 4-91..4-98 and 4-134..4-140: exhaust all four
        // 512-word M00 MUL/DIV planes.  Each destination register accepts
        // 53 data source EAs: Dn, modes 2..6, abs.w/abs.l, PC-relative,
        // PC-indexed and immediate.  An direct and mode 7/reg 5..7 are the
        // 88 illegal holes in each plane.
        for (int operation_index = 0; operation_index < 4;
             operation_index++) begin
            int legal_count;
            int illegal_count;
            logic [15:0] operation_base;
            logic [7:0] expected_id;
            legal_count = 0;
            illegal_count = 0;
            case (operation_index)
                0: begin
                    operation_base = 16'hc0c0;
                    expected_id = M64K_INSN_MULU;
                end
                1: begin
                    operation_base = 16'hc1c0;
                    expected_id = M64K_INSN_MULS;
                end
                2: begin
                    operation_base = 16'h80c0;
                    expected_id = M64K_INSN_DIVU;
                end
                default: begin
                    operation_base = 16'h81c0;
                    expected_id = M64K_INSN_DIVS;
                end
            endcase
            for (int destination_register = 0;
                 destination_register < 8; destination_register++) begin
                for (int ea_index = 0; ea_index < 64; ea_index++) begin
                    int ea_mode;
                    int ea_register;
                    int extension_words;
                    logic legal_source;
                    ea_mode = ea_index >> 3;
                    ea_register = ea_index & 7;
                    legal_source = (ea_mode == 0) ||
                        ((ea_mode >= 2) && (ea_mode <= 6)) ||
                        ((ea_mode == 7) && (ea_register <= 4));
                    extension_words =
                        ((ea_mode == 5) || (ea_mode == 6) ||
                         ((ea_mode == 7) &&
                          ((ea_register == 0) || (ea_register == 2) ||
                           (ea_register == 3) || (ea_register == 4)))) ? 1 :
                        (((ea_mode == 7) && (ea_register == 1)) ? 2 : 0);
                    test_opcode = operation_base |
                        16'(destination_register << 9) | 16'(ea_index);
                    set_window(M64K_PROFILE_M00, 32'h0000_1600,
                               COUNT_WIDTH'(1 + extension_words),
                               test_opcode, 16'h0002, 16'h0000);
                    if (legal_source) begin
                        legal_count = legal_count + 1;
                        assert (decode_valid && decode_uop.valid &&
                                !decode_exception.valid);
                        assert (decode_words == 1 + extension_words);
                        assert (decode_uop.instruction_id == expected_id);
                        assert (decode_uop.opcode ==
                            ((operation_index < 2) ? M64K_UOP_MULTIPLY :
                                                     M64K_UOP_DIVIDE));
                        assert (decode_uop.size == M64K_OP_WORD);
                        assert (decode_uop.condition[0] ==
                                operation_index[0]);
                        assert (decode_uop.destination.kind ==
                                M64K_OPERAND_DATA_REGISTER);
                        assert (decode_uop.destination.index[2:0] ==
                                destination_register[2:0]);
                        assert (!decode_uop.memory_write);
                        assert (decode_uop.flags_write ==
                                (M64K_FLAG_N | M64K_FLAG_Z |
                                 M64K_FLAG_V | M64K_FLAG_C));
                    end else begin
                        illegal_count = illegal_count + 1;
                        assert (decode_valid && !decode_uop.valid &&
                                decode_exception.valid);
                        assert (decode_exception.vector ==
                                M64K_VECTOR_ILLEGAL);
                    end
                end
            end
            assert (legal_count == 424);
            assert (illegal_count == 88);
        end

        $display("PASS: M64K generated M00 predecoder and profile branch lengths");
        $finish;
    end
endmodule
