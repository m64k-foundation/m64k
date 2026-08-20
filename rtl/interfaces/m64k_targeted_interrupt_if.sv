interface m64k_targeted_interrupt_if (
    input logic clk,
    input logic rst_n
);
    import m64k_native_contract_pkg::*;

    logic interrupt_valid;
    logic interrupt_ready;
    m64k_targeted_interrupt_t interrupt;

    logic completion_valid;
    logic completion_ready;
    m64k_interrupt_completion_t completion;

    property interrupt_remains_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            interrupt_valid && !interrupt_ready |=> interrupt_valid && $stable(interrupt);
    endproperty
    assert property (interrupt_remains_stable_while_blocked);

    property completion_remains_stable_while_blocked;
        @(posedge clk) disable iff (!rst_n)
            completion_valid && !completion_ready |=> completion_valid && $stable(completion);
    endproperty
    assert property (completion_remains_stable_while_blocked);

    modport controller (
        output interrupt_valid,
        output interrupt,
        input interrupt_ready,
        input completion_valid,
        input completion,
        output completion_ready
    );

    modport target (
        input interrupt_valid,
        input interrupt,
        output interrupt_ready,
        output completion_valid,
        output completion,
        input completion_ready
    );

    modport monitor (
        input interrupt_valid,
        input interrupt_ready,
        input interrupt,
        input completion_valid,
        input completion_ready,
        input completion
    );
endinterface
