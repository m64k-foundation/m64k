package mx68k_pkg;
    localparam int unsigned MX68K_ADDR_WIDTH = 32;
    localparam int unsigned MX68K_LINE_BYTES = 16;
    localparam int unsigned MX68K_LINE_BITS  = MX68K_LINE_BYTES * 8;
    localparam int unsigned MX68K_TXN_ID_WIDTH = 4;
    localparam int unsigned MX68K_SOURCE_WIDTH = 4;

    typedef enum logic [1:0] {
        MX_MEM_READ   = 2'b00,
        MX_MEM_WRITE  = 2'b01,
        MX_MEM_ATOMIC = 2'b10,
        MX_MEM_FENCE  = 2'b11
    } mx_mem_command_t;

    typedef enum logic [2:0] {
        MX_SIZE_BYTE = 3'd0,
        MX_SIZE_WORD = 3'd1,
        MX_SIZE_LONG = 3'd2,
        MX_SIZE_QUAD = 3'd3,
        MX_SIZE_LINE = 3'd4
    } mx_mem_size_t;

    typedef enum logic [3:0] {
        MX_ATOMIC_NONE = 4'd0,
        MX_ATOMIC_SWAP = 4'd1,
        MX_ATOMIC_CAS  = 4'd2,
        MX_ATOMIC_ADD  = 4'd3,
        MX_ATOMIC_AND  = 4'd4,
        MX_ATOMIC_OR   = 4'd5,
        MX_ATOMIC_XOR  = 4'd6
    } mx_atomic_op_t;

    typedef enum logic [3:0] {
        MX_FAULT_NONE        = 4'd0,
        MX_FAULT_ACCESS      = 4'd1,
        MX_FAULT_PAGE        = 4'd2,
        MX_FAULT_ALIGNMENT   = 4'd3,
        MX_FAULT_BUS         = 4'd4,
        MX_FAULT_TIMEOUT     = 4'd5,
        MX_FAULT_ECC         = 4'd6,
        MX_FAULT_UNSUPPORTED = 4'd7
    } mx_mem_fault_t;

    typedef struct packed {
        mx_mem_command_t command;
        mx_mem_size_t size;
        mx_atomic_op_t atomic_op;
        logic [MX68K_ADDR_WIDTH-1:0] addr;
        logic [MX68K_LINE_BITS-1:0] wdata;
        logic [MX68K_LINE_BITS-1:0] compare_data;
        logic [MX68K_LINE_BYTES-1:0] wstrb;
        logic [MX68K_TXN_ID_WIDTH-1:0] txn_id;
        logic [MX68K_SOURCE_WIDTH-1:0] source;
        logic instruction;
        logic supervisor;
        logic cacheable;
        logic ordered;
        logic lock;
    } mx_mem_req_t;

    typedef struct packed {
        logic [MX68K_LINE_BITS-1:0] rdata;
        logic [MX68K_TXN_ID_WIDTH-1:0] txn_id;
        logic [MX68K_SOURCE_WIDTH-1:0] source;
        mx_mem_fault_t fault;
        logic atomic_success;
    } mx_mem_rsp_t;

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [MX68K_ADDR_WIDTH-1:0] mx68k_line_base(
        input logic [MX68K_ADDR_WIDTH-1:0] addr
    );
        return {addr[MX68K_ADDR_WIDTH-1:4], 4'b0000};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [4:0] mx68k_size_bytes(input mx_mem_size_t size);
        case (size)
            MX_SIZE_BYTE: return 5'd1;
            MX_SIZE_WORD: return 5'd2;
            MX_SIZE_LONG: return 5'd4;
            MX_SIZE_QUAD: return 5'd8;
            MX_SIZE_LINE: return 5'd16;
            default:      return 5'd0;
        endcase
    endfunction
endpackage
