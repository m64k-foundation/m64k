package m64k_integer_alu_pkg;
    typedef enum logic [1:0] {
        M64K_INTEGER_SIZE_BYTE = 2'd0,
        M64K_INTEGER_SIZE_WORD = 2'd1,
        M64K_INTEGER_SIZE_LONG = 2'd2,
        M64K_INTEGER_SIZE_QUAD = 2'd3
    } m64k_integer_size_t;

    typedef enum logic [3:0] {
        M64K_INTEGER_ADD = 4'd0,
        M64K_INTEGER_SUB = 4'd1,
        M64K_INTEGER_ADCX = 4'd2,
        M64K_INTEGER_SBCX = 4'd3,
        M64K_INTEGER_AND = 4'd4,
        M64K_INTEGER_OR = 4'd5,
        M64K_INTEGER_XOR = 4'd6,
        M64K_INTEGER_NOT = 4'd7,
        M64K_INTEGER_NEG = 4'd8,
        M64K_INTEGER_NEGX = 4'd9,
        M64K_INTEGER_CMP = 4'd10,
        M64K_INTEGER_TST = 4'd11
    } m64k_integer_operation_t;

    function automatic logic m64k_integer_operation_is_legal(input m64k_integer_operation_t operation);
        case (operation)
            M64K_INTEGER_ADD,
            M64K_INTEGER_SUB,
            M64K_INTEGER_ADCX,
            M64K_INTEGER_SBCX,
            M64K_INTEGER_AND,
            M64K_INTEGER_OR,
            M64K_INTEGER_XOR,
            M64K_INTEGER_NOT,
            M64K_INTEGER_NEG,
            M64K_INTEGER_NEGX,
            M64K_INTEGER_CMP,
            M64K_INTEGER_TST: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction
endpackage
