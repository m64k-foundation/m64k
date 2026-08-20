package m64k_precise_retirement_pkg;
    import m64k_native_contract_pkg::*;

    localparam int unsigned M64K_RETIRE_MAX_WRITES = 4;

    typedef enum logic [7:0] {
        M64K_RETIRE_CONTRACT_MAJOR = 8'd1
    } m64k_retire_contract_major_t;

    typedef enum logic [7:0] {
        M64K_RETIRE_CONTRACT_MINOR = 8'd0
    } m64k_retire_contract_minor_t;

    typedef enum logic [2:0] {
        M64K_RETIRE_NORMAL = 3'd0,
        M64K_RETIRE_SYNCHRONOUS_EXCEPTION = 3'd1,
        M64K_RETIRE_INTERRUPT = 3'd2,
        M64K_RETIRE_DEBUG_ENTRY = 3'd3,
        M64K_RETIRE_HALT = 3'd4
    } m64k_retire_outcome_t;

    typedef enum logic [2:0] {
        M64K_RETIRE_DESTINATION_NONE = 3'd0,
        M64K_RETIRE_DESTINATION_INTEGER = 3'd1,
        M64K_RETIRE_DESTINATION_FLOAT = 3'd2,
        M64K_RETIRE_DESTINATION_VECTOR = 3'd3,
        M64K_RETIRE_DESTINATION_PREDICATE = 3'd4,
        M64K_RETIRE_DESTINATION_CONTROL = 3'd5,
        M64K_RETIRE_DESTINATION_STATUS = 3'd6
    } m64k_retire_destination_class_t;

    typedef struct packed {
        logic valid;
        m64k_retire_destination_class_t destination_class;
        logic [11:0] destination_index;
        logic [7:0] byte_enable;
        m64k_native_word_t value;
    } m64k_retire_write_t;

    typedef struct packed {
        logic valid;
        logic is_write;
        logic is_atomic;
        logic is_device;
        m64k_pa_t physical_address;
        m64k_access_size_t size;
        logic [63:0] data;
        logic [7:0] byte_enable;
    } m64k_retire_memory_effect_t;

    typedef struct packed {
        logic [7:0] contract_major;
        logic [7:0] contract_minor;
        m64k_execution_context_t execution_context;
        logic [63:0] hardware_thread_retirement_order;
        logic [63:0] program_counter;
        logic [63:0] next_program_counter;
        logic [127:0] instruction;
        logic [4:0] instruction_bytes;
        m64k_privilege_t privilege_before;
        m64k_privilege_t privilege_after;
        m64k_retire_outcome_t outcome;
        logic [15:0] exception_cause;
        logic [63:0] exception_address;
        logic [2:0] write_count;
        m64k_retire_write_t [M64K_RETIRE_MAX_WRITES-1:0] writes;
        m64k_retire_memory_effect_t memory_effect;
    } m64k_precise_retirement_record_t;
endpackage
