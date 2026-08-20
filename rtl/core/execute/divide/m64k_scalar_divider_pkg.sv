package m64k_scalar_divider_pkg;
    import m64k_execute_backend_pkg::*;

    typedef enum logic [1:0] {
        M64K_DIVIDE_SIZE_BYTE = 2'd0,
        M64K_DIVIDE_SIZE_WORD = 2'd1,
        M64K_DIVIDE_SIZE_LONG = 2'd2,
        M64K_DIVIDE_SIZE_QUAD = 2'd3
    } m64k_divide_size_t;

    typedef enum logic [1:0] {
        M64K_DIVIDE_QUOTIENT = 2'd0,
        M64K_DIVIDE_REMAINDER = 2'd1,
        M64K_DIVIDE_QUOTIENT_REMAINDER = 2'd2
    } m64k_divide_result_form_t;

    typedef enum logic [1:0] {
        M64K_DIVIDE_FAULT_NONE = 2'd0,
        M64K_DIVIDE_FAULT_ZERO = 2'd1,
        M64K_DIVIDE_FAULT_QUOTIENT_OVERFLOW = 2'd2
    } m64k_divide_fault_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        m64k_divide_size_t operand_size;
        m64k_divide_result_form_t result_form;
        logic signed_operation;
        logic double_width_dividend;
        logic update_flags;
        logic [63:0] dividend_low;
        logic [63:0] dividend_high;
        logic [63:0] divisor;
    } m64k_divide_request_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [1:0] result_count;
        m64k_execute_result_t [1:0] results;
        logic flags_valid;
        logic negative;
        logic zero;
        logic overflow;
        logic carry;
        logic fault_valid;
        m64k_divide_fault_t fault;
    } m64k_divide_response_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
    } m64k_divide_squash_t;
endpackage
