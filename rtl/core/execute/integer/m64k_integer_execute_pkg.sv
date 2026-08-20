package m64k_integer_execute_pkg;
    import m64k_execute_backend_pkg::*;
    import m64k_integer_alu_pkg::*;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] source_left;
        logic [63:0] source_right;
        m64k_integer_size_t operand_size;
        m64k_integer_operation_t operation;
        logic extend_in;
        logic update_flags;
    } m64k_integer_execute_request_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic result_valid;
        m64k_execute_result_t result;
        logic flags_valid;
        logic negative;
        logic zero;
        logic overflow;
        logic carry_or_borrow;
        logic extend_valid;
        logic extend;
    } m64k_integer_execute_response_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
    } m64k_integer_execute_squash_t;
endpackage
