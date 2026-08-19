interface m64k_irq_if;
    // One routed interrupt channel per core. A compatibility source may leave
    // vector_valid low to request the classic M68k autovector for level 1..7.
    logic       request;
    logic [2:0] level;
    logic       vector_valid;
    logic [7:0] vector;

    // Acknowledge is a one-cycle pulse at the architectural acceptance point.
    logic       acknowledge;
    logic [2:0] acknowledged_level;

    modport source (
        output request, level, vector_valid, vector,
        input acknowledge, acknowledged_level
    );

    modport target (
        input request, level, vector_valid, vector,
        output acknowledge, acknowledged_level
    );
endinterface
