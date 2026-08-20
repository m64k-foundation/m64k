// Private execution-backend contracts. These types are microarchitectural and
// are not part of the M64K ISA, ABI, retirement record, or memory transaction ID.
package m64k_execute_backend_pkg;
    import m64k_arch_types_pkg::*;

    localparam int unsigned M64K_BACKEND_ROB_INDEX_WIDTH = 8;
    localparam int unsigned M64K_BACKEND_ROB_GENERATION_WIDTH = 8;
    localparam int unsigned M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH = 64;
    localparam int unsigned M64K_BACKEND_UOP_INDEX_WIDTH = 4;

    typedef logic [M64K_BACKEND_ROB_INDEX_WIDTH-1:0] m64k_backend_rob_index_t;
    typedef logic [M64K_BACKEND_ROB_GENERATION_WIDTH-1:0] m64k_backend_rob_generation_t;
    typedef logic [M64K_BACKEND_ALLOCATION_SEQUENCE_WIDTH-1:0] m64k_backend_allocation_sequence_t;
    typedef logic [M64K_BACKEND_UOP_INDEX_WIDTH-1:0] m64k_backend_uop_index_t;

    // The allocator must not reuse the same complete token until every unit that
    // accepted it has either returned or cancelled the operation. rob_generation
    // distinguishes reuse of one ROB slot; allocation_sequence prevents an old
    // response from aliasing a later allocation after localized slot reuse. Any
    // eventual allocation_sequence rollover requires allocation stop and a proved
    // drain of every structure that can retain a tag before sequence zero is reused.
    typedef struct packed {
        m64k_execution_context_t execution_context;
        m64k_backend_rob_index_t rob_index;
        m64k_backend_rob_generation_t rob_generation;
        m64k_backend_allocation_sequence_t allocation_sequence;
        m64k_backend_uop_index_t uop_index;
    } m64k_execute_tag_t;

    typedef enum logic [1:0] {
        M64K_EXECUTE_RESULT_LOW = 2'd0,
        M64K_EXECUTE_RESULT_HIGH = 2'd1,
        M64K_EXECUTE_RESULT_QUOTIENT = 2'd2,
        M64K_EXECUTE_RESULT_REMAINDER = 2'd3
    } m64k_execute_result_role_t;

    typedef struct packed {
        logic valid;
        m64k_execute_result_role_t role;
        logic [63:0] value;
    } m64k_execute_result_t;
endpackage
