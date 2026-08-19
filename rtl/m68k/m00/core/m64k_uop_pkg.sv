package m64k_uop_pkg;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;
    import m64k_ea_pkg::*;

    typedef enum logic [4:0] {
        M64K_UCLASS_NONE,
        M64K_UCLASS_ALU,
        M64K_UCLASS_SHIFT,
        M64K_UCLASS_EA,
        M64K_UCLASS_LOAD,
        M64K_UCLASS_STORE,
        M64K_UCLASS_BRANCH,
        M64K_UCLASS_REGISTER,
        M64K_UCLASS_SYSTEM,
        M64K_UCLASS_MULDIV,
        M64K_UCLASS_FPU,
        M64K_UCLASS_VECTOR,
        M64K_UCLASS_COMMIT
    } m64k_uop_class_t;

    typedef enum logic [7:0] {
        M64K_UOP_INVALID,
        M64K_UOP_NOP,
        M64K_UOP_MOVE,
        M64K_UOP_MOVE_ADDRESS,
        M64K_UOP_ADD,
        M64K_UOP_ADD_EXTEND,
        M64K_UOP_SUBTRACT,
        M64K_UOP_SUBTRACT_EXTEND,
        M64K_UOP_AND,
        M64K_UOP_OR,
        M64K_UOP_XOR,
        M64K_UOP_COMPARE,
        M64K_UOP_COMPARE_MEMORY,
        M64K_UOP_TEST,
        M64K_UOP_CLEAR,
        M64K_UOP_NEGATE,
        M64K_UOP_SHIFT,
        M64K_UOP_ROTATE,
        M64K_UOP_CALCULATE_EA,
        M64K_UOP_LOAD,
        M64K_UOP_STORE,
        M64K_UOP_BRANCH,
        M64K_UOP_BRANCH_SUBROUTINE,
        M64K_UOP_JUMP,
        M64K_UOP_JUMP_SUBROUTINE,
        M64K_UOP_RETURN,
        M64K_UOP_TRAP,
        M64K_UOP_EXCEPTION_RETURN,
        M64K_UOP_STOP,
        M64K_UOP_RESET,
        M64K_UOP_MOVE_MULTIPLE,
        M64K_UOP_ATOMIC,
        M64K_UOP_MULTIPLY,
        M64K_UOP_DIVIDE,
        M64K_UOP_FPU_EXECUTE,
        M64K_UOP_VECTOR_EXECUTE,
        M64K_UOP_PUSH_EFFECTIVE_ADDRESS,
        M64K_UOP_NOT,
        M64K_UOP_DBCC,
        M64K_UOP_SWAP,
        M64K_UOP_EXCHANGE,
        M64K_UOP_LINK,
        M64K_UOP_UNLINK,
        M64K_UOP_SIGN_EXTEND,
        M64K_UOP_BIT_TEST,
        M64K_UOP_CHECK_BOUNDS,
        M64K_UOP_SET_CONDITION,
        M64K_UOP_COMMIT
    } m64k_uop_opcode_t;

    typedef enum logic [3:0] {
        M64K_OPERAND_NONE,
        M64K_OPERAND_DATA_REGISTER,
        M64K_OPERAND_ADDRESS_REGISTER,
        M64K_OPERAND_PC,
        M64K_OPERAND_SR,
        M64K_OPERAND_CONTROL_REGISTER,
        M64K_OPERAND_IMMEDIATE,
        M64K_OPERAND_TEMPORARY,
        M64K_OPERAND_FP_REGISTER,
        M64K_OPERAND_VECTOR_REGISTER,
        M64K_OPERAND_USP
    } m64k_operand_kind_t;

    typedef struct packed {
        m64k_operand_kind_t kind;
        logic [5:0] index;
    } m64k_operand_ref_t;

    localparam logic [4:0] M64K_FLAG_X = 5'b1_0000;
    localparam logic [4:0] M64K_FLAG_N = 5'b0_1000;
    localparam logic [4:0] M64K_FLAG_Z = 5'b0_0100;
    localparam logic [4:0] M64K_FLAG_V = 5'b0_0010;
    localparam logic [4:0] M64K_FLAG_C = 5'b0_0001;
    localparam logic [4:0] M64K_FLAG_ALL = 5'b1_1111;

    // Decoder-to-backend contract. Values are references or decoded constants;
    // physical register selection and forwarding remain microarchitectural.
    typedef struct packed {
        logic valid;
        logic first;
        logic last;
        m64k_uop_class_t uop_class;
        m64k_uop_opcode_t opcode;
        m64k_operand_size_t size;
        m64k_profile_t profile;
        logic [7:0] instruction_id;
        logic [15:0] instruction_word;
        logic [31:0] instruction_pc;
        logic [31:0] sequential_pc;
        m64k_operand_ref_t source_a;
        m64k_operand_ref_t source_b;
        m64k_operand_ref_t destination;
        logic [31:0] immediate;
        logic [31:0] memory_address;
        m64k_ea_t source_ea;
        m64k_ea_t destination_ea;
        logic [3:0] condition;
        logic [4:0] flags_read;
        logic [4:0] flags_write;
        logic [7:0] exception_vector;
        logic privileged;
        logic serializing;
        logic may_fault;
        logic memory_write;
        logic memory_atomic;
        logic memory_ordered;
        logic [3:0] checkpoint;
    } m64k_uop_t;

    function automatic logic m64k_uop_is_memory(input m64k_uop_t uop);
        return (uop.uop_class == M64K_UCLASS_LOAD) ||
               (uop.uop_class == M64K_UCLASS_STORE);
    endfunction

    function automatic logic m64k_uop_is_control(input m64k_uop_t uop);
        return (uop.uop_class == M64K_UCLASS_BRANCH) ||
               (uop.uop_class == M64K_UCLASS_SYSTEM);
    endfunction

    function automatic logic m64k_uop_writes_flags(input m64k_uop_t uop);
        return |uop.flags_write;
    endfunction
endpackage
