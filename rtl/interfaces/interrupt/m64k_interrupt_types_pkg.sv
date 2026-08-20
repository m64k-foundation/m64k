package m64k_interrupt_types_pkg;
    import m64k_arch_types_pkg::*;

    typedef enum logic [2:0] {
        M64K_INTERRUPT_EXTERNAL = 3'd0,
        M64K_INTERRUPT_TIMER = 3'd1,
        M64K_INTERRUPT_SOFTWARE = 3'd2,
        M64K_INTERRUPT_NMI = 3'd3,
        M64K_INTERRUPT_MACHINE_CHECK = 3'd4,
        M64K_INTERRUPT_DEBUG = 3'd5
    } m64k_interrupt_class_t;

    typedef enum logic [1:0] {
        M64K_INTERRUPT_TARGET_HARDWARE_THREAD = 2'd0,
        M64K_INTERRUPT_TARGET_ANY_THREAD_IN_CORE = 2'd1,
        M64K_INTERRUPT_TARGET_ALL_THREADS_IN_CORE = 2'd2,
        M64K_INTERRUPT_TARGET_ALL_CORES = 2'd3
    } m64k_interrupt_target_mode_t;

    typedef struct packed {
        m64k_interrupt_target_mode_t target_mode;
        m64k_execution_context_t target_context;
        logic [15:0] source_id;
        logic [15:0] interrupt_id;
        logic [15:0] vector;
        logic [7:0] interrupt_priority;
        m64k_interrupt_class_t interrupt_class;
        logic level_sensitive;
    } m64k_targeted_interrupt_t;

    typedef enum logic [1:0] {
        M64K_INTERRUPT_ACCEPTED = 2'd0,
        M64K_INTERRUPT_RETRY = 2'd1,
        M64K_INTERRUPT_DELIVERY_ERROR = 2'd2
    } m64k_interrupt_disposition_t;

    typedef struct packed {
        m64k_execution_context_t target_context;
        logic [15:0] source_id;
        logic [15:0] interrupt_id;
        m64k_interrupt_disposition_t disposition;
    } m64k_interrupt_completion_t;
endpackage
