module mx68k_core_system_control_tb;
    import mx68k_arch_pkg::*;

    logic clk;
    logic rst_n;
    logic reset_devices_n;
    logic stopped;
    logic faulted;
    mx_exception_t terminal_exception;
    logic retire_valid;
    logic [31:0] retire_pc;
    logic [7:0] retire_instruction_id;
    logic [31:0] debug_pc;
    logic [15:0] debug_sr;
    logic [31:0] debug_usp;
    logic [31:0] debug_ssp;
    logic [8*32-1:0] debug_data_registers;
    logic [8*32-1:0] debug_address_registers;

    mx68k_mem_if imem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_mem_if dmem_bus(.clk(clk), .rst_n(rst_n));
    mx68k_irq_if irq_bus();

    assign irq_bus.request = 1'b0;
    assign irq_bus.level = 3'd0;
    assign irq_bus.vector_valid = 1'b0;
    assign irq_bus.vector = 8'd0;

    mx68k_core_m00 #(.QUEUE_WORDS(8)) core (
        .clk, .rst_n, .reset_devices_n,
        .stopped, .faulted, .terminal_exception,
        .retire_valid, .retire_pc, .retire_instruction_id,
        .debug_pc, .debug_sr, .debug_usp, .debug_ssp,
        .debug_data_registers, .debug_address_registers,
        .irq(irq_bus), .imem(imem_bus), .dmem(dmem_bus)
    );

    mx68k_ram #(.MEM_BYTES(512)) instruction_ram (
        .clk, .rst_n, .mem(imem_bus)
    );
    mx68k_ram #(.MEM_BYTES(1024)) data_ram (
        .clk, .rst_n, .mem(dmem_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer cycles;
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles > 4000)
                $fatal(1, "MX68K system-control test timed out");
        end
    end

    task automatic set_data_word(input integer address,
                                 input logic [15:0] value);
        begin
            data_ram.storage[address + 0] = value[15:8];
            data_ram.storage[address + 1] = value[7:0];
        end
    endtask

    task automatic set_data_long(input integer address,
                                 input logic [31:0] value);
        begin
            data_ram.storage[address + 0] = value[31:24];
            data_ram.storage[address + 1] = value[23:16];
            data_ram.storage[address + 2] = value[15:8];
            data_ram.storage[address + 3] = value[7:0];
        end
    endtask

    task automatic set_word(input integer address,
                            input logic [15:0] value);
        begin
            instruction_ram.storage[address + 0] = value[15:8];
            instruction_ram.storage[address + 1] = value[7:0];
        end
    endtask

    task automatic wait_retire(input logic [31:0] expected_pc);
        begin
            while (!(retire_valid && (retire_pc == expected_pc)))
                @(negedge clk);
            @(negedge clk);
        end
    endtask

    task automatic begin_case(input logic [31:0] initial_pc);
        begin
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            set_data_long(0, 32'h0000_0300);
            set_data_long(4, initial_pc);
            repeat (2) @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        repeat (2) @(negedge clk);

        // PRM 4-168: RTS reads a long PC from the active stack, advances SP
        // by four and leaves every condition code unchanged.  PRM 4-146:
        // NOP affects no state other than its sequential PC advance.
        set_data_long(16'h300, 32'h0000_0120);
        set_word(16'h100, 16'h4e75); // RTS
        set_word(16'h120, 16'h4e71); // NOP
        set_word(16'h122, 16'h4e72); // STOP #$2700
        set_word(16'h124, 16'h2700);
        begin_case(32'h0000_0100);
        wait_retire(32'h0000_0100);
        assert (debug_pc == 32'h0000_0120);
        assert (debug_ssp == 32'h0000_0304);
        assert (debug_sr == 16'h2700);
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_pc == 32'h0000_0126);

        // PRM 4-105/4-106: the architected ILLEGAL opcode takes vector 4,
        // stacks the faulting instruction address on M00 and changes no CCR.
        set_data_long(MX_VECTOR_ILLEGAL * 4, 32'h0000_0180);
        set_word(16'h140, 16'h4afc); // ILLEGAL
        set_word(16'h180, 16'h4e72); // handler: STOP #$2700
        set_word(16'h182, 16'h2700);
        begin_case(32'h0000_0140);
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2700);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0140);

        // PRM 6-83/6-84 and UM figure 6-5: M00 RTE consumes exactly the
        // six-byte SR+PC frame from SSP.  Restoring S=0 exposes the already
        // banked USP, while SSP itself advances by six.
        set_data_word(16'h300, 16'h001f);
        set_data_long(16'h302, 32'h0000_0120);
        set_data_long(MX_VECTOR_TRAP_BASE * 4, 32'h0000_0180);
        set_word(16'h100, 16'h41f8); // LEA $0200.W,A0
        set_word(16'h102, 16'h0200);
        set_word(16'h104, 16'h4e60); // MOVE A0,USP
        set_word(16'h106, 16'h4e73); // RTE -> user PC $120
        set_word(16'h120, 16'h200f); // MOVE.L A7,D0 (active USP)
        set_word(16'h122, 16'h4e40); // TRAP #0, following PC=$124
        set_word(16'h180, 16'h4e72); // handler: STOP #$2700
        set_word(16'h182, 16'h2700);
        begin_case(32'h0000_0100);
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_data_registers[0*32 +: 32] == 32'h0000_0200);
        assert (debug_usp == 32'h0000_0200);
        assert (debug_ssp == 32'h0000_0300);
        // MOVE.L A7,D0 preserves X and computes NZVC from $00000200, so the
        // subsequent TRAP stacks $0010 rather than the pre-MOVE $001f.
        assert ({data_ram.storage[10'h300], data_ram.storage[10'h301]} ==
                16'h0010);
        assert ({data_ram.storage[10'h302], data_ram.storage[10'h303],
                 data_ram.storage[10'h304], data_ram.storage[10'h305]} ==
                32'h0000_0124);

        // UM 6.3.4: trace eligibility is sampled at instruction start.  A
        // traced STOP completes, loads its immediate SR and takes vector 9
        // before any following instruction; the frame contains PC after STOP.
        set_data_long(MX_VECTOR_TRACE * 4, 32'h0000_0180);
        set_word(16'h100, 16'h46fc); // MOVE.W #$a71f,SR: enable M00 T
        set_word(16'h102, 16'ha71f);
        set_word(16'h104, 16'h4e72); // traced STOP #$2700
        set_word(16'h106, 16'h2700);
        set_word(16'h108, 16'h4afc); // must not execute before trace
        set_word(16'h180, 16'h4e72); // trace handler: STOP #$2700
        set_word(16'h182, 16'h2700);
        begin_case(32'h0000_0100);
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h2700);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0108);

        // PRM 6-83: RTE is privileged.  A user attempt takes vector 8 and
        // stacks the address of the unexecuted RTE rather than popping data.
        set_data_long(MX_VECTOR_PRIVILEGE * 4, 32'h0000_0180);
        set_word(16'h140, 16'h46fc); // MOVE.W #$001f,SR: user state
        set_word(16'h142, 16'h001f);
        set_word(16'h144, 16'h4e73); // RTE: privilege violation
        set_word(16'h180, 16'h4e72); // handler: STOP #$2700
        set_word(16'h182, 16'h2700);
        begin_case(32'h0000_0140);
        wait (stopped || faulted);
        @(negedge clk);
        assert (stopped && !faulted && !terminal_exception.valid);
        assert (debug_ssp == 32'h0000_02fa);
        assert ({data_ram.storage[10'h2fa], data_ram.storage[10'h2fb]} ==
                16'h001f);
        assert ({data_ram.storage[10'h2fc], data_ram.storage[10'h2fd],
                 data_ram.storage[10'h2fe], data_ram.storage[10'h2ff]} ==
                32'h0000_0144);

        $display("PASS: M00 NOP/RTS/ILLEGAL/RTE/STOP documented semantics");
        $finish;
    end
endmodule
