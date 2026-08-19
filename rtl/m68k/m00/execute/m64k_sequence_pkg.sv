package m64k_sequence_pkg;
    // Architectural instructions which require more than one ordered memory
    // operand use this common sequence namespace.  It is intentionally not an
    // instruction-specific FSM: future MOVEP, CAS/CAS2 and coprocessor flows
    // add programs and reuse the same read/checkpoint/commit machinery.
    typedef enum logic [2:0] {
        M64K_SEQUENCE_NONE,
        M64K_SEQUENCE_CMPM
    } m64k_sequence_program_t;

    typedef enum logic [2:0] {
        M64K_SEQUENCE_IDLE,
        M64K_SEQUENCE_READ_SOURCE,
        M64K_SEQUENCE_READ_DESTINATION
    } m64k_sequence_step_t;
endpackage
