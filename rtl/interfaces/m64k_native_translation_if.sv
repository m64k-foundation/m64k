interface m64k_native_translation_if (
    input logic clk,
    input logic rst_n
);
    import m64k_native_contract_pkg::*;

    logic request_valid;
    logic request_ready;
    m64k_virtual_memory_request_t request;
    logic response_valid;
    logic response_ready;
    m64k_translation_response_t response;

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

    modport requester (
        output request_valid,
        output request,
        input request_ready,
        input response_valid,
        input response,
        output response_ready
    );

    modport translator (
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
