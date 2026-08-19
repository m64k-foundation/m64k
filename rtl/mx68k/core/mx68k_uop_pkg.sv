package mx68k_uop_pkg;
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;
    import mx68k_ea_pkg::*;

    typedef enum logic [4:0] {
        MX_UCLASS_NONE,
        MX_UCLASS_ALU,
        MX_UCLASS_SHIFT,
        MX_UCLASS_EA,
        MX_UCLASS_LOAD,
        MX_UCLASS_STORE,
        MX_UCLASS_BRANCH,
        MX_UCLASS_REGISTER,
        MX_UCLASS_SYSTEM,
        MX_UCLASS_MULDIV,
        MX_UCLASS_FPU,
        MX_UCLASS_VECTOR,
        MX_UCLASS_COMMIT
    } mx_uop_class_t;

    typedef enum logic [7:0] {
        MX_UOP_INVALID,
        MX_UOP_NOP,
        MX_UOP_MOVE,
        MX_UOP_MOVE_ADDRESS,
        MX_UOP_ADD,
        MX_UOP_ADD_EXTEND,
        MX_UOP_SUBTRACT,
        MX_UOP_SUBTRACT_EXTEND,
        MX_UOP_AND,
        MX_UOP_OR,
        MX_UOP_XOR,
        MX_UOP_COMPARE,
        MX_UOP_COMPARE_MEMORY,
        MX_UOP_TEST,
        MX_UOP_CLEAR,
        MX_UOP_NEGATE,
        MX_UOP_SHIFT,
        MX_UOP_ROTATE,
        MX_UOP_CALCULATE_EA,
        MX_UOP_LOAD,
        MX_UOP_STORE,
        MX_UOP_BRANCH,
        MX_UOP_BRANCH_SUBROUTINE,
        MX_UOP_JUMP,
        MX_UOP_JUMP_SUBROUTINE,
        MX_UOP_RETURN,
        MX_UOP_TRAP,
        MX_UOP_EXCEPTION_RETURN,
        MX_UOP_STOP,
        MX_UOP_RESET,
        MX_UOP_MOVE_MULTIPLE,
        MX_UOP_ATOMIC,
        MX_UOP_MULTIPLY,
        MX_UOP_DIVIDE,
        MX_UOP_FPU_EXECUTE,
        MX_UOP_VECTOR_EXECUTE,
        MX_UOP_PUSH_EFFECTIVE_ADDRESS,
        MX_UOP_NOT,
        MX_UOP_DBCC,
        MX_UOP_SWAP,
        MX_UOP_EXCHANGE,
        MX_UOP_LINK,
        MX_UOP_UNLINK,
        MX_UOP_SIGN_EXTEND,
        MX_UOP_BIT_TEST,
        MX_UOP_CHECK_BOUNDS,
        MX_UOP_SET_CONDITION,
        MX_UOP_COMMIT
    } mx_uop_opcode_t;

    typedef enum logic [3:0] {
        MX_OPERAND_NONE,
        MX_OPERAND_DATA_REGISTER,
        MX_OPERAND_ADDRESS_REGISTER,
        MX_OPERAND_PC,
        MX_OPERAND_SR,
        MX_OPERAND_CONTROL_REGISTER,
        MX_OPERAND_IMMEDIATE,
        MX_OPERAND_TEMPORARY,
        MX_OPERAND_FP_REGISTER,
        MX_OPERAND_VECTOR_REGISTER,
        MX_OPERAND_USP
    } mx_operand_kind_t;

    typedef struct packed {
        mx_operand_kind_t kind;
        logic [5:0] index;
    } mx_operand_ref_t;

    localparam logic [4:0] MX_FLAG_X = 5'b1_0000;
    localparam logic [4:0] MX_FLAG_N = 5'b0_1000;
    localparam logic [4:0] MX_FLAG_Z = 5'b0_0100;
    localparam logic [4:0] MX_FLAG_V = 5'b0_0010;
    localparam logic [4:0] MX_FLAG_C = 5'b0_0001;
    localparam logic [4:0] MX_FLAG_ALL = 5'b1_1111;

    // Decoder-to-backend contract. Values are references or decoded constants;
    // physical register selection and forwarding remain microarchitectural.
    typedef struct packed {
        logic valid;
        logic first;
        logic last;
        mx_uop_class_t uop_class;
        mx_uop_opcode_t opcode;
        mx_operand_size_t size;
        mx_profile_t profile;
        logic [7:0] instruction_id;
        logic [15:0] instruction_word;
        logic [31:0] instruction_pc;
        logic [31:0] sequential_pc;
        mx_operand_ref_t source_a;
        mx_operand_ref_t source_b;
        mx_operand_ref_t destination;
        logic [31:0] immediate;
        logic [31:0] memory_address;
        mx_ea_t source_ea;
        mx_ea_t destination_ea;
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
    } mx_uop_t;

    function automatic logic mx_uop_is_memory(input mx_uop_t uop);
        return (uop.uop_class == MX_UCLASS_LOAD) ||
               (uop.uop_class == MX_UCLASS_STORE);
    endfunction

    function automatic logic mx_uop_is_control(input mx_uop_t uop);
        return (uop.uop_class == MX_UCLASS_BRANCH) ||
               (uop.uop_class == MX_UCLASS_SYSTEM);
    endfunction

    function automatic logic mx_uop_writes_flags(input mx_uop_t uop);
        return |uop.flags_write;
    endfunction
endpackage
