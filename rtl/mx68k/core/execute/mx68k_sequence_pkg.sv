package mx68k_sequence_pkg;
    // Architectural instructions which require more than one ordered memory
    // operand use this common sequence namespace.  It is intentionally not an
    // instruction-specific FSM: future MOVEP, CAS/CAS2 and coprocessor flows
    // add programs and reuse the same read/checkpoint/commit machinery.
    typedef enum logic [2:0] {
        MX_SEQUENCE_NONE,
        MX_SEQUENCE_CMPM
    } mx_sequence_program_t;

    typedef enum logic [2:0] {
        MX_SEQUENCE_IDLE,
        MX_SEQUENCE_READ_SOURCE,
        MX_SEQUENCE_READ_DESTINATION
    } mx_sequence_step_t;
endpackage
