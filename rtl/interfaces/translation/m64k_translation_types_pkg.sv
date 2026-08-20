package m64k_translation_types_pkg;
    import m64k_arch_types_pkg::*;
    import m64k_memory_types_pkg::*;

    // ASID and privilege terminate at translation. The physical fabric does
    // not carry metadata which has no physical consumer.
    typedef struct packed {
        m64k_execution_context_t execution_context;
        m64k_transaction_id_t transaction_id;
        m64k_asid_t asid;
        m64k_privilege_t privilege;
        m64k_memory_operation_t operation;
        m64k_access_size_t size;
        m64k_atomic_operation_t atomic_operation;
        m64k_va_t virtual_address;
        m64k_ordering_attributes_t ordering;
    } m64k_virtual_memory_request_t;

    typedef struct packed {
        m64k_execution_context_t execution_context;
        m64k_transaction_id_t transaction_id;
        m64k_pa_t physical_address;
        m64k_memory_type_t memory_type;
        logic readable;
        logic writable;
        logic executable;
        logic coherent;
        m64k_memory_fault_t fault;
    } m64k_translation_response_t;
endpackage
