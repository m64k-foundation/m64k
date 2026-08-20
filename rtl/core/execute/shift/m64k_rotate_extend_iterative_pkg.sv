package m64k_rotate_extend_iterative_pkg;
    import m64k_execute_backend_pkg::*;
    import m64k_shift_rotate_pkg::*;

    typedef enum logic {
        M64K_ROTATE_EXTEND_LEFT  = 1'b0,
        M64K_ROTATE_EXTEND_RIGHT = 1'b1
    } m64k_rotate_extend_direction_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
        logic [63:0] source;
        logic [5:0] count;
        m64k_shift_size_t operand_size;
        m64k_rotate_extend_direction_t direction;
        logic extend_in;
        logic update_flags;
    } m64k_rotate_extend_request_t;

    // The result and persistent X value form one atomic execution response.
    // Retirement must either commit both values or commit neither value.
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
    } m64k_rotate_extend_response_t;

    typedef struct packed {
        m64k_execute_tag_t tag;
    } m64k_rotate_extend_squash_t;
endpackage
