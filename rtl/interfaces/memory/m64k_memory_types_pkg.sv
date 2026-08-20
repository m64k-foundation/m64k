package m64k_memory_types_pkg;
    import m64k_arch_types_pkg::*;

    localparam int unsigned M64K_TRANSACTION_ID_WIDTH = 12;
    localparam int unsigned M64K_CACHE_LINE_BYTES = 64;
    localparam int unsigned M64K_TRANSPORT_BEAT_BYTES = 16;
    localparam int unsigned M64K_TRANSPORT_BEAT_BITS = M64K_TRANSPORT_BEAT_BYTES * 8;
    localparam int unsigned M64K_CACHE_LINE_BEATS = M64K_CACHE_LINE_BYTES / M64K_TRANSPORT_BEAT_BYTES;

    typedef logic [M64K_TRANSACTION_ID_WIDTH-1:0] m64k_transaction_id_t;
    typedef logic [M64K_CACHE_LINE_BEATS-1:0] m64k_cache_line_beat_mask_t;

    typedef enum logic [2:0] {
        M64K_MEMORY_READ = 3'd0,
        M64K_MEMORY_WRITE = 3'd1,
        M64K_MEMORY_INSTRUCTION_FETCH = 3'd2,
        M64K_MEMORY_ATOMIC = 3'd3,
        M64K_MEMORY_FENCE = 3'd4,
        M64K_MEMORY_CACHE_MAINTENANCE = 3'd5
    } m64k_memory_operation_t;

    typedef enum logic [2:0] {
        M64K_ACCESS_SIZE_1_BYTE = 3'd0,
        M64K_ACCESS_SIZE_2_BYTES = 3'd1,
        M64K_ACCESS_SIZE_4_BYTES = 3'd2,
        M64K_ACCESS_SIZE_8_BYTES = 3'd3,
        M64K_ACCESS_SIZE_16_BYTES = 3'd4,
        M64K_ACCESS_SIZE_32_BYTES = 3'd5,
        M64K_ACCESS_SIZE_64_BYTES = 3'd6
    } m64k_access_size_t;

    typedef enum logic [2:0] {
        M64K_MEMORY_TYPE_WRITE_BACK = 3'd0,
        M64K_MEMORY_TYPE_WRITE_THROUGH = 3'd1,
        M64K_MEMORY_TYPE_UNCACHED = 3'd2,
        M64K_MEMORY_TYPE_DEVICE = 3'd3,
        M64K_MEMORY_TYPE_STRONGLY_ORDERED = 3'd4
    } m64k_memory_type_t;

    typedef enum logic [2:0] {
        M64K_ORDER_RELAXED = 3'd0,
        M64K_ORDER_ACQUIRE = 3'd1,
        M64K_ORDER_RELEASE = 3'd2,
        M64K_ORDER_ACQUIRE_RELEASE = 3'd3,
        M64K_ORDER_SEQUENTIAL = 3'd4,
        M64K_ORDER_IO = 3'd5
    } m64k_memory_order_t;

    typedef enum logic [1:0] {
        M64K_ORDER_SCOPE_HARDWARE_THREAD = 2'd0,
        M64K_ORDER_SCOPE_CORE = 2'd1,
        M64K_ORDER_SCOPE_CLUSTER = 2'd2,
        M64K_ORDER_SCOPE_SYSTEM = 2'd3
    } m64k_order_scope_t;

    typedef enum logic [3:0] {
        M64K_ATOMIC_NONE = 4'd0,
        M64K_ATOMIC_SWAP = 4'd1,
        M64K_ATOMIC_COMPARE_EXCHANGE = 4'd2,
        M64K_ATOMIC_ADD = 4'd3,
        M64K_ATOMIC_AND = 4'd4,
        M64K_ATOMIC_OR = 4'd5,
        M64K_ATOMIC_XOR = 4'd6
    } m64k_atomic_operation_t;

    typedef enum logic [3:0] {
        M64K_COHERENCE_NONE = 4'd0,
        M64K_COHERENCE_READ_SHARED = 4'd1,
        M64K_COHERENCE_READ_UNIQUE = 4'd2,
        M64K_COHERENCE_MAKE_UNIQUE = 4'd3,
        M64K_COHERENCE_CLEAN = 4'd4,
        M64K_COHERENCE_INVALIDATE = 4'd5,
        M64K_COHERENCE_CLEAN_INVALIDATE = 4'd6,
        M64K_COHERENCE_WRITEBACK = 4'd7,
        M64K_COHERENCE_EVICT = 4'd8
    } m64k_coherence_operation_t;

    typedef enum logic [2:0] {
        M64K_COHERENCE_STATE_INVALID = 3'd0,
        M64K_COHERENCE_STATE_SHARED = 3'd1,
        M64K_COHERENCE_STATE_EXCLUSIVE = 3'd2,
        M64K_COHERENCE_STATE_MODIFIED = 3'd3
    } m64k_coherence_state_t;

    typedef enum logic [3:0] {
        M64K_MEMORY_FAULT_NONE = 4'd0,
        M64K_MEMORY_FAULT_ACCESS = 4'd1,
        M64K_MEMORY_FAULT_PAGE = 4'd2,
        M64K_MEMORY_FAULT_ALIGNMENT = 4'd3,
        M64K_MEMORY_FAULT_BUS = 4'd4,
        M64K_MEMORY_FAULT_TIMEOUT = 4'd5,
        M64K_MEMORY_FAULT_UNCORRECTABLE_ECC = 4'd6,
        M64K_MEMORY_FAULT_UNSUPPORTED = 4'd7,
        M64K_MEMORY_FAULT_PERMISSION = 4'd8,
        M64K_MEMORY_FAULT_POISON = 4'd9
    } m64k_memory_fault_t;

    typedef struct packed {
        m64k_memory_order_t ordering;
        m64k_order_scope_t ordering_scope;
    } m64k_ordering_attributes_t;

    typedef struct packed {
        m64k_coherence_operation_t operation;
        logic exclusive;
        logic allocate_in_shared_cache;
    } m64k_coherence_attributes_t;

    // A 64-byte line is transported as four independently backpressured beats.
    typedef struct packed {
        m64k_execution_context_t source_context;
        m64k_transaction_id_t transaction_id;
        m64k_memory_operation_t operation;
        m64k_access_size_t size;
        m64k_atomic_operation_t atomic_operation;
        m64k_pa_t physical_address;
        logic [1:0] beat_index;
        logic last_beat;
        logic [M64K_TRANSPORT_BEAT_BITS-1:0] write_data;
        logic [63:0] compare_data;
        logic [M64K_TRANSPORT_BEAT_BYTES-1:0] byte_enable;
        m64k_memory_type_t memory_type;
        m64k_ordering_attributes_t ordering;
        m64k_coherence_attributes_t coherence;
    } m64k_physical_memory_request_t;

    typedef struct packed {
        m64k_execution_context_t source_context;
        m64k_transaction_id_t transaction_id;
        logic [1:0] beat_index;
        logic last_beat;
        m64k_memory_fault_t fault;
        m64k_coherence_state_t coherence_state;
        logic [M64K_TRANSPORT_BEAT_BITS-1:0] read_data;
        logic atomic_success;
        logic retry;
        logic corrected_error;
        logic poisoned;
    } m64k_physical_memory_response_t;

    function automatic logic [6:0] m64k_access_size_bytes(input m64k_access_size_t size);
        return 7'(1) << size;
    endfunction

    function automatic m64k_pa_t m64k_cache_line_base(input m64k_pa_t address);
        return address & ~(m64k_pa_t'(M64K_CACHE_LINE_BYTES) - m64k_pa_t'(1));
    endfunction
endpackage
