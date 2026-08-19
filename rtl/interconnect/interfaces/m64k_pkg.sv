package m64k_pkg;
    localparam int unsigned M64K_ADDR_WIDTH = 32;
    localparam int unsigned M64K_LINE_BYTES = 16;
    localparam int unsigned M64K_LINE_BITS  = M64K_LINE_BYTES * 8;
    localparam int unsigned M64K_TXN_ID_WIDTH = 4;
    localparam int unsigned M64K_SOURCE_WIDTH = 4;

    typedef enum logic [1:0] {
        M64K_MEM_READ   = 2'b00,
        M64K_MEM_WRITE  = 2'b01,
        M64K_MEM_ATOMIC = 2'b10,
        M64K_MEM_FENCE  = 2'b11
    } m64k_mem_command_t;

    typedef enum logic [2:0] {
        M64K_SIZE_BYTE = 3'd0,
        M64K_SIZE_WORD = 3'd1,
        M64K_SIZE_LONG = 3'd2,
        M64K_SIZE_QUAD = 3'd3,
        M64K_SIZE_LINE = 3'd4
    } m64k_mem_size_t;

    typedef enum logic [3:0] {
        M64K_ATOMIC_NONE = 4'd0,
        M64K_ATOMIC_SWAP = 4'd1,
        M64K_ATOMIC_CAS  = 4'd2,
        M64K_ATOMIC_ADD  = 4'd3,
        M64K_ATOMIC_AND  = 4'd4,
        M64K_ATOMIC_OR   = 4'd5,
        M64K_ATOMIC_XOR  = 4'd6
    } m64k_atomic_op_t;

    typedef enum logic [3:0] {
        M64K_FAULT_NONE        = 4'd0,
        M64K_FAULT_ACCESS      = 4'd1,
        M64K_FAULT_PAGE        = 4'd2,
        M64K_FAULT_ALIGNMENT   = 4'd3,
        M64K_FAULT_BUS         = 4'd4,
        M64K_FAULT_TIMEOUT     = 4'd5,
        M64K_FAULT_ECC         = 4'd6,
        M64K_FAULT_UNSUPPORTED = 4'd7
    } m64k_mem_fault_t;

    typedef struct packed {
        m64k_mem_command_t command;
        m64k_mem_size_t size;
        m64k_atomic_op_t atomic_op;
        logic [M64K_ADDR_WIDTH-1:0] addr;
        logic [M64K_LINE_BITS-1:0] wdata;
        logic [M64K_LINE_BITS-1:0] compare_data;
        logic [M64K_LINE_BYTES-1:0] wstrb;
        logic [M64K_TXN_ID_WIDTH-1:0] txn_id;
        logic [M64K_SOURCE_WIDTH-1:0] source;
        logic instruction;
        logic supervisor;
        logic cacheable;
        logic ordered;
        logic lock;
    } m64k_mem_req_t;

    typedef struct packed {
        logic [M64K_LINE_BITS-1:0] rdata;
        logic [M64K_TXN_ID_WIDTH-1:0] txn_id;
        logic [M64K_SOURCE_WIDTH-1:0] source;
        m64k_mem_fault_t fault;
        logic atomic_success;
    } m64k_mem_rsp_t;

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [M64K_ADDR_WIDTH-1:0] m64k_line_base(
        input logic [M64K_ADDR_WIDTH-1:0] addr
    );
        return {addr[M64K_ADDR_WIDTH-1:4], 4'b0000};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [4:0] m64k_size_bytes(input m64k_mem_size_t size);
        case (size)
            M64K_SIZE_BYTE: return 5'd1;
            M64K_SIZE_WORD: return 5'd2;
            M64K_SIZE_LONG: return 5'd4;
            M64K_SIZE_QUAD: return 5'd8;
            M64K_SIZE_LINE: return 5'd16;
            default:      return 5'd0;
        endcase
    endfunction
endpackage
