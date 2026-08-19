module mx68k_predecoder #(
    parameter int unsigned WINDOW_WORDS = 16
) (
    input mx68k_arch_pkg::mx_profile_t profile,
    input logic window_valid,
    input logic [31:0] window_pc,
    input logic [$clog2(WINDOW_WORDS+1)-1:0] window_count,
    input logic [WINDOW_WORDS*16-1:0] window_words,
    input logic [WINDOW_WORDS*4-1:0] window_faults,

    output logic decode_valid,
    output logic decode_need_more,
    output logic [$clog2(WINDOW_WORDS+1)-1:0] decode_words,
    output mx68k_uop_pkg::mx_uop_t decode_uop,
    output mx68k_arch_pkg::mx_exception_t decode_exception
);
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;
    import mx68k_ea_pkg::*;
    import mx68k_uop_pkg::*;
    import mx68k_m00_decode_table_pkg::*;

    localparam int unsigned COUNT_WIDTH = $clog2(WINDOW_WORDS + 1);

    logic [15:0] opcode;
    logic [15:0] extension_word_1;
    logic [15:0] extension_word_2;
    logic [15:0] extension_word_3;
    mx_mem_fault_t opcode_fault;
    mx_mem_fault_t extension_fault_1;
    mx_mem_fault_t extension_fault_2;
    mx_mem_fault_t extension_fault_3;
    mx_decode_match_t match;
    logic signed [31:0] branch_displacement;
    logic [31:0] branch_target;
    mx_operand_size_t ea_size;
    mx_ea_t decoded_source_ea;
    mx_ea_t decoded_destination_ea;
    integer ea_source_words;
    integer ea_destination_words;
    integer ea_total_words;
    integer ea_fault_word;

    function automatic logic [15:0] get_window_word(input int unsigned index);
        return window_words[index*16 +: 16];
    endfunction

    function automatic mx_mem_fault_t get_window_fault(input int unsigned index);
        return mx_mem_fault_t'(window_faults[index*4 +: 4]);
    endfunction

    function automatic mx_ea_t decode_ea(
        input logic [2:0] mode,
        input logic [2:0] register_index,
        input int unsigned extension_index,
        input int unsigned extension_words,
        input logic [31:0] extension_pc
    );
        mx_ea_t value;
        begin
            value = '0;
            value.valid = 1'b1;
            value.kind = mx_ea_decode_kind(mode, register_index);
            value.register_index = register_index;
            if (extension_words >= 1)
                value.extension_0 = get_window_word(extension_index);
            if (extension_words >= 2)
                value.extension_1 = get_window_word(extension_index + 1);
            value.extension_pc = extension_pc;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_fetch_exception(
        input mx_mem_fault_t fault,
        input logic [31:0] fault_pc,
        input logic [31:0] instruction_pc,
        input logic [15:0] fault_opcode,
        input mx_profile_t fault_profile
    );
        mx_exception_t value;
        begin
            value = '0;
            value.valid = 1'b1;
            value.exception_class = MX_EXC_FETCH;
            value.stage = MX_FAULT_STAGE_FETCH;
            value.vector = (fault == MX_FAULT_ALIGNMENT) ?
                           MX_VECTOR_ADDRESS_ERROR : MX_VECTOR_ACCESS_FAULT;
            value.instruction_pc = instruction_pc;
            value.next_pc = fault_pc;
            value.logical_address = fault_pc;
            value.opcode = fault_opcode;
            value.operand_size = MX_OP_WORD;
            value.instruction = 1'b1;
            value.rerunnable = (fault_profile != MX_PROFILE_M00);
            return value;
        end
    endfunction

    function automatic mx_exception_t make_illegal_exception(
        input logic [31:0] instruction_pc,
        input logic [15:0] illegal_opcode
    );
        mx_exception_t value;
        begin
            value = '0;
            value.valid = 1'b1;
            value.exception_class = MX_EXC_DECODE;
            value.stage = MX_FAULT_STAGE_DECODE;
            value.vector = MX_VECTOR_ILLEGAL;
            value.instruction_pc = instruction_pc;
            value.next_pc = instruction_pc + 32'd2;
            value.opcode = illegal_opcode;
            value.operand_size = MX_OP_WORD;
            value.instruction = 1'b1;
            return value;
        end
    endfunction

    initial begin
        if (WINDOW_WORDS < 4)
            $fatal(1, "mx68k_predecoder WINDOW_WORDS must be at least four");
    end

    always_comb begin
        opcode = window_words[15:0];
        extension_word_1 = window_words[31:16];
        extension_word_2 = window_words[47:32];
        extension_word_3 = window_words[63:48];
        opcode_fault = mx_mem_fault_t'(window_faults[3:0]);
        extension_fault_1 = mx_mem_fault_t'(window_faults[7:4]);
        extension_fault_2 = mx_mem_fault_t'(window_faults[11:8]);
        extension_fault_3 = mx_mem_fault_t'(window_faults[15:12]);
        match = mx_lookup_m00_opcode(opcode);
        branch_displacement = '0;
        branch_target = '0;
        ea_size = MX_OP_WORD;
        decoded_source_ea = '0;
        decoded_destination_ea = '0;
        ea_source_words = 0;
        ea_destination_words = 0;
        ea_total_words = 0;
        ea_fault_word = 0;

        decode_valid = 1'b0;
        decode_need_more = 1'b0;
        decode_words = '0;
        decode_uop = '0;
        decode_exception = '0;

        if (window_valid) begin
            if (opcode_fault != MX_FAULT_NONE) begin
                decode_valid = 1'b1;
                decode_words = COUNT_WIDTH'(1);
                decode_exception = make_fetch_exception(
                    opcode_fault, window_pc, window_pc, opcode, profile);
            end else begin
                decode_valid = 1'b1;
                decode_words = COUNT_WIDTH'(1);
                decode_uop.valid = 1'b1;
                decode_uop.first = 1'b1;
                decode_uop.last = 1'b1;
                decode_uop.profile = profile;
                decode_uop.instruction_id = match.instruction_id;
                decode_uop.instruction_word = opcode;
                decode_uop.instruction_pc = window_pc;
                decode_uop.sequential_pc = window_pc + 32'd2;
                decode_uop.size = MX_OP_WORD;

                if (!match.matched) begin
                    decode_uop = '0;
                    decode_exception = make_illegal_exception(window_pc, opcode);
                end else begin
                    case (match.format)
                        MX_DECODE_NOP: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_NOP;
                        end
                        MX_DECODE_RESET: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_RESET;
                            decode_uop.privileged = 1'b1;
                            decode_uop.serializing = 1'b1;
                        end
                        MX_DECODE_STOP: begin
                            if (window_count < COUNT_WIDTH'(2)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (extension_fault_1 != MX_FAULT_NONE) begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    extension_fault_1, window_pc + 32'd2,
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                decode_uop.opcode = MX_UOP_STOP;
                                decode_uop.immediate = {16'd0, extension_word_1};
                                decode_uop.sequential_pc = window_pc + 32'd4;
                                decode_uop.privileged = 1'b1;
                                decode_uop.serializing = 1'b1;
                            end
                        end
                        MX_DECODE_RTE: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_EXCEPTION_RETURN;
                            decode_uop.privileged = 1'b1;
                            decode_uop.serializing = 1'b1;
                            decode_uop.may_fault = 1'b1;
                        end
                        MX_DECODE_RTS,
                        MX_DECODE_RTR: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_RETURN;
                            // RTR is not an RTS alias: it first restores the
                            // CCR word and then loads the PC at SP+2.
                            decode_uop.condition[0] =
                                (match.format == MX_DECODE_RTR);
                            decode_uop.serializing = 1'b1;
                            decode_uop.may_fault = 1'b1;
                        end
                        MX_DECODE_TRAPV: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_TRAP;
                            decode_uop.condition = 4'h9;
                            decode_uop.flags_read = MX_FLAG_V;
                            decode_uop.exception_vector = MX_VECTOR_TRAPCC;
                            decode_uop.serializing = 1'b1;
                        end
                        MX_DECODE_ILLEGAL: begin
                            decode_uop = '0;
                            decode_exception = make_illegal_exception(window_pc, opcode);
                        end
                        MX_DECODE_TRAP: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_TRAP;
                            decode_uop.exception_vector = MX_VECTOR_TRAP_BASE +
                                                          {4'd0, opcode[3:0]};
                            decode_uop.serializing = 1'b1;
                        end
                        MX_DECODE_MOVEQ: begin
                            decode_uop.uop_class = MX_UCLASS_REGISTER;
                            decode_uop.opcode = MX_UOP_MOVE;
                            decode_uop.size = MX_OP_LONG;
                            decode_uop.immediate = {{24{opcode[7]}}, opcode[7:0]};
                            decode_uop.source_a.kind = MX_OPERAND_IMMEDIATE;
                            decode_uop.destination.kind = MX_OPERAND_DATA_REGISTER;
                            decode_uop.destination.index = {3'd0, opcode[11:9]};
                            decode_uop.flags_write = MX_FLAG_N | MX_FLAG_Z |
                                                     MX_FLAG_V | MX_FLAG_C;
                        end
                        MX_DECODE_MOVE: begin
                            case (opcode[15:12])
                                4'h1: ea_size = MX_OP_BYTE;
                                4'h2: ea_size = MX_OP_LONG;
                                default: ea_size = MX_OP_WORD;
                            endcase
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_destination_words = mx_ea_extension_words(
                                opcode[8:6], opcode[11:9], ea_size);
                            ea_total_words = 1 + ea_source_words +
                                             ea_destination_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words,
                                window_pc + 32'd2);
                            decoded_destination_ea = decode_ea(
                                opcode[8:6], opcode[11:9],
                                1 + ea_source_words,
                                ea_destination_words,
                                window_pc + 32'(2 * (1 + ea_source_words)));
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;

                            if ((ea_source_words == 7) ||
                                (ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                ((ea_size == MX_OP_BYTE) &&
                                 ((decoded_source_ea.kind ==
                                   MX_EA_ADDRESS_REGISTER) ||
                                  (decoded_destination_ea.kind ==
                                   MX_EA_ADDRESS_REGISTER)))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_REGISTER;
                                decode_uop.opcode =
                                    (decoded_destination_ea.kind ==
                                     MX_EA_ADDRESS_REGISTER) ?
                                    MX_UOP_MOVE_ADDRESS : MX_UOP_MOVE;
                                decode_uop.size = ea_size;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea) ||
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        mx_ea_immediate_value(decoded_source_ea,
                                                              ea_size);
                                end
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                end else if (decoded_destination_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                end
                                if (decoded_destination_ea.kind inside {
                                    MX_EA_ABSOLUTE_WORD,
                                    MX_EA_ABSOLUTE_LONG})
                                    decode_uop.memory_address = mx_ea_address(
                                        decoded_destination_ea, ea_size,
                                        32'd0, 32'd0, 32'd0);
                                if (decode_uop.opcode == MX_UOP_MOVE)
                                    decode_uop.flags_write = MX_FLAG_N |
                                        MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                            end
                        end
                        MX_DECODE_ADD_EA_DN: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;

                            if ((ea_source_words == 7) ||
                                ((ea_size == MX_OP_BYTE) &&
                                 (decoded_source_ea.kind ==
                                  MX_EA_ADDRESS_REGISTER))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = MX_UOP_ADD;
                                decode_uop.size = ea_size;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index =
                                    {3'd0, opcode[11:9]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                decode_uop.flags_write = MX_FLAG_ALL;
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        mx_ea_immediate_value(decoded_source_ea,
                                                              ea_size);
                                end
                            end
                        end
                        MX_DECODE_BINARY_DN_EA: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER) ||
                                ((opcode[15:12] != 4'hb) &&
                                 !mx_ea_is_memory(decoded_destination_ea))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                case (opcode[15:12])
                                    4'h8: decode_uop.opcode = MX_UOP_OR;
                                    4'h9: decode_uop.opcode = MX_UOP_SUBTRACT;
                                    4'hb: decode_uop.opcode = MX_UOP_XOR;
                                    4'hc: decode_uop.opcode = MX_UOP_AND;
                                    default: decode_uop.opcode = MX_UOP_ADD;
                                endcase
                                decode_uop.size = ea_size;
                                decode_uop.source_a.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.source_a.index =
                                    {3'd0, opcode[11:9]};
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (decode_uop.opcode inside {
                                    MX_UOP_ADD, MX_UOP_SUBTRACT})
                                    decode_uop.flags_write =
                                        decode_uop.flags_write | MX_FLAG_X;
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index = {3'd0,
                                        decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_BINARY_EA_DN: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_source_words == 7) ||
                                // M68000PRM 4-14/4-16 and 4-149/4-151:
                                // AND/OR never accept An as an operand.
                                // SUB/CMP accept An only for word/long.
                                ((decoded_source_ea.kind ==
                                  MX_EA_ADDRESS_REGISTER) &&
                                 (((opcode[15:12] == 4'h8) ||
                                   (opcode[15:12] == 4'hc)) ||
                                  (ea_size == MX_OP_BYTE)))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                case (opcode[15:12])
                                    4'h8: decode_uop.opcode = MX_UOP_OR;
                                    4'h9: decode_uop.opcode = MX_UOP_SUBTRACT;
                                    4'hb: decode_uop.opcode = MX_UOP_COMPARE;
                                    default: decode_uop.opcode = MX_UOP_AND;
                                endcase
                                decode_uop.size = ea_size;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index =
                                    {3'd0, opcode[11:9]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (decode_uop.opcode != MX_UOP_COMPARE)
                                    decode_uop.flags_write =
                                        decode_uop.flags_write |
                                        ((decode_uop.opcode == MX_UOP_SUBTRACT) ?
                                         MX_FLAG_X : 5'd0);
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    // The instruction tables explicitly
                                    // permit #<data> as a source even though
                                    // assemblers normally select xI forms.
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        mx_ea_immediate_value(
                                            decoded_source_ea, ea_size);
                                end
                            end
                        end
                        MX_DECODE_CMPA: begin
                            ea_size = opcode[8] ? MX_OP_LONG : MX_OP_WORD;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if (ea_source_words == 7) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = MX_UOP_COMPARE;
                                decode_uop.size = ea_size;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind =
                                    MX_OPERAND_ADDRESS_REGISTER;
                                decode_uop.destination.index = {3'd0,
                                                                opcode[11:9]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_ADDRESS_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        (ea_size == MX_OP_WORD) ?
                                        {{16{decoded_source_ea.extension_0[15]}},
                                          decoded_source_ea.extension_0} :
                                        mx_ea_immediate_value(
                                            decoded_source_ea, ea_size);
                                end
                            end
                        end
                        MX_DECODE_MOVE_TO_CCR,
                        MX_DECODE_MOVE_TO_SR: begin
                            ea_size = MX_OP_WORD;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_source_words == 7) ||
                                (decoded_source_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                decode_uop.opcode = MX_UOP_MOVE;
                                decode_uop.size = MX_OP_WORD;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind = MX_OPERAND_SR;
                                // condition[0] selects the low CCR-only merge;
                                // a clear bit replaces the complete SR word.
                                decode_uop.condition[0] =
                                    match.format ==
                                    MX_DECODE_MOVE_TO_CCR;
                                decode_uop.privileged =
                                    match.format ==
                                    MX_DECODE_MOVE_TO_SR;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate = {16'd0,
                                        decoded_source_ea.extension_0};
                                end
                            end
                        end
                        MX_DECODE_MOVE_FROM_SR: begin
                            ea_size = MX_OP_WORD;
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                decode_uop.opcode = MX_UOP_MOVE;
                                decode_uop.size = MX_OP_WORD;
                                decode_uop.source_a.kind = MX_OPERAND_SR;
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index = {3'd0,
                                        decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_MOVE_USP: begin
                            // M68000 PRM 6-20/6-21: bit 3 selects the
                            // direction (0: An -> USP, 1: USP -> An).  Both
                            // forms are privileged long transfers and leave
                            // the condition codes unchanged.
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_MOVE;
                            decode_uop.size = MX_OP_LONG;
                            decode_uop.privileged = 1'b1;
                            if (opcode[3]) begin
                                decode_uop.source_a.kind = MX_OPERAND_USP;
                                decode_uop.destination.kind =
                                    MX_OPERAND_ADDRESS_REGISTER;
                                decode_uop.destination.index =
                                    {3'd0, opcode[2:0]};
                            end else begin
                                decode_uop.source_a.kind =
                                    MX_OPERAND_ADDRESS_REGISTER;
                                decode_uop.source_a.index =
                                    {3'd0, opcode[2:0]};
                                decode_uop.destination.kind = MX_OPERAND_USP;
                            end
                        end
                        MX_DECODE_SCC: begin
                            ea_size = MX_OP_BYTE;
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = MX_UOP_SET_CONDITION;
                                decode_uop.size = MX_OP_BYTE;
                                decode_uop.condition = opcode[11:8];
                                // Scc consumes the current condition-code
                                // state even though it never modifies it.
                                // Keep this dependency explicit for future
                                // scoreboarding/renaming implementations.
                                decode_uop.flags_read = MX_FLAG_N | MX_FLAG_Z |
                                                        MX_FLAG_V | MX_FLAG_C;
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index = {3'd0,
                                        decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_TAS: begin
                            // M68000 PRM 4-186/4-187: TAS tests the original
                            // byte, then sets bit 7.  Memory destinations are
                            // one indivisible read-modify-write transaction.
                            ea_size = MX_OP_BYTE;
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = MX_UOP_ATOMIC;
                                decode_uop.size = MX_OP_BYTE;
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_atomic =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_ordered =
                                    mx_ea_is_memory(decoded_destination_ea);
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index = {3'd0,
                                        decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_EXT: begin
                            decode_uop.uop_class = MX_UCLASS_ALU;
                            decode_uop.opcode = MX_UOP_SIGN_EXTEND;
                            decode_uop.size = opcode[6] ? MX_OP_LONG : MX_OP_WORD;
                            decode_uop.condition[0] = opcode[6];
                            decode_uop.destination.kind =
                                MX_OPERAND_DATA_REGISTER;
                            decode_uop.destination.index = {3'd0, opcode[2:0]};
                            decode_uop.destination_ea.valid = 1'b1;
                            decode_uop.destination_ea.kind =
                                MX_EA_DATA_REGISTER;
                            decode_uop.destination_ea.register_index =
                                opcode[2:0];
                            decode_uop.flags_write = MX_FLAG_N | MX_FLAG_Z |
                                                     MX_FLAG_V | MX_FLAG_C;
                        end
                        MX_DECODE_EXG: begin
                            // M68000 PRM 4-104/4-105: EXG is a one-word,
                            // long-word register exchange.  Bits 7:3 select
                            // Dn/Dn, An/An, or Dn/An; no condition-code bit
                            // is affected.
                            decode_uop.uop_class = MX_UCLASS_REGISTER;
                            decode_uop.opcode = MX_UOP_EXCHANGE;
                            decode_uop.size = MX_OP_LONG;
                            case (opcode[7:3])
                                5'b01000: begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_ea.kind =
                                        MX_EA_DATA_REGISTER;
                                    decode_uop.destination_ea.kind =
                                        MX_EA_DATA_REGISTER;
                                end
                                5'b01001: begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.destination.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_ea.kind =
                                        MX_EA_ADDRESS_REGISTER;
                                    decode_uop.destination_ea.kind =
                                        MX_EA_ADDRESS_REGISTER;
                                end
                                default: begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_ea.kind =
                                        MX_EA_ADDRESS_REGISTER;
                                    decode_uop.destination_ea.kind =
                                        MX_EA_DATA_REGISTER;
                                end
                            endcase
                            decode_uop.source_a.index = {3'd0, opcode[2:0]};
                            decode_uop.destination.index =
                                {3'd0, opcode[11:9]};
                            decode_uop.source_ea.valid = 1'b1;
                            decode_uop.source_ea.register_index = opcode[2:0];
                            decode_uop.destination_ea.valid = 1'b1;
                            decode_uop.destination_ea.register_index =
                                opcode[11:9];
                        end
                        MX_DECODE_BIT_DYNAMIC,
                        MX_DECODE_BIT_IMMEDIATE: begin
                            ea_size = (opcode[5:3] == 3'd0) ? MX_OP_LONG :
                                                                   MX_OP_BYTE;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words =
                                ((match.format == MX_DECODE_BIT_DYNAMIC) ?
                                 1 : 2) + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0],
                                (match.format == MX_DECODE_BIT_DYNAMIC) ? 1 : 2,
                                ea_source_words, window_pc +
                                ((match.format == MX_DECODE_BIT_DYNAMIC) ?
                                 32'd2 : 32'd4));
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_source_words == 7) ||
                                (decoded_source_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER) ||
                                ((decoded_source_ea.kind == MX_EA_IMMEDIATE) &&
                                 !((match.format == MX_DECODE_BIT_DYNAMIC) &&
                                   (opcode[7:6] == 2'b00))) ||
                                ((opcode[7:6] != 2'b00) &&
                                 !mx_ea_is_alterable(decoded_source_ea))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = MX_UOP_BIT_TEST;
                                decode_uop.size = ea_size;
                                decode_uop.destination_ea = decoded_source_ea;
                                decode_uop.condition[1:0] = opcode[7:6];
                                decode_uop.condition[2] =
                                    match.format == MX_DECODE_BIT_DYNAMIC;
                                if (match.format == MX_DECODE_BIT_DYNAMIC) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index =
                                        {3'd0, opcode[11:9]};
                                end else begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate = {16'd0,
                                                            extension_word_1};
                                end
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                decode_uop.flags_write = MX_FLAG_Z;
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if
                                    (decoded_source_ea.kind ==
                                     MX_EA_IMMEDIATE) begin
                                    // Dynamic BTST is the sole bit operation
                                    // whose data-addressing destination may be
                                    // immediate (M68000PRM 4-61).  Its bit
                                    // number still comes from source_a/Dn.
                                    decode_uop.destination.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        mx_ea_immediate_value(
                                            decoded_source_ea, ea_size);
                                end
                            end
                        end
                        MX_DECODE_MUL,
                        MX_DECODE_DIV: begin
                            ea_size = MX_OP_WORD;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            // M68000PRM MULS/MULU/DIVS/DIVU word-form EA
                            // tables allow data-register, memory,
                            // PC-relative and immediate sources, but mark An
                            // direct as illegal.
                            if ((ea_source_words == 7) ||
                                (decoded_source_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_MULDIV;
                                decode_uop.opcode =
                                    (match.format == MX_DECODE_DIV) ?
                                    MX_UOP_DIVIDE : MX_UOP_MULTIPLY;
                                decode_uop.size = MX_OP_WORD;
                                decode_uop.condition[0] = opcode[8];
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index = {3'd0,
                                                                opcode[11:9]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate = {16'd0,
                                        decoded_source_ea.extension_0};
                                end
                            end
                        end
                        MX_DECODE_CHK: begin
                            ea_size = MX_OP_WORD;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;

                            if ((ea_source_words == 7) ||
                                (decoded_source_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                decode_uop.opcode = MX_UOP_CHECK_BOUNDS;
                                decode_uop.size = MX_OP_WORD;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index = {3'd0,
                                                                opcode[11:9]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                decode_uop.flags_write = MX_FLAG_N;
                                decode_uop.exception_vector = MX_VECTOR_CHK;
                                decode_uop.serializing = 1'b1;
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate = {16'd0,
                                        decoded_source_ea.extension_0};
                                end
                            end
                        end
                        MX_DECODE_ADDSUB_ADDRESS: begin
                            ea_size = opcode[8] ? MX_OP_LONG : MX_OP_WORD;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if (ea_source_words == 7) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = (opcode[15:12] == 4'hd) ?
                                    MX_UOP_ADD : MX_UOP_SUBTRACT;
                                decode_uop.size = ea_size;
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination.kind =
                                    MX_OPERAND_ADDRESS_REGISTER;
                                decode_uop.destination.index = {3'd0,
                                                                opcode[11:9]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_ADDRESS_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea);
                                if (decoded_source_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                        decoded_source_ea.register_index};
                                end else if (decoded_source_ea.kind ==
                                             MX_EA_IMMEDIATE) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        mx_ea_immediate_value(
                                            decoded_source_ea, ea_size);
                                end
                            end
                        end
                        MX_DECODE_CMP_IMMEDIATE: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            ea_source_words = (ea_size == MX_OP_LONG) ? 2 : 1;
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words +
                                             ea_destination_words;
                            decoded_source_ea = decode_ea(
                                3'd7, 3'd4, 1, ea_source_words,
                                window_pc + 32'd2);
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0],
                                1 + ea_source_words, ea_destination_words,
                                window_pc + 32'(2 * (1 + ea_source_words)));
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((opcode[7:6] == 2'b11) ||
                                (ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = MX_UOP_COMPARE;
                                decode_uop.size = ea_size;
                                decode_uop.source_a.kind =
                                    MX_OPERAND_IMMEDIATE;
                                decode_uop.immediate =
                                    mx_ea_immediate_value(decoded_source_ea,
                                                          ea_size);
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_LOGICAL_IMMEDIATE,
                        MX_DECODE_ADDSUB_IMMEDIATE: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            ea_source_words = (ea_size == MX_OP_LONG) ? 2 : 1;
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words +
                                             ea_destination_words;
                            decoded_source_ea = decode_ea(
                                3'd7, 3'd4, 1, ea_source_words,
                                window_pc + 32'd2);
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0],
                                1 + ea_source_words, ea_destination_words,
                                window_pc + 32'(2 * (1 + ea_source_words)));
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((opcode[7:6] == 2'b11) ||
                                (ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                if (match.format ==
                                    MX_DECODE_ADDSUB_IMMEDIATE)
                                    decode_uop.opcode = (opcode[11:8] == 4'h6) ?
                                        MX_UOP_ADD : MX_UOP_SUBTRACT;
                                else begin
                                    case (opcode[11:8])
                                        4'h0: decode_uop.opcode = MX_UOP_OR;
                                        4'h2: decode_uop.opcode = MX_UOP_AND;
                                        default: decode_uop.opcode = MX_UOP_XOR;
                                    endcase
                                end
                                decode_uop.size = ea_size;
                                decode_uop.source_a.kind =
                                    MX_OPERAND_IMMEDIATE;
                                decode_uop.immediate =
                                    mx_ea_immediate_value(decoded_source_ea,
                                                          ea_size);
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (match.format ==
                                    MX_DECODE_ADDSUB_IMMEDIATE)
                                    decode_uop.flags_write =
                                        decode_uop.flags_write | MX_FLAG_X;
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_ADDQ_SUBQ: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;

                            if ((opcode[7:6] == 2'b11) ||
                                (ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                ((ea_size == MX_OP_BYTE) &&
                                 (decoded_destination_ea.kind ==
                                  MX_EA_ADDRESS_REGISTER))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                decode_uop.opcode = opcode[8] ?
                                    MX_UOP_SUBTRACT : MX_UOP_ADD;
                                decode_uop.size = ea_size;
                                decode_uop.source_a.kind =
                                    MX_OPERAND_IMMEDIATE;
                                decode_uop.immediate = (opcode[11:9] == 3'd0) ?
                                                       32'd8 :
                                                       {29'd0, opcode[11:9]};
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                    decode_uop.flags_write = MX_FLAG_ALL;
                                end else if (decoded_destination_ea.kind ==
                                             MX_EA_ADDRESS_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                end else begin
                                    decode_uop.flags_write = MX_FLAG_ALL;
                                end
                            end
                        end
                        MX_DECODE_ADDX_SUBX_REGISTER: begin
                            decode_words = COUNT_WIDTH'(1);
                            decode_uop.uop_class = MX_UCLASS_ALU;
                            decode_uop.opcode = (opcode[15:12] == 4'hd) ?
                                MX_UOP_ADD_EXTEND : MX_UOP_SUBTRACT_EXTEND;
                            case (opcode[7:6])
                                2'b00: decode_uop.size = MX_OP_BYTE;
                                2'b01: decode_uop.size = MX_OP_WORD;
                                default: decode_uop.size = MX_OP_LONG;
                            endcase
                            decode_uop.source_a.kind =
                                MX_OPERAND_DATA_REGISTER;
                            decode_uop.source_a.index = {3'd0, opcode[2:0]};
                            decode_uop.source_ea.kind = MX_EA_DATA_REGISTER;
                            decode_uop.source_ea.register_index = opcode[2:0];
                            decode_uop.destination.kind =
                                MX_OPERAND_DATA_REGISTER;
                            decode_uop.destination.index =
                                {3'd0, opcode[11:9]};
                            decode_uop.destination_ea.kind =
                                MX_EA_DATA_REGISTER;
                            decode_uop.destination_ea.register_index =
                                opcode[11:9];
                            // Distinguishes binary SUBX from unary NEGX in
                            // the shared subtract-with-extend execution path.
                            decode_uop.condition[0] =
                                (opcode[15:12] == 4'h9);
                            decode_uop.flags_read = MX_FLAG_X | MX_FLAG_Z;
                            decode_uop.flags_write = MX_FLAG_ALL;
                            decode_uop.sequential_pc = window_pc + 32'd2;
                        end
                        MX_DECODE_ADDX_SUBX_MEMORY: begin
                            // M68000PRM 4-13/4-14 and 4-183/4-184 define
                            // R/M=1 as two independently predecremented address
                            // registers: read -(Ay), read/modify/write -(Ax).
                            decode_words = COUNT_WIDTH'(1);
                            decode_uop.uop_class = MX_UCLASS_ALU;
                            decode_uop.opcode = (opcode[15:12] == 4'hd) ?
                                MX_UOP_ADD_EXTEND : MX_UOP_SUBTRACT_EXTEND;
                            case (opcode[7:6])
                                2'b00: decode_uop.size = MX_OP_BYTE;
                                2'b01: decode_uop.size = MX_OP_WORD;
                                default: decode_uop.size = MX_OP_LONG;
                            endcase
                            decode_uop.source_ea.valid = 1'b1;
                            decode_uop.source_ea.kind = MX_EA_PREDECREMENT;
                            decode_uop.source_ea.register_index = opcode[2:0];
                            decode_uop.destination_ea.valid = 1'b1;
                            decode_uop.destination_ea.kind =
                                MX_EA_PREDECREMENT;
                            decode_uop.destination_ea.register_index =
                                opcode[11:9];
                            decode_uop.condition[0] =
                                (opcode[15:12] == 4'h9);
                            decode_uop.flags_read = MX_FLAG_X | MX_FLAG_Z;
                            decode_uop.flags_write = MX_FLAG_ALL;
                            decode_uop.may_fault = 1'b1;
                            decode_uop.memory_write = 1'b1;
                            decode_uop.sequential_pc = window_pc + 32'd2;
                        end
                        MX_DECODE_CMPM: begin
                            // M68000PRM 4-80/4-81: source (Ay)+ is read
                            // before destination (Ax)+.  The backend sequence
                            // preserves that order and applies the two
                            // postincrements at explicit fault checkpoints.
                            decode_words = COUNT_WIDTH'(1);
                            decode_uop.uop_class = MX_UCLASS_ALU;
                            decode_uop.opcode = MX_UOP_COMPARE_MEMORY;
                            case (opcode[7:6])
                                2'b00: decode_uop.size = MX_OP_BYTE;
                                2'b01: decode_uop.size = MX_OP_WORD;
                                default: decode_uop.size = MX_OP_LONG;
                            endcase
                            decode_uop.source_ea.valid = 1'b1;
                            decode_uop.source_ea.kind = MX_EA_POSTINCREMENT;
                            decode_uop.source_ea.register_index = opcode[2:0];
                            decode_uop.destination_ea.valid = 1'b1;
                            decode_uop.destination_ea.kind =
                                MX_EA_POSTINCREMENT;
                            decode_uop.destination_ea.register_index =
                                opcode[11:9];
                            decode_uop.flags_write = MX_FLAG_N | MX_FLAG_Z |
                                                     MX_FLAG_V | MX_FLAG_C;
                            decode_uop.may_fault = 1'b1;
                            decode_uop.memory_ordered = 1'b1;
                            decode_uop.sequential_pc = window_pc + 32'd2;
                        end
                        MX_DECODE_ABCD_SBCD: begin
                            // M68000PRM 4-1/4-2 and 4-169/4-170: packed-BCD
                            // byte operation, with bit 3 selecting Dn,Dn or
                            // the two independently predecremented operands.
                            decode_words = COUNT_WIDTH'(1);
                            decode_uop.uop_class = MX_UCLASS_ALU;
                            decode_uop.opcode = (opcode[15:12] == 4'hc) ?
                                MX_UOP_ADD_EXTEND : MX_UOP_SUBTRACT_EXTEND;
                            decode_uop.size = MX_OP_BYTE;
                            decode_uop.condition[0] =
                                (opcode[15:12] == 4'h8);
                            decode_uop.condition[1] = 1'b1;
                            if (!opcode[3]) begin
                                decode_uop.source_a.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.source_a.index =
                                    {3'd0, opcode[2:0]};
                                decode_uop.source_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.source_ea.register_index =
                                    opcode[2:0];
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index =
                                    {3'd0, opcode[11:9]};
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                            end else begin
                                decode_uop.source_ea.valid = 1'b1;
                                decode_uop.source_ea.kind =
                                    MX_EA_PREDECREMENT;
                                decode_uop.source_ea.register_index =
                                    opcode[2:0];
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_PREDECREMENT;
                                decode_uop.destination_ea.register_index =
                                    opcode[11:9];
                                decode_uop.may_fault = 1'b1;
                                decode_uop.memory_write = 1'b1;
                            end
                            decode_uop.flags_read = MX_FLAG_X | MX_FLAG_Z;
                            // N and V are undefined for ABCD/SBCD. Preserve
                            // them deterministically instead of claiming a
                            // value not specified by the architecture.
                            decode_uop.flags_write =
                                MX_FLAG_X | MX_FLAG_Z | MX_FLAG_C;
                            decode_uop.sequential_pc = window_pc + 32'd2;
                        end
                        MX_DECODE_NOT,
                        MX_DECODE_NEG,
                        MX_DECODE_NEGX,
                        MX_DECODE_NBCD: begin
                            if (match.format == MX_DECODE_NBCD)
                                ea_size = MX_OP_BYTE;
                            else begin
                                case (opcode[7:6])
                                    2'b00: ea_size = MX_OP_BYTE;
                                    2'b01: ea_size = MX_OP_WORD;
                                    default: ea_size = MX_OP_LONG;
                                endcase
                            end
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((opcode[7:6] == 2'b11) ||
                                (ea_destination_words == 7) ||
                                !mx_ea_is_alterable(decoded_destination_ea) ||
                                (decoded_destination_ea.kind ==
                                 MX_EA_ADDRESS_REGISTER)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                if (match.format == MX_DECODE_NEG)
                                    decode_uop.opcode = MX_UOP_NEGATE;
                                else if (match.format inside {
                                         MX_DECODE_NEGX, MX_DECODE_NBCD})
                                    decode_uop.opcode =
                                        MX_UOP_SUBTRACT_EXTEND;
                                else
                                    decode_uop.opcode = MX_UOP_NOT;
                                decode_uop.size = ea_size;
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.memory_write =
                                    mx_ea_is_memory(decoded_destination_ea);
                                decode_uop.flags_write = MX_FLAG_N |
                                    MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                if (match.format == MX_DECODE_NBCD) begin
                                    decode_uop.condition[1] = 1'b1;
                                    decode_uop.flags_read = MX_FLAG_X |
                                                                  MX_FLAG_Z;
                                    decode_uop.flags_write = MX_FLAG_X |
                                                          MX_FLAG_Z |
                                                          MX_FLAG_C;
                                end else if (match.format inside {
                                    MX_DECODE_NEG, MX_DECODE_NEGX})
                                    decode_uop.flags_write =
                                        decode_uop.flags_write | MX_FLAG_X;
                                if (decoded_destination_ea.kind ==
                                    MX_EA_DATA_REGISTER) begin
                                    decode_uop.destination.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0,
                                         decoded_destination_ea.register_index};
                                end
                            end
                        end
                        MX_DECODE_SWAP: begin
                            decode_uop.uop_class = MX_UCLASS_REGISTER;
                            decode_uop.opcode = MX_UOP_SWAP;
                            decode_uop.size = MX_OP_LONG;
                            decode_uop.destination.kind =
                                MX_OPERAND_DATA_REGISTER;
                            decode_uop.destination.index = {3'd0, opcode[2:0]};
                            decode_uop.destination_ea.valid = 1'b1;
                            decode_uop.destination_ea.kind =
                                MX_EA_DATA_REGISTER;
                            decode_uop.destination_ea.register_index =
                                opcode[2:0];
                            decode_uop.flags_write = MX_FLAG_N | MX_FLAG_Z |
                                                     MX_FLAG_V | MX_FLAG_C;
                        end
                        MX_DECODE_MOVEM: begin
                            ea_size = opcode[6] ? MX_OP_LONG : MX_OP_WORD;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 2 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 2,
                                ea_source_words, window_pc + 32'd4);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_source_words == 7) ||
                                !mx_ea_is_memory(decoded_source_ea) ||
                                // PRM 4-128/4-129: register-to-memory
                                // permits control-alterable or predecrement,
                                // never a PC-relative destination.
                                (!opcode[10] &&
                                 !mx_ea_is_alterable(decoded_source_ea)) ||
                                (!opcode[10] &&
                                 (decoded_source_ea.kind ==
                                  MX_EA_POSTINCREMENT)) ||
                                (opcode[10] &&
                                 (decoded_source_ea.kind ==
                                  MX_EA_PREDECREMENT))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = opcode[10] ?
                                    MX_UCLASS_LOAD : MX_UCLASS_STORE;
                                decode_uop.opcode = MX_UOP_MOVE_MULTIPLE;
                                decode_uop.size = ea_size;
                                decode_uop.immediate = {16'd0,
                                                        extension_word_1};
                                decode_uop.condition[0] = opcode[10];
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.may_fault = 1'b1;
                                decode_uop.memory_write = !opcode[10];
                            end
                        end
                        MX_DECODE_LINK: begin
                            if (window_count < COUNT_WIDTH'(2)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (extension_fault_1 != MX_FAULT_NONE) begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    extension_fault_1, window_pc + 32'd2,
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                decode_uop.opcode = MX_UOP_LINK;
                                decode_uop.size = MX_OP_LONG;
                                decode_uop.source_a.kind =
                                    MX_OPERAND_ADDRESS_REGISTER;
                                decode_uop.source_a.index = {3'd0, opcode[2:0]};
                                decode_uop.source_ea.valid = 1'b1;
                                decode_uop.source_ea.kind =
                                    MX_EA_ADDRESS_REGISTER;
                                decode_uop.source_ea.register_index =
                                    opcode[2:0];
                                decode_uop.immediate =
                                    {{16{extension_word_1[15]}},
                                      extension_word_1};
                                decode_uop.sequential_pc = window_pc + 32'd4;
                                decode_uop.may_fault = 1'b1;
                                decode_uop.memory_write = 1'b1;
                                decode_uop.serializing = 1'b1;
                            end
                        end
                        MX_DECODE_UNLINK: begin
                            decode_uop.uop_class = MX_UCLASS_SYSTEM;
                            decode_uop.opcode = MX_UOP_UNLINK;
                            decode_uop.size = MX_OP_LONG;
                            decode_uop.source_a.kind =
                                MX_OPERAND_ADDRESS_REGISTER;
                            decode_uop.source_a.index = {3'd0, opcode[2:0]};
                            decode_uop.source_ea.valid = 1'b1;
                            decode_uop.source_ea.kind = MX_EA_ADDRESS_REGISTER;
                            decode_uop.source_ea.register_index = opcode[2:0];
                            decode_uop.may_fault = 1'b1;
                            decode_uop.serializing = 1'b1;
                        end
                        MX_DECODE_CLR,
                        MX_DECODE_TEST,
                        MX_DECODE_JSR,
                        MX_DECODE_LEA,
                        MX_DECODE_PEA,
                        MX_DECODE_JMP: begin
                            case (opcode[7:6])
                                2'b00: ea_size = MX_OP_BYTE;
                                2'b01: ea_size = MX_OP_WORD;
                                default: ea_size = MX_OP_LONG;
                            endcase
                            if (match.format inside {
                                MX_DECODE_JSR, MX_DECODE_LEA, MX_DECODE_PEA,
                                MX_DECODE_JMP})
                                ea_size = MX_OP_LONG;
                            ea_source_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_source_words;
                            decoded_source_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_source_words,
                                window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;

                            if ((ea_source_words == 7) ||
                                ((match.format inside {
                                  MX_DECODE_JSR, MX_DECODE_LEA,
                                  MX_DECODE_PEA, MX_DECODE_JMP}) &&
                                 !mx_ea_is_control(decoded_source_ea)) ||
                                (!(match.format inside {
                                  MX_DECODE_JSR, MX_DECODE_LEA,
                                  MX_DECODE_PEA, MX_DECODE_JMP}) &&
                                 (!mx_ea_is_alterable(decoded_source_ea) ||
                                  (decoded_source_ea.kind ==
                                   MX_EA_ADDRESS_REGISTER))) ||
                                (!(match.format inside {
                                  MX_DECODE_JSR, MX_DECODE_LEA,
                                  MX_DECODE_PEA, MX_DECODE_JMP}) &&
                                 (opcode[7:6] == 2'b11))) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.size = ea_size;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.source_ea = decoded_source_ea;
                                decode_uop.destination_ea = decoded_source_ea;
                                decode_uop.may_fault =
                                    mx_ea_is_memory(decoded_source_ea) ||
                                    (match.format inside {
                                     MX_DECODE_JSR, MX_DECODE_PEA});
                                if (match.format == MX_DECODE_CLR) begin
                                    decode_uop.uop_class = MX_UCLASS_ALU;
                                    decode_uop.opcode = MX_UOP_CLEAR;
                                    decode_uop.destination_ea =
                                        decoded_source_ea;
                                    if (decoded_source_ea.kind ==
                                        MX_EA_DATA_REGISTER) begin
                                        decode_uop.destination.kind =
                                            MX_OPERAND_DATA_REGISTER;
                                        decode_uop.destination.index =
                                            {3'd0, opcode[2:0]};
                                    end
                                    decode_uop.flags_write = MX_FLAG_N |
                                        MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                    decode_uop.memory_write =
                                        mx_ea_is_memory(decoded_source_ea);
                                end else if (match.format == MX_DECODE_TEST) begin
                                    decode_uop.uop_class = MX_UCLASS_ALU;
                                    decode_uop.opcode = MX_UOP_TEST;
                                    decode_uop.flags_write = MX_FLAG_N |
                                        MX_FLAG_Z | MX_FLAG_V | MX_FLAG_C;
                                end else if (match.format == MX_DECODE_LEA) begin
                                    decode_uop.uop_class = MX_UCLASS_EA;
                                    decode_uop.opcode = MX_UOP_CALCULATE_EA;
                                    decode_uop.destination.kind =
                                        MX_OPERAND_ADDRESS_REGISTER;
                                    decode_uop.destination.index =
                                        {3'd0, opcode[11:9]};
                                    decode_uop.may_fault = 1'b0;
                                end else if (match.format == MX_DECODE_PEA) begin
                                    decode_uop.uop_class = MX_UCLASS_STORE;
                                    decode_uop.opcode =
                                        MX_UOP_PUSH_EFFECTIVE_ADDRESS;
                                    decode_uop.memory_write = 1'b1;
                                end else if (match.format == MX_DECODE_JMP) begin
                                    decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                    decode_uop.opcode = MX_UOP_JUMP;
                                    decode_uop.serializing = 1'b1;
                                    decode_uop.may_fault = 1'b0;
                                end else begin
                                    decode_uop.uop_class = MX_UCLASS_SYSTEM;
                                    decode_uop.opcode = MX_UOP_JUMP_SUBROUTINE;
                                    decode_uop.serializing = 1'b1;
                                end
                            end
                        end
                        MX_DECODE_LOGICAL_IMMEDIATE_SR: begin
                            if (window_count < COUNT_WIDTH'(2)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (extension_fault_1 != MX_FAULT_NONE) begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    extension_fault_1, window_pc + 32'd2,
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop.uop_class = MX_UCLASS_ALU;
                                case (opcode[11:8])
                                    4'h0: decode_uop.opcode = MX_UOP_OR;
                                    4'h2: decode_uop.opcode = MX_UOP_AND;
                                    default: decode_uop.opcode = MX_UOP_XOR;
                                endcase
                                // M68000PRM 4-19, 4-103 and 4-154: the
                                // xxI-to-CCR forms are byte operations on the
                                // low SR byte and are not privileged.  The
                                // corresponding SR forms operate on a word
                                // and require supervisor state.
                                decode_uop.condition[0] =
                                    !opcode[6];
                                decode_uop.size = decode_uop.condition[0] ?
                                    MX_OP_BYTE : MX_OP_WORD;
                                decode_uop.source_a.kind = MX_OPERAND_SR;
                                decode_uop.source_b.kind = MX_OPERAND_IMMEDIATE;
                                decode_uop.destination.kind = MX_OPERAND_SR;
                                decode_uop.immediate = {16'd0, extension_word_1};
                                decode_uop.sequential_pc = window_pc + 32'd4;
                                decode_uop.privileged =
                                    !decode_uop.condition[0];
                                decode_uop.serializing = 1'b1;
                            end
                        end
                        MX_DECODE_DBCC: begin
                            if (window_count < COUNT_WIDTH'(2)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (extension_fault_1 != MX_FAULT_NONE) begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    extension_fault_1, window_pc + 32'd2,
                                    window_pc, opcode, profile);
                            end else begin
                                decode_words = COUNT_WIDTH'(2);
                                decode_uop.uop_class = MX_UCLASS_BRANCH;
                                decode_uop.opcode = MX_UOP_DBCC;
                                decode_uop.size = MX_OP_WORD;
                                decode_uop.condition = opcode[11:8];
                                decode_uop.flags_read = MX_FLAG_N | MX_FLAG_Z |
                                                        MX_FLAG_V | MX_FLAG_C;
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index = {3'd0,
                                                                opcode[2:0]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[2:0];
                                decode_uop.immediate = window_pc + 32'd2 +
                                    {{16{extension_word_1[15]}},
                                      extension_word_1};
                                decode_uop.sequential_pc = window_pc + 32'd4;
                                decode_uop.serializing = 1'b1;
                            end
                        end
                        MX_DECODE_SHIFT_MEMORY: begin
                            ea_size = MX_OP_WORD;
                            ea_destination_words = mx_ea_extension_words(
                                opcode[5:3], opcode[2:0], ea_size);
                            ea_total_words = 1 + ea_destination_words;
                            decoded_destination_ea = decode_ea(
                                opcode[5:3], opcode[2:0], 1,
                                ea_destination_words, window_pc + 32'd2);
                            for (int extension_index = 1;
                                 extension_index < ea_total_words;
                                 extension_index = extension_index + 1)
                                if ((ea_fault_word == 0) &&
                                    (get_window_fault(extension_index) !=
                                     MX_FAULT_NONE))
                                    ea_fault_word = extension_index;
                            if ((ea_destination_words == 7) ||
                                !mx_ea_is_memory(decoded_destination_ea) ||
                                !mx_ea_is_alterable(decoded_destination_ea)) begin
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else if (window_count <
                                         COUNT_WIDTH'(ea_total_words)) begin
                                decode_valid = 1'b0;
                                decode_need_more = 1'b1;
                                decode_words = '0;
                                decode_uop = '0;
                            end else if (ea_fault_word != 0) begin
                                decode_words = COUNT_WIDTH'(ea_fault_word + 1);
                                decode_uop = '0;
                                decode_exception = make_fetch_exception(
                                    get_window_fault(ea_fault_word),
                                    window_pc + 32'(2 * ea_fault_word),
                                    window_pc, opcode, profile);
                            end else begin
                                // PRM 4-22/4-23, 4-161/4-165: memory
                                // shifts are word-only, count one, and RMW.
                                decode_words = COUNT_WIDTH'(ea_total_words);
                                decode_uop.uop_class = MX_UCLASS_SHIFT;
                                decode_uop.opcode = MX_UOP_SHIFT;
                                decode_uop.size = MX_OP_WORD;
                                decode_uop.condition = {opcode[8],
                                                        opcode[10:9], 1'b0};
                                decode_uop.immediate = 32'd1;
                                decode_uop.destination_ea =
                                    decoded_destination_ea;
                                decode_uop.sequential_pc = window_pc +
                                    32'(2 * ea_total_words);
                                decode_uop.flags_read = MX_FLAG_X;
                                decode_uop.flags_write = MX_FLAG_ALL;
                                decode_uop.may_fault = 1'b1;
                                decode_uop.memory_write = 1'b1;
                                decode_uop.memory_ordered = 1'b1;
                            end
                        end
                        MX_DECODE_SHIFT_REGISTER: begin
                            if (opcode[7:6] == 2'b11) begin
                                // The separate memory-shift encoding is not
                                // part of this register shifter format.
                                decode_uop = '0;
                                decode_exception = make_illegal_exception(
                                    window_pc, opcode);
                            end else begin
                                decode_uop.uop_class = MX_UCLASS_SHIFT;
                                decode_uop.opcode = MX_UOP_SHIFT;
                                case (opcode[7:6])
                                    2'b00: decode_uop.size = MX_OP_BYTE;
                                    2'b01: decode_uop.size = MX_OP_WORD;
                                    default: decode_uop.size = MX_OP_LONG;
                                endcase
                                decode_uop.condition = {opcode[8],
                                                        opcode[4:3],
                                                        opcode[5]};
                                decode_uop.destination.kind =
                                    MX_OPERAND_DATA_REGISTER;
                                decode_uop.destination.index = {3'd0,
                                                                opcode[2:0]};
                                decode_uop.destination_ea.valid = 1'b1;
                                decode_uop.destination_ea.kind =
                                    MX_EA_DATA_REGISTER;
                                decode_uop.destination_ea.register_index =
                                    opcode[2:0];
                                if (opcode[5]) begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_DATA_REGISTER;
                                    decode_uop.source_a.index = {3'd0,
                                                                opcode[11:9]};
                                    decode_uop.source_ea.valid = 1'b1;
                                    decode_uop.source_ea.kind =
                                        MX_EA_DATA_REGISTER;
                                    decode_uop.source_ea.register_index =
                                        opcode[11:9];
                                end else begin
                                    decode_uop.source_a.kind =
                                        MX_OPERAND_IMMEDIATE;
                                    decode_uop.immediate =
                                        (opcode[11:9] == 3'd0) ? 32'd8 :
                                        {29'd0, opcode[11:9]};
                                end
                                decode_uop.flags_read = MX_FLAG_X;
                                decode_uop.flags_write = MX_FLAG_ALL;
                            end
                        end
                        MX_DECODE_BRANCH: begin
                            decode_uop.uop_class = MX_UCLASS_BRANCH;
                            decode_uop.condition = opcode[11:8];
                            decode_uop.serializing = 1'b1;
                            if (opcode[11:8] == 4'h1)
                                decode_uop.opcode = MX_UOP_BRANCH_SUBROUTINE;
                            else
                                decode_uop.opcode = MX_UOP_BRANCH;
                            if (opcode[11:8] >= 4'h2)
                                decode_uop.flags_read = MX_FLAG_N | MX_FLAG_Z |
                                                        MX_FLAG_V | MX_FLAG_C;

                            if (opcode[7:0] == 8'h00) begin
                                if (window_count < COUNT_WIDTH'(2)) begin
                                    decode_valid = 1'b0;
                                    decode_need_more = 1'b1;
                                    decode_words = '0;
                                    decode_uop = '0;
                                end else if (extension_fault_1 != MX_FAULT_NONE) begin
                                    decode_words = COUNT_WIDTH'(2);
                                    decode_uop = '0;
                                    decode_exception = make_fetch_exception(
                                        extension_fault_1, window_pc + 32'd2,
                                        window_pc, opcode, profile);
                                end else begin
                                    branch_displacement = {{16{extension_word_1[15]}},
                                                           extension_word_1};
                                    branch_target = window_pc + 32'd2 + branch_displacement;
                                    decode_words = COUNT_WIDTH'(2);
                                    decode_uop.sequential_pc = window_pc + 32'd4;
                                    decode_uop.immediate = branch_target;
                                end
                            end else if ((opcode[7:0] == 8'hff) &&
                                         (profile >= MX_PROFILE_M20)) begin
                                if (window_count < COUNT_WIDTH'(3)) begin
                                    decode_valid = 1'b0;
                                    decode_need_more = 1'b1;
                                    decode_words = '0;
                                    decode_uop = '0;
                                end else if (extension_fault_1 != MX_FAULT_NONE) begin
                                    decode_words = COUNT_WIDTH'(2);
                                    decode_uop = '0;
                                    decode_exception = make_fetch_exception(
                                        extension_fault_1, window_pc + 32'd2,
                                        window_pc, opcode, profile);
                                end else if (extension_fault_2 != MX_FAULT_NONE) begin
                                    decode_words = COUNT_WIDTH'(3);
                                    decode_uop = '0;
                                    decode_exception = make_fetch_exception(
                                        extension_fault_2, window_pc + 32'd4,
                                        window_pc, opcode, profile);
                                end else begin
                                    branch_displacement = {extension_word_1,
                                                           extension_word_2};
                                    branch_target = window_pc + 32'd2 + branch_displacement;
                                    decode_words = COUNT_WIDTH'(3);
                                    decode_uop.sequential_pc = window_pc + 32'd6;
                                    decode_uop.immediate = branch_target;
                                end
                            end else begin
                                branch_displacement = {{24{opcode[7]}}, opcode[7:0]};
                                branch_target = window_pc + 32'd2 + branch_displacement;
                                decode_uop.immediate = branch_target;
                            end
                        end
                        default: begin
                            decode_uop = '0;
                            decode_exception = make_illegal_exception(window_pc, opcode);
                        end
                    endcase
                end
            end
        end
    end
endmodule
