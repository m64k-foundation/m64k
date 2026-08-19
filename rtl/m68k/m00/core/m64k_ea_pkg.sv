package m64k_ea_pkg;
    import m64k_arch_pkg::*;

    typedef enum logic [3:0] {
        M64K_EA_NONE,
        M64K_EA_DATA_REGISTER,
        M64K_EA_ADDRESS_REGISTER,
        M64K_EA_INDIRECT,
        M64K_EA_POSTINCREMENT,
        M64K_EA_PREDECREMENT,
        M64K_EA_DISPLACEMENT,
        M64K_EA_INDEXED,
        M64K_EA_ABSOLUTE_WORD,
        M64K_EA_ABSOLUTE_LONG,
        M64K_EA_PC_DISPLACEMENT,
        M64K_EA_PC_INDEXED,
        M64K_EA_IMMEDIATE,
        M64K_EA_INVALID
    } m64k_ea_kind_t;

    // extension_pc is the address of extension_0. On the 68000 that is the
    // architecturally visible base for PC-relative effective addresses.
    typedef struct packed {
        logic valid;
        m64k_ea_kind_t kind;
        logic [2:0] register_index;
        logic [15:0] extension_0;
        logic [15:0] extension_1;
        logic [31:0] extension_pc;
    } m64k_ea_t;

    function automatic m64k_ea_kind_t m64k_ea_decode_kind(
        input logic [2:0] mode,
        input logic [2:0] register_index
    );
        case (mode)
            3'd0: return M64K_EA_DATA_REGISTER;
            3'd1: return M64K_EA_ADDRESS_REGISTER;
            3'd2: return M64K_EA_INDIRECT;
            3'd3: return M64K_EA_POSTINCREMENT;
            3'd4: return M64K_EA_PREDECREMENT;
            3'd5: return M64K_EA_DISPLACEMENT;
            3'd6: return M64K_EA_INDEXED;
            3'd7: begin
                case (register_index)
                    3'd0: return M64K_EA_ABSOLUTE_WORD;
                    3'd1: return M64K_EA_ABSOLUTE_LONG;
                    3'd2: return M64K_EA_PC_DISPLACEMENT;
                    3'd3: return M64K_EA_PC_INDEXED;
                    3'd4: return M64K_EA_IMMEDIATE;
                    default: return M64K_EA_INVALID;
                endcase
            end
            default: return M64K_EA_INVALID;
        endcase
    endfunction

    function automatic logic [2:0] m64k_ea_extension_words(
        input logic [2:0] mode,
        input logic [2:0] register_index,
        input m64k_operand_size_t size
    );
        m64k_ea_kind_t kind;
        begin
            kind = m64k_ea_decode_kind(mode, register_index);
            case (kind)
                M64K_EA_DISPLACEMENT,
                M64K_EA_INDEXED,
                M64K_EA_ABSOLUTE_WORD,
                M64K_EA_PC_DISPLACEMENT,
                M64K_EA_PC_INDEXED: return 3'd1;
                M64K_EA_ABSOLUTE_LONG: return 3'd2;
                M64K_EA_IMMEDIATE: return (size == M64K_OP_LONG) ? 3'd2 : 3'd1;
                M64K_EA_INVALID: return 3'd7;
                default: return 3'd0;
            endcase
        end
    endfunction

    function automatic logic m64k_ea_is_memory(input m64k_ea_t ea);
        return ea.valid && (ea.kind inside {
            M64K_EA_INDIRECT, M64K_EA_POSTINCREMENT, M64K_EA_PREDECREMENT,
            M64K_EA_DISPLACEMENT, M64K_EA_INDEXED, M64K_EA_ABSOLUTE_WORD,
            M64K_EA_ABSOLUTE_LONG, M64K_EA_PC_DISPLACEMENT, M64K_EA_PC_INDEXED
        });
    endfunction

    function automatic logic m64k_ea_is_control(input m64k_ea_t ea);
        return ea.valid && (ea.kind inside {
            M64K_EA_INDIRECT, M64K_EA_DISPLACEMENT, M64K_EA_INDEXED,
            M64K_EA_ABSOLUTE_WORD, M64K_EA_ABSOLUTE_LONG,
            M64K_EA_PC_DISPLACEMENT, M64K_EA_PC_INDEXED
        });
    endfunction

    function automatic logic m64k_ea_is_alterable(input m64k_ea_t ea);
        return ea.valid && !(ea.kind inside {
            M64K_EA_NONE, M64K_EA_INVALID, M64K_EA_PC_DISPLACEMENT,
            M64K_EA_PC_INDEXED, M64K_EA_IMMEDIATE
        });
    endfunction

    function automatic logic [2:0] m64k_ea_step_bytes(
        input m64k_operand_size_t size,
        input logic [2:0] address_register
    );
        case (size)
            // Byte accesses through A7 preserve word stack alignment.
            M64K_OP_BYTE: return (address_register == 3'd7) ? 3'd2 : 3'd1;
            M64K_OP_WORD: return 3'd2;
            default: return 3'd4;
        endcase
    endfunction

    function automatic logic [31:0] m64k_ea_immediate_value(
        input m64k_ea_t ea,
        input m64k_operand_size_t size
    );
        case (size)
            M64K_OP_BYTE: return {24'd0, ea.extension_0[7:0]};
            M64K_OP_WORD: return {16'd0, ea.extension_0};
            default: return {ea.extension_0, ea.extension_1};
        endcase
    endfunction

    function automatic logic [31:0] m64k_ea_index_value(
        input m64k_ea_t ea,
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

    function automatic logic [31:0] m64k_ea_address(
        input m64k_ea_t ea,
        input m64k_operand_size_t size,
        input logic [31:0] address_register_value,
        input logic [31:0] data_index_value,
        input logic [31:0] address_index_value
    );
        logic [31:0] index_value;
        begin
            index_value = m64k_ea_index_value(ea, data_index_value,
                                            address_index_value);
            case (ea.kind)
                M64K_EA_INDIRECT,
                M64K_EA_POSTINCREMENT: return address_register_value;
                M64K_EA_PREDECREMENT: return address_register_value -
                    m64k_ea_step_bytes(size, ea.register_index);
                M64K_EA_DISPLACEMENT: return address_register_value +
                    {{16{ea.extension_0[15]}}, ea.extension_0};
                M64K_EA_INDEXED: return address_register_value + index_value +
                    {{24{ea.extension_0[7]}}, ea.extension_0[7:0]};
                M64K_EA_ABSOLUTE_WORD: return
                    {{16{ea.extension_0[15]}}, ea.extension_0};
                M64K_EA_ABSOLUTE_LONG: return
                    {ea.extension_0, ea.extension_1};
                M64K_EA_PC_DISPLACEMENT: return ea.extension_pc +
                    {{16{ea.extension_0[15]}}, ea.extension_0};
                M64K_EA_PC_INDEXED: return ea.extension_pc + index_value +
                    {{24{ea.extension_0[7]}}, ea.extension_0[7:0]};
                default: return 32'd0;
            endcase
        end
    endfunction
endpackage
