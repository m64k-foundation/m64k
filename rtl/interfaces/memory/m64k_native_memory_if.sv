interface m64k_native_memory_if (
    input logic clk,
    input logic rst_n
);
    import m64k_memory_types_pkg::*;

    logic request_valid;
    logic request_ready;
    m64k_physical_memory_request_t request;

    logic response_valid;
    logic response_ready;
    m64k_physical_memory_response_t response;

    property request_remains_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            request_valid && !request_ready |=> request_valid && $stable(request);
    endproperty
    assert property (request_remains_stable_while_blocked);

    property response_remains_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            response_valid && !response_ready |=> response_valid && $stable(response);
    endproperty
    assert property (response_remains_stable_while_blocked);

    property compare_exchange_is_at_most_64_bits;
        @(posedge clk) disable iff (!rst_n)
            request_valid && (request.atomic_operation == M64K_ATOMIC_COMPARE_EXCHANGE) |->
                request.size <= M64K_ACCESS_SIZE_8_BYTES;
    endproperty
    assert property (compare_exchange_is_at_most_64_bits);

    modport requester (
        output request_valid,
        output request,
        input request_ready,
        input response_valid,
        input response,
        output response_ready
    );

    modport responder (
        input request_valid,
        input request,
        output request_ready,
        output response_valid,
        output response,
        input response_ready
    );

    modport monitor (
        input request_valid,
        input request_ready,
        input request,
        input response_valid,
        input response_ready,
        input response
    );
endinterface
