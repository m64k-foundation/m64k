package m64k_scalar_multiply_pkg;
    import m64k_execute_backend_pkg::*;

    typedef enum logic [1:0] {
        M64K_MULTIPLY_SIZE_BYTE = 2'd0,
        M64K_MULTIPLY_SIZE_WORD = 2'd1,
        M64K_MULTIPLY_SIZE_LONG = 2'd2,
        M64K_MULTIPLY_SIZE_QUAD = 2'd3
    } m64k_multiply_size_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] source_left;
        logic [63:0] source_right;
        m64k_multiply_size_t operand_size;
        logic signed_operation;
        logic widening;
        logic update_flags;
    } m64k_multiply_request_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [1:0] result_count;
        m64k_execute_result_t [1:0] results;
        logic flags_valid;
        logic negative;
        logic zero;
        logic overflow;
        logic carry;
    } m64k_multiply_response_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
    } m64k_multiply_squash_t;
endpackage
