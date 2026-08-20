interface m64k_precise_retirement_if #(
    parameter int unsigned RETIRE_LANES = 4
) (
    input logic clk,
    input logic rst_n
);
    import m64k_precise_retirement_pkg::*;

    logic [RETIRE_LANES-1:0] valid;
    m64k_precise_retirement_record_t records [RETIRE_LANES];

    generate
        for (genvar lane = 0; lane < RETIRE_LANES; lane++) begin : gen_retirement_contract_assertions
            property supported_contract_version;
                @(posedge clk) disable iff (!rst_n)
                    valid[lane] |->
                        (records[lane].contract_major == M64K_RETIRE_CONTRACT_MAJOR) &&
                        (records[lane].contract_minor <= M64K_RETIRE_CONTRACT_MINOR);
            endproperty
            assert property (supported_contract_version);

            property bounded_write_count;
                @(posedge clk) disable iff (!rst_n)
                    valid[lane] |-> records[lane].write_count <= 3'(M64K_RETIRE_MAX_WRITES);
            endproperty
            assert property (bounded_write_count);

            property bounded_instruction_length;
                @(posedge clk) disable iff (!rst_n)
                    valid[lane] |->
                        (records[lane].instruction_bytes == 5'd4) ||
                        (records[lane].instruction_bytes == 5'd8) ||
                        (records[lane].instruction_bytes == 5'd12) ||
                        (records[lane].instruction_bytes == 5'd16);
            endproperty
            assert property (bounded_instruction_length);
        end
    endgenerate

    modport producer (
        output valid,
        output records
    );

    modport observer (
        input valid,
        input records
    );
endinterface
