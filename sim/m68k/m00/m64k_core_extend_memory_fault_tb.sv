module m64k_core_extend_memory_fault_tb;
    import m64k_pkg::*;
    import m64k_arch_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
    logic stopped;
    logic faulted;
    m64k_exception_t terminal_exception;
    logic retire_valid;
    logic [31:0] retire_pc;
    logic [7:0] retire_instruction_id;
    logic [31:0] debug_pc;
    logic [15:0] debug_sr;
    logic [31:0] debug_usp;
    logic [31:0] debug_ssp;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;
    logic [31:0] operand_bus_address [0:3];
    logic operand_bus_write [0:3];
    integer operand_bus_count;
    integer cycles;

    m64k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    m64k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    m64k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    m64k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n, .stopped, .faulted,
        .terminal_exception, .retire_valid, .retire_pc,
        .retire_instruction_id, .debug_pc, .debug_sr, .debug_usp,
        .debug_ssp, .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    m64k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    m64k_ram #(
        .MEM_BYTES(1024),
        .INJECT_FAULT_ENABLE(1'b1),
        .INJECT_FAULT_READ(1'b1),
        .INJECT_FAULT_WRITE(1'b1),
        .INJECT_FAULT_READ_ADDR(32'h0000_0200),
        .INJECT_FAULT_WRITE_ADDR(32'h0000_0220)
    ) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            operand_bus_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (dmem_bus.req_valid && dmem_bus.req_ready &&
                (dmem_bus.req.addr >= 32'h0000_01f0) &&
                (dmem_bus.req.addr < 32'h0000_0300)) begin
                operand_bus_address[operand_bus_count] <= dmem_bus.req.addr;
                operand_bus_write[operand_bus_count] <=
                    (dmem_bus.req.command == M64K_MEM_WRITE);
                operand_bus_count <= operand_bus_count + 1;
            end
            if (cycles > 5000)
                $fatal(1, "ADDX/SUBX/ABCD/SBCD fault test timed out");
        end
    end

    task automatic set_instruction_word(input integer address,
                                        input logic [15:0] value);
        instruction_ram.storage[address] = value[15:8];
        instruction_ram.storage[address + 1] = value[7:0];
    endtask

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        data_ram.storage[address] = value[31:24];
        data_ram.storage[address + 1] = value[23:16];
        data_ram.storage[address + 2] = value[15:8];
        data_ram.storage[address + 3] = value[7:0];
    endtask

    function automatic logic [31:0] operand_step(input integer size);
        case (size)
            0: return 32'd1;
            1: return 32'd2;
            default: return 32'd4;
        endcase
    endfunction

    function automatic logic [15:0] memory_opcode(
        input integer operation,
        input integer size,
        input logic [2:0] source_register,
        input logic [2:0] destination_register
    );
        logic [15:0] result;
        begin
            case (operation)
                0: result = 16'hd108; // ADDX.B -(A0),-(A0)
                1: result = 16'h9108; // SUBX.B -(A0),-(A0)
                2: result = 16'hc108; // ABCD   -(A0),-(A0)
                default: result = 16'h8108; // SBCD -(A0),-(A0)
            endcase
            result[11:9] = destination_register;
            result[2:0] = source_register;
            if (operation < 2)
                result[7:6] = size[1:0];
            return result;
        end
    endfunction

    task automatic check_group0_frame(
        input logic [15:0] expected_ssw,
        input logic [31:0] expected_address,
        input logic [15:0] expected_opcode
    );
        begin
            // MC68000UM 6.3.9.1 and figure 6-7 define this seven-word M00
            // diagnostic frame.  R/W=1 is a read, I/N=1 is an operand, and
            // FC=101 denotes supervisor data space.
            assert (stopped && !faulted && !terminal_exception.valid);
            assert (debug_pc == 32'h0000_0184);
            assert (debug_ssp == 32'h0000_0372);
            assert ({data_ram.storage[16'h372],
                     data_ram.storage[16'h373]} == expected_ssw);
            assert ({data_ram.storage[16'h374], data_ram.storage[16'h375],
                     data_ram.storage[16'h376], data_ram.storage[16'h377]} ==
                    expected_address);
            assert ({data_ram.storage[16'h378],
                     data_ram.storage[16'h379]} == expected_opcode);
            assert ({data_ram.storage[16'h37a],
                     data_ram.storage[16'h37b]} == 16'h271f);
            assert ({data_ram.storage[16'h37c], data_ram.storage[16'h37d],
                     data_ram.storage[16'h37e], data_ram.storage[16'h37f]} ==
                    32'h0000_0112);
        end
    endtask

    task automatic run_fault_case(input integer operation,
                                  input integer size,
                                  input integer fault_phase,
                                  input logic same_register);
        logic [2:0] source_register;
        logic [2:0] destination_register;
        logic [15:0] opcode;
        logic [31:0] step;
        logic [31:0] source_address;
        logic [31:0] destination_address;
        logic [31:0] source_initial;
        logic [31:0] destination_initial;
        logic [31:0] fault_address;
        logic [15:0] expected_ssw;
        integer expected_accesses;
        begin
            source_register = same_register ? 3'd2 : 3'd0;
            destination_register = same_register ? 3'd2 : 3'd1;
            step = operand_step(size);
            opcode = memory_opcode(operation, size, source_register,
                                   destination_register);

            if (same_register) begin
                case (fault_phase)
                    0: source_initial = 32'h0000_0200 + step;
                    1: source_initial = 32'h0000_0200 + (step << 1);
                    default: source_initial = 32'h0000_0220 + (step << 1);
                endcase
                destination_initial = source_initial;
                source_address = source_initial - step;
                destination_address = source_initial - (step << 1);
            end else begin
                source_address = (fault_phase == 0) ?
                    32'h0000_0200 : 32'h0000_0240;
                destination_address = (fault_phase == 1) ?
                    32'h0000_0200 : (fault_phase == 2) ?
                    32'h0000_0220 : 32'h0000_0260;
                source_initial = source_address + step;
                destination_initial = destination_address + step;
            end

            fault_address = (fault_phase == 0) ? source_address :
                            destination_address;
            expected_ssw = (fault_phase == 2) ? 16'h000d : 16'h001d;
            expected_accesses = fault_phase + 1;

            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0380);
            set_data_long(4, 32'h0000_0100);
            set_data_long(M64K_VECTOR_ACCESS_FAULT * 4, 32'h0000_0180);
            for (int stack_index = 16'h370; stack_index < 16'h380;
                 stack_index++)
                data_ram.storage[stack_index] = 8'h00;

            set_instruction_word(16'h100,
                {4'h2, source_register, 9'b001_111_100}); // MOVEA.L #,An
            set_instruction_word(16'h102, source_initial[31:16]);
            set_instruction_word(16'h104, source_initial[15:0]);
            if (!same_register) begin
                set_instruction_word(16'h106,
                    {4'h2, destination_register,
                     9'b001_111_100}); // MOVEA.L #,An
                set_instruction_word(16'h108, destination_initial[31:16]);
                set_instruction_word(16'h10a, destination_initial[15:0]);
            end else begin
                set_instruction_word(16'h106, 16'h4e71);
                set_instruction_word(16'h108, 16'h4e71);
                set_instruction_word(16'h10a, 16'h4e71);
            end
            set_instruction_word(16'h10c, 16'h44fc); // MOVE.W #$1f,CCR
            set_instruction_word(16'h10e, 16'h001f);
            set_instruction_word(16'h110, opcode);
            set_instruction_word(16'h112, 16'h4e72); // must not execute
            set_instruction_word(16'h114, 16'h2700);
            set_instruction_word(16'h180, 16'h4e72); // vector-2 handler
            set_instruction_word(16'h182, 16'h2700);

            set_data_long(source_address, 32'h1234_5678);
            set_data_long(destination_address, 32'h8765_4321);

            repeat (2) @(negedge clk);
            rst_n = 1'b1;
            wait (stopped || faulted);
            repeat (2) @(negedge clk);

            // The MC68000 frame is diagnostic and does not support restart
            // (MC68000UM 6.3.9.1).  M64K additionally makes the incomplete
            // instruction deterministic: address/CCR/memory state publishes
            // only after the final response.  A later restartable profile can
            // retain the same checkpoints in its internal replay state.
            assert (debug_address_registers[source_register*32 +: 32] ==
                    source_initial);
            if (!same_register)
                assert (debug_address_registers[
                        destination_register*32 +: 32] ==
                        destination_initial);
            assert ({data_ram.storage[destination_address],
                     data_ram.storage[destination_address + 1],
                     data_ram.storage[destination_address + 2],
                     data_ram.storage[destination_address + 3]} ==
                    32'h8765_4321);
            check_group0_frame(expected_ssw, fault_address, opcode);

            assert (operand_bus_count == expected_accesses);
            assert (operand_bus_address[0] == source_address &&
                    !operand_bus_write[0]);
            if (fault_phase > 0)
                assert (operand_bus_address[1] == destination_address &&
                        !operand_bus_write[1]);
            if (fault_phase > 1)
                assert (operand_bus_address[2] == destination_address &&
                        operand_bus_write[2]);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;

        // ADDX/SUBX cover byte, word and long.  ABCD/SBCD are byte-only.
        // Every legal operation/size is forced to fail at source read,
        // destination read and destination write, both with independent An
        // operands and the architecturally important same-An double step.
        for (int operation = 0; operation < 4; operation++) begin
            for (int size = 0; size < ((operation < 2) ? 3 : 1); size++) begin
                for (int fault_phase = 0; fault_phase < 3; fault_phase++) begin
                    run_fault_case(operation, size, fault_phase, 1'b0);
                    run_fault_case(operation, size, fault_phase, 1'b1);
                end
            end
        end

        $display("PASS: M00 ADDX/SUBX/ABCD/SBCD three-phase fault matrix");
        $finish;
    end
endmodule
