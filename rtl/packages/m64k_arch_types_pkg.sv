package m64k_arch_types_pkg;
    localparam int unsigned M64K_INITIAL_CORE_COUNT = 4;
    localparam int unsigned M64K_INITIAL_THREADS_PER_CORE = 2;
    localparam int unsigned M64K_CORE_ID_WIDTH = 6;
    localparam int unsigned M64K_HARDWARE_THREAD_ID_WIDTH = 2;
    localparam int unsigned M64K_ASID_WIDTH = 16;
    localparam int unsigned M64K_VIRTUAL_ADDRESS_WIDTH = 64;
    localparam int unsigned M64K_PHYSICAL_ADDRESS_WIDTH = 48;
    localparam int unsigned M64K_NATIVE_XLEN = 64;

    typedef logic [M64K_CORE_ID_WIDTH-1:0] m64k_core_id_t;
    typedef logic [M64K_HARDWARE_THREAD_ID_WIDTH-1:0] m64k_hardware_thread_id_t;
    typedef logic [M64K_ASID_WIDTH-1:0] m64k_asid_t;
    typedef logic [M64K_VIRTUAL_ADDRESS_WIDTH-1:0] m64k_va_t;
    typedef logic [M64K_PHYSICAL_ADDRESS_WIDTH-1:0] m64k_pa_t;
    typedef logic [M64K_NATIVE_XLEN-1:0] m64k_native_word_t;
    typedef logic [M64K_INITIAL_CORE_COUNT-1:0] m64k_initial_core_mask_t;
    typedef logic [M64K_INITIAL_THREADS_PER_CORE-1:0] m64k_initial_hardware_thread_mask_t;

    typedef struct packed {
        m64k_core_id_t core_id;
        m64k_hardware_thread_id_t hardware_thread_id;
    } m64k_execution_context_t;

    typedef enum logic [1:0] {
        M64K_PRIVILEGE_USER = 2'd0,
        M64K_PRIVILEGE_SUPERVISOR = 2'd1,
        M64K_PRIVILEGE_RESERVED_H = 2'd2,
        M64K_PRIVILEGE_MACHINE = 2'd3
    } m64k_privilege_t;
endpackage
