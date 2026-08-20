package m64k_shift_rotate_pkg;
    typedef enum logic [1:0] {
        M64K_SHIFT_SIZE_BYTE = 2'd0,
        M64K_SHIFT_SIZE_WORD = 2'd1,
        M64K_SHIFT_SIZE_LONG = 2'd2,
        M64K_SHIFT_SIZE_QUAD = 2'd3
    } m64k_shift_size_t;

    typedef enum logic [2:0] {
        M64K_SHIFT_ASL  = 3'd0,
        M64K_SHIFT_ASR  = 3'd1,
        M64K_SHIFT_LSL  = 3'd2,
        M64K_SHIFT_LSR  = 3'd3,
        M64K_SHIFT_ROL  = 3'd4,
        M64K_SHIFT_ROR  = 3'd5,
        M64K_SHIFT_ROXL = 3'd6,
        M64K_SHIFT_ROXR = 3'd7
    } m64k_shift_operation_t;
endpackage
