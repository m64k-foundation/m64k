package m64k_shift_rotate_shared_pkg;
    import m64k_execute_backend_pkg::*;
    import m64k_shift_rotate_pkg::*;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] source;
        logic [5:0] count;
        m64k_shift_size_t operand_size;
        m64k_shift_operation_t operation;
        logic extend_in;
        logic update_flags;
    } m64k_shift_rotate_shared_request_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] result;
        logic flags_valid;
        logic negative;
        logic zero;
        logic overflow;
        logic carry;
        logic extend_valid;
        logic extend_out;
    } m64k_shift_rotate_shared_response_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
    } m64k_shift_rotate_shared_squash_t;
endpackage
