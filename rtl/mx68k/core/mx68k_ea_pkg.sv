package mx68k_ea_pkg;
    import mx68k_arch_pkg::*;

    typedef enum logic [3:0] {
        MX_EA_NONE,
        MX_EA_DATA_REGISTER,
        MX_EA_ADDRESS_REGISTER,
        MX_EA_INDIRECT,
        MX_EA_POSTINCREMENT,
        MX_EA_PREDECREMENT,
        MX_EA_DISPLACEMENT,
        MX_EA_INDEXED,
        MX_EA_ABSOLUTE_WORD,
        MX_EA_ABSOLUTE_LONG,
        MX_EA_PC_DISPLACEMENT,
        MX_EA_PC_INDEXED,
        MX_EA_IMMEDIATE,
        MX_EA_INVALID
    } mx_ea_kind_t;

    // extension_pc is the address of extension_0. On the 68000 that is the
    // architecturally visible base for PC-relative effective addresses.
    typedef struct packed {
        logic valid;
        mx_ea_kind_t kind;
        logic [2:0] register_index;
        logic [15:0] extension_0;
        logic [15:0] extension_1;
        logic [31:0] extension_pc;
    } mx_ea_t;

    function automatic mx_ea_kind_t mx_ea_decode_kind(
        input logic [2:0] mode,
        input logic [2:0] register_index
    );
        case (mode)
            3'd0: return MX_EA_DATA_REGISTER;
            3'd1: return MX_EA_ADDRESS_REGISTER;
            3'd2: return MX_EA_INDIRECT;
            3'd3: return MX_EA_POSTINCREMENT;
            3'd4: return MX_EA_PREDECREMENT;
            3'd5: return MX_EA_DISPLACEMENT;
            3'd6: return MX_EA_INDEXED;
            3'd7: begin
                case (register_index)
                    3'd0: return MX_EA_ABSOLUTE_WORD;
                    3'd1: return MX_EA_ABSOLUTE_LONG;
                    3'd2: return MX_EA_PC_DISPLACEMENT;
                    3'd3: return MX_EA_PC_INDEXED;
                    3'd4: return MX_EA_IMMEDIATE;
                    default: return MX_EA_INVALID;
                endcase
            end
            default: return MX_EA_INVALID;
        endcase
    endfunction

    function automatic logic [2:0] mx_ea_extension_words(
        input logic [2:0] mode,
        input logic [2:0] register_index,
        input mx_operand_size_t size
    );
        mx_ea_kind_t kind;
        begin
            kind = mx_ea_decode_kind(mode, register_index);
            case (kind)
                MX_EA_DISPLACEMENT,
                MX_EA_INDEXED,
                MX_EA_ABSOLUTE_WORD,
                MX_EA_PC_DISPLACEMENT,
                MX_EA_PC_INDEXED: return 3'd1;
                MX_EA_ABSOLUTE_LONG: return 3'd2;
                MX_EA_IMMEDIATE: return (size == MX_OP_LONG) ? 3'd2 : 3'd1;
                MX_EA_INVALID: return 3'd7;
                default: return 3'd0;
            endcase
        end
    endfunction

    function automatic logic mx_ea_is_memory(input mx_ea_t ea);
        return ea.valid && (ea.kind inside {
            MX_EA_INDIRECT, MX_EA_POSTINCREMENT, MX_EA_PREDECREMENT,
            MX_EA_DISPLACEMENT, MX_EA_INDEXED, MX_EA_ABSOLUTE_WORD,
            MX_EA_ABSOLUTE_LONG, MX_EA_PC_DISPLACEMENT, MX_EA_PC_INDEXED
        });
    endfunction

    function automatic logic mx_ea_is_control(input mx_ea_t ea);
        return ea.valid && (ea.kind inside {
            MX_EA_INDIRECT, MX_EA_DISPLACEMENT, MX_EA_INDEXED,
            MX_EA_ABSOLUTE_WORD, MX_EA_ABSOLUTE_LONG,
            MX_EA_PC_DISPLACEMENT, MX_EA_PC_INDEXED
        });
    endfunction

    function automatic logic mx_ea_is_alterable(input mx_ea_t ea);
        return ea.valid && !(ea.kind inside {
            MX_EA_NONE, MX_EA_INVALID, MX_EA_PC_DISPLACEMENT,
            MX_EA_PC_INDEXED, MX_EA_IMMEDIATE
        });
    endfunction

    function automatic logic [2:0] mx_ea_step_bytes(
        input mx_operand_size_t size,
        input logic [2:0] address_register
    );
        case (size)
            // Byte accesses through A7 preserve word stack alignment.
            MX_OP_BYTE: return (address_register == 3'd7) ? 3'd2 : 3'd1;
            MX_OP_WORD: return 3'd2;
            default: return 3'd4;
        endcase
    endfunction

    function automatic logic [31:0] mx_ea_immediate_value(
        input mx_ea_t ea,
        input mx_operand_size_t size
    );
        case (size)
            MX_OP_BYTE: return {24'd0, ea.extension_0[7:0]};
            MX_OP_WORD: return {16'd0, ea.extension_0};
            default: return {ea.extension_0, ea.extension_1};
        endcase
    endfunction

    function automatic logic [31:0] mx_ea_index_value(
        input mx_ea_t ea,
        input logic [31:0] data_index_value,
        input logic [31:0] address_index_value
    );
        logic [31:0] raw_index;
        begin
            raw_index = ea.extension_0[15] ? address_index_value :
                                               data_index_value;
            return ea.extension_0[11] ? raw_index :
                   {{16{raw_index[15]}}, raw_index[15:0]};
        end
    endfunction

    function automatic logic [31:0] mx_ea_address(
        input mx_ea_t ea,
        input mx_operand_size_t size,
        input logic [31:0] address_register_value,
        input logic [31:0] data_index_value,
        input logic [31:0] address_index_value
    );
        logic [31:0] index_value;
        begin
            index_value = mx_ea_index_value(ea, data_index_value,
                                            address_index_value);
            case (ea.kind)
                MX_EA_INDIRECT,
                MX_EA_POSTINCREMENT: return address_register_value;
                MX_EA_PREDECREMENT: return address_register_value -
                    mx_ea_step_bytes(size, ea.register_index);
                MX_EA_DISPLACEMENT: return address_register_value +
                    {{16{ea.extension_0[15]}}, ea.extension_0};
                MX_EA_INDEXED: return address_register_value + index_value +
                    {{24{ea.extension_0[7]}}, ea.extension_0[7:0]};
                MX_EA_ABSOLUTE_WORD: return
                    {{16{ea.extension_0[15]}}, ea.extension_0};
                MX_EA_ABSOLUTE_LONG: return
                    {ea.extension_0, ea.extension_1};
                MX_EA_PC_DISPLACEMENT: return ea.extension_pc +
                    {{16{ea.extension_0[15]}}, ea.extension_0};
                MX_EA_PC_INDEXED: return ea.extension_pc + index_value +
                    {{24{ea.extension_0[7]}}, ea.extension_0[7:0]};
                default: return 32'd0;
            endcase
        end
    endfunction
endpackage
