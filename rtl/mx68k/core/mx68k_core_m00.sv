module mx68k_core_m00 #(
    parameter logic [3:0] INSTRUCTION_SOURCE_ID = 4'd0,
    parameter logic [3:0] DATA_SOURCE_ID = 4'd1,
    parameter int unsigned QUEUE_WORDS = 16
) (
    input logic clk,
    input logic rst_n,

    // MC68000 RESET instruction output.  This is distinct from rst_n: it
    // resets external devices without resetting the processor itself.
    output logic reset_devices_n,
    output logic stopped,
    output logic faulted,
    output mx68k_arch_pkg::mx_exception_t terminal_exception,

    output logic retire_valid,
    output logic [31:0] retire_pc,
    output logic [7:0] retire_instruction_id,

    output logic [31:0] debug_pc,
    output logic [15:0] debug_sr,
    output logic [31:0] debug_usp,
    output logic [31:0] debug_ssp,
    output logic [8*32-1:0] debug_data_registers,
    output logic [8*32-1:0] debug_address_registers,

    mx68k_irq_if.target irq,
    mx68k_mem_if.master imem,
    mx68k_mem_if.master dmem
);
    import mx68k_pkg::*;
    import mx68k_arch_pkg::*;
    import mx68k_ea_pkg::*;
    import mx68k_uop_pkg::*;
    import mx68k_sequence_pkg::*;

    typedef enum logic [4:0] {
        MEMORY_ACTION_NONE,
        MEMORY_ACTION_MOVE_STORE,
        MEMORY_ACTION_CLEAR_STORE,
        MEMORY_ACTION_TEST_LOAD,
        MEMORY_ACTION_JSR_PUSH,
        MEMORY_ACTION_RTS_POP,
        MEMORY_ACTION_PEA_PUSH,
        MEMORY_ACTION_MOVE_LOAD,
        MEMORY_ACTION_ALU_LOAD,
        MEMORY_ACTION_MOVE_LOAD_TO_STORE,
        MEMORY_ACTION_MOVEM_STORE,
        MEMORY_ACTION_MOVEM_LOAD,
        MEMORY_ACTION_LINK_PUSH,
        MEMORY_ACTION_UNLINK_POP,
        MEMORY_ACTION_RMW_LOAD,
        MEMORY_ACTION_RMW_STORE,
        MEMORY_ACTION_BIT_TEST_LOAD,
        MEMORY_ACTION_EXCEPTION_PUSH_PC,
        MEMORY_ACTION_EXCEPTION_PUSH_SR,
        MEMORY_ACTION_EXCEPTION_PUSH_IR,
        MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
        MEMORY_ACTION_EXCEPTION_PUSH_SSW,
        MEMORY_ACTION_EXCEPTION_VECTOR_READ,
        MEMORY_ACTION_RTE_LOAD_SR,
        MEMORY_ACTION_RTE_LOAD_PC,
        MEMORY_ACTION_RTR_LOAD_CCR,
        MEMORY_ACTION_RTR_LOAD_PC,
        MEMORY_ACTION_EXTEND_SOURCE_LOAD,
        MEMORY_ACTION_EXTEND_DESTINATION_LOAD,
        MEMORY_ACTION_ATOMIC,
        MEMORY_ACTION_SEQUENCE_READ
    } memory_action_t;

    typedef enum logic [3:0] {
        CORE_RESET_SEND,
        CORE_RESET_WAIT,
        CORE_START_FRONTEND,
        CORE_RUN,
        CORE_DATA_SEND,
        CORE_DATA_WAIT,
        CORE_DIVIDE_WAIT,
        CORE_RESET_DEVICES,
        CORE_STOPPED,
        CORE_FAULTED
    } core_state_t;

    core_state_t state_q;
    mx_exception_t terminal_exception_q;
    logic redirect_pending_q;
    logic [31:0] redirect_target_q;
    mx_uop_t pending_memory_uop_q;
    memory_action_t pending_memory_action_q;
    logic [31:0] pending_memory_address_q;
    logic [31:0] pending_memory_write_value_q;
    logic [31:0] pending_control_target_q;
    logic pending_address_update_q;
    logic [2:0] pending_address_update_index_q;
    logic [31:0] pending_address_update_value_q;
    logic [31:0] pending_destination_original_q;
    logic [31:0] pending_source_operand_q;
    logic [31:0] pending_second_address_q;
    logic pending_address_update_b_q;
    logic [2:0] pending_address_update_index_b_q;
    logic [31:0] pending_address_update_value_b_q;
    logic [15:0] pending_movem_mask_q;
    logic [3:0] pending_movem_bit_q;
    mx_exception_t pending_exception_q;
    logic [15:0] pending_exception_sr_q;
    logic [2:0] pending_interrupt_level_q;
    logic interrupt_ack_q;
    logic [2:0] interrupt_ack_level_q;
    logic interrupt_level7_seen_q;
    logic interrupt_level7_pending_q;
    logic trace_pending_q;
    logic [31:0] trace_pending_pc_q;
    logic [15:0] trace_pending_sr_q;
    logic pending_instruction_trace_q;
    logic trace_after_exception_q;
    logic [6:0] reset_devices_cycles_q;

    logic instruction_valid;
    logic instruction_ready;
    logic [$clog2(QUEUE_WORDS+1)-1:0] instruction_words;
    mx_uop_t instruction_uop;
    mx_exception_t instruction_exception;
    logic frontend_redirect_valid;
    logic [31:0] frontend_redirect_pc;

    mx_mem_req_t reset_request;
    mx_mem_req_t data_request;
    logic reset_response_ids_match;
    mx_mem_fault_t reset_response_fault;
    logic reset_response_handshake;
    logic [31:0] reset_ssp;
    logic [31:0] reset_pc;
    logic data_response_ids_match;
    mx_mem_fault_t data_response_fault;
    logic data_response_handshake;
    logic data_response_completes_access;
    logic data_request_splits_long;
    logic split_access_second_q;
    logic [15:0] split_read_high_q;
    logic [31:0] split_base_address_q;
    logic [4:0] data_request_operand_bytes;
    logic [31:0] data_request_write_value;
    logic [31:0] data_response_beat_value;
    logic [31:0] completed_memory_address;

    logic rf_boot_valid;
    logic rf_commit_valid;
    logic rf_data_write_enable;
    logic [2:0] rf_data_write_index;
    logic [31:0] rf_data_write_value;
    logic rf_data_write_enable_b;
    logic [2:0] rf_data_write_index_b;
    logic [31:0] rf_data_write_value_b;
    logic rf_address_write_enable;
    logic [2:0] rf_address_write_index;
    logic [31:0] rf_address_write_value;
    logic rf_address_write_enable_b;
    logic [2:0] rf_address_write_index_b;
    logic [31:0] rf_address_write_value_b;
    logic rf_sr_write_enable;
    logic [15:0] rf_sr_write_value;
    logic rf_pc_write_enable;
    logic [31:0] rf_pc_write_value;
    logic rf_usp_write_enable;
    logic [31:0] rf_usp_write_value;
    logic rf_ssp_write_enable;
    logic [31:0] rf_ssp_write_value;
    logic [31:0] rf_data_read_a;
    logic [31:0] rf_data_read_b;
    logic [31:0] rf_address_read_a;
    logic [31:0] rf_address_read_b;

    logic instruction_handshake;
    logic branch_taken;
    logic dbcc_condition_false;
    logic dbcc_taken;
    mx_condition_flags_t condition_flags;
    logic execute_supported;
    logic privilege_fault;
    logic successful_uop;
    logic direct_commit_valid;
    logic data_commit_valid;
    logic exception_entry_commit_valid;
    logic rte_commit_valid;
    logic rtr_commit_valid;
    logic reset_instruction_commit_valid;
    logic trap_taken;
    logic [15:0] move_sr;
    logic [15:0] direct_sr_value;
    logic [15:0] data_sr_value;
    logic starts_memory_sequence;
    logic [31:0] source_operand_value;
    logic [31:0] destination_operand_value;
    logic [31:0] alu_source_value;
    mx_operand_size_t alu_operation_size;
    logic [31:0] data_alu_source_value;
    mx_operand_size_t data_alu_operation_size;
    logic [31:0] direct_result_value;
    logic [5:0] shift_count;
    logic memory_shift_active;
    logic [31:0] shift_operand;
    mx_operand_size_t shift_operation_size;
    logic [5:0] shift_operation_count;
    logic shift_direction_left;
    logic [1:0] shift_kind;
    mx_alu_result_t shift_result;
    mx_alu_result_t direct_add_extend_result;
    mx_alu_result_t direct_subtract_extend_result;
    mx_alu_result_t data_add_extend_result;
    mx_alu_result_t data_subtract_extend_result;
    mx_alu_result_t rmw_add_extend_result;
    mx_alu_result_t rmw_subtract_extend_result;
    logic divider_start;
    logic divider_busy;
    logic divider_done;
    logic [31:0] divider_result;
    logic divider_divide_by_zero;
    logic divider_overflow;
    logic divider_n;
    logic divider_z;
    logic divide_commit_valid;
    mx_sequence_program_t sequence_program_q;
    mx_sequence_step_t sequence_step_q;
    logic sequence_checkpoint_commit_valid;
    logic [2:0] sequence_checkpoint_index_q;
    logic [31:0] sequence_checkpoint_value_q;
    logic [31:0] source_ea_address;
    logic [31:0] destination_ea_address;
    logic [31:0] sequence_source_step;
    logic [31:0] sequence_destination_step;
    logic [31:0] data_response_value;
    logic [31:0] data_writeback_value;
    logic [31:0] rmw_result_value;
    logic [4:0] direct_bit_index;
    logic [2:0] memory_bit_index;
    logic [4:0] pending_operand_bytes;
    logic pending_request_is_write;
    logic pending_writes_flags;
    logic direct_writes_flags;
    logic direct_writes_sr;
    logic [15:0] movem_remaining_mask;
    logic [3:0] movem_next_bit;
    logic movem_final_transfer;
    logic movem_load_write_valid;
    logic interrupt_level7_active;
    logic interrupt_level7_rise;
    logic [2:0] active_interrupt_level;
    logic interrupt_take;
    logic [7:0] accepted_interrupt_vector;
    logic [15:0] exception_entry_sr;
    logic direct_chk_trap;
    logic data_chk_trap;
    logic [15:0] direct_chk_sr;
    logic [15:0] data_chk_sr;
    logic chk_operand_commit_valid;

    // Keep the shift/rotate datapath outside the core control cone.  The
    // dedicated unit is a bounded-depth barrel implementation; it replaces
    // the former 64-step combinational loop without changing M00 flags.
    mx68k_shifter shifter (
        .operand(shift_operand),
        .size(shift_operation_size),
        .count(shift_operation_count),
        .direction_left(shift_direction_left),
        .shift_kind(shift_kind),
        .old_extend(debug_sr[MX_SR_X]),
        .shift_result
    );

    mx68k_divider divider (
        .clk,
        .rst_n,
        .start(divider_start),
        .dividend((state_q == CORE_RUN) ? destination_operand_value :
                                             pending_destination_original_q),
        .divisor((state_q == CORE_RUN) ? source_operand_value[15:0] :
                                          data_response_value[15:0]),
        .signed_operation((state_q == CORE_RUN) ?
                          instruction_uop.condition[0] :
                          pending_memory_uop_q.condition[0]),
        .busy(divider_busy),
        .done(divider_done),
        .result(divider_result),
        .divide_by_zero(divider_divide_by_zero),
        .overflow(divider_overflow),
        .n(divider_n),
        .z(divider_z)
    );
    logic pending_exception_special;
    logic pending_action_is_exception_frame;
    logic data_request_alignment_error;

    logic [31:0] perf_line_requests;
    logic [31:0] perf_stale_responses;
    logic [31:0] perf_words_delivered;
    logic [31:0] perf_redirects;
    logic [31:0] perf_instructions_decoded;

    function automatic mx_exception_t make_terminal_exception(
        input logic [7:0] vector,
        input mx_exception_class_t exception_class,
        input mx_fault_stage_t stage,
        input logic [31:0] instruction_pc,
        input logic [31:0] next_pc
    );
        mx_exception_t value;
        begin
            value = '0;
            value.valid = 1'b1;
            value.vector = vector;
            value.exception_class = exception_class;
            value.stage = stage;
            value.instruction_pc = instruction_pc;
            value.next_pc = next_pc;
            value.instruction = 1'b1;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_data_exception(
        input mx_mem_fault_t fault,
        input mx_uop_t faulting_uop,
        input logic [31:0] fault_address,
        input logic fault_write,
        input logic supervisor
    );
        mx_exception_t value;
        begin
            value = make_terminal_exception(
                (fault == MX_FAULT_ALIGNMENT) ? MX_VECTOR_ADDRESS_ERROR :
                                                MX_VECTOR_ACCESS_FAULT,
                MX_EXC_DATA, MX_FAULT_STAGE_MEMORY,
                faulting_uop.instruction_pc, faulting_uop.sequential_pc);
            value.logical_address = fault_address;
            value.physical_address = fault_address;
            value.opcode = faulting_uop.instruction_word;
            value.operand_size = faulting_uop.size;
            value.function_code = mx_m00_function_code(
                supervisor, 1'b0);
            value.special_status = mx_m00_special_status_word(
                fault_write, 1'b0, supervisor);
            value.write = fault_write;
            value.instruction = 1'b0;
            value.rerunnable = 1'b0;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_m00_fetch_exception(
        input mx_exception_t original,
        input logic supervisor
    );
        mx_exception_t value;
        begin
            value = original;
            value.physical_address = original.logical_address;
            value.function_code = mx_m00_function_code(
                supervisor, 1'b1);
            value.special_status = mx_m00_special_status_word(
                1'b0, 1'b1, supervisor);
            value.write = 1'b0;
            value.instruction = 1'b1;
            value.rerunnable = 1'b0;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_execute_exception(
        input logic [7:0] vector,
        input mx_uop_t faulting_uop
    );
        mx_exception_t value;
        begin
            value = make_terminal_exception(
                vector, MX_EXC_EXECUTE, MX_FAULT_STAGE_EXECUTE,
                faulting_uop.instruction_pc, faulting_uop.sequential_pc);
            value.opcode = faulting_uop.instruction_word;
            value.operand_size = faulting_uop.size;
            value.rerunnable = 1'b0;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_interrupt_exception(
        input logic [7:0] vector,
        input logic [31:0] pc
    );
        mx_exception_t value;
        begin
            value = make_terminal_exception(
                vector, MX_EXC_INTERRUPT, MX_FAULT_STAGE_COMMIT, pc, pc);
            value.instruction = 1'b0;
            value.rerunnable = 1'b1;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_instruction_trap_exception(
        input logic [7:0] vector,
        input mx_uop_t trapping_uop
    );
        mx_exception_t value;
        begin
            value = make_execute_exception(vector, trapping_uop);
            value.exception_class = MX_EXC_TRAP;
            value.rerunnable = 1'b0;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_trace_exception(
        input logic [31:0] pc
    );
        mx_exception_t value;
        begin
            value = make_terminal_exception(
                MX_VECTOR_TRACE, MX_EXC_TRACE, MX_FAULT_STAGE_COMMIT, pc, pc);
            value.instruction = 1'b0;
            value.rerunnable = 1'b1;
            return value;
        end
    endfunction

    function automatic mx_exception_t make_frame_exception(
        input mx_exception_t original,
        input logic [31:0] fault_address
    );
        mx_exception_t value;
        begin
            value = original;
            value.valid = 1'b1;
            value.exception_class = MX_EXC_DOUBLE_FAULT;
            value.stage = MX_FAULT_STAGE_FRAME;
            value.logical_address = fault_address;
            value.physical_address = fault_address;
            value.rerunnable = 1'b0;
            return value;
        end
    endfunction

    mx68k_decode_frontend #(
        .SOURCE_ID(INSTRUCTION_SOURCE_ID),
        .QUEUE_WORDS(QUEUE_WORDS)
    ) frontend (
        .clk, .rst_n,
        .redirect_valid(frontend_redirect_valid),
        .redirect_pc(frontend_redirect_pc),
        .supervisor(debug_sr[MX_SR_S]),
        .profile(MX_PROFILE_M00),
        .instruction_valid, .instruction_ready, .instruction_words,
        .instruction_uop, .instruction_exception,
        .perf_line_requests, .perf_stale_responses,
        .perf_words_delivered, .perf_redirects,
        .perf_instructions_decoded,
        .mem(imem)
    );

    mx68k_register_file registers (
        .clk, .rst_n,
        .profile(MX_PROFILE_M00),
        // Some encodings (for example ADD.L D6,(A2)) have a register
        // source and an unrelated destination EA.  In that case source_ea is
        // intentionally empty; source_a is the architectural register
        // reference that must select the read port.
        .data_read_index_a(
            (instruction_uop.source_a.kind == MX_OPERAND_DATA_REGISTER) ?
            instruction_uop.source_a.index[2:0] :
            instruction_uop.source_ea.register_index),
        .data_read_index_b(instruction_uop.destination_ea.register_index),
        .data_read_value_a(rf_data_read_a),
        .data_read_value_b(rf_data_read_b),
        .address_read_index_a(
            (instruction_uop.source_a.kind == MX_OPERAND_ADDRESS_REGISTER) ?
            instruction_uop.source_a.index[2:0] :
            instruction_uop.source_ea.register_index),
        .address_read_index_b(
            (instruction_uop.destination.kind ==
             MX_OPERAND_ADDRESS_REGISTER) ?
            instruction_uop.destination.index[2:0] :
            instruction_uop.destination_ea.register_index),
        .address_read_value_a(rf_address_read_a),
        .address_read_value_b(rf_address_read_b),
        .boot_valid(rf_boot_valid),
        .boot_ssp(reset_ssp),
        .boot_pc(reset_pc),
        .commit_valid(rf_commit_valid),
        .data_write_enable(rf_data_write_enable),
        .data_write_index(rf_data_write_index),
        .data_write_value(rf_data_write_value),
        .data_write_enable_b(rf_data_write_enable_b),
        .data_write_index_b(rf_data_write_index_b),
        .data_write_value_b(rf_data_write_value_b),
        .address_write_enable(rf_address_write_enable),
        .address_write_index(rf_address_write_index),
        .address_write_value(rf_address_write_value),
        .address_write_enable_b(rf_address_write_enable_b),
        .address_write_index_b(rf_address_write_index_b),
        .address_write_value_b(rf_address_write_value_b),
        .sr_write_enable(rf_sr_write_enable),
        .sr_write_value(rf_sr_write_value),
        .pc_write_enable(rf_pc_write_enable),
        .pc_write_value(rf_pc_write_value),
        .usp_write_enable(rf_usp_write_enable),
        .usp_write_value(rf_usp_write_value),
        .ssp_write_enable(rf_ssp_write_enable),
        .ssp_write_value(rf_ssp_write_value),
        .sr(debug_sr),
        .pc(debug_pc),
        .usp(debug_usp),
        .ssp(debug_ssp),
        .debug_data_registers,
        .debug_address_registers
    );

    function automatic logic [31:0] packed_register_value(
        input logic [8*32-1:0] packed_registers,
        input logic [2:0] index
    );
        return packed_registers[index*32 +: 32];
    endfunction

    function automatic logic [3:0] first_set_bit(
        input logic [15:0] mask
    );
        logic found;
        begin
            first_set_bit = 4'd0;
            found = 1'b0;
            for (int bit_index = 0; bit_index < 16; bit_index++) begin
                if (!found && mask[bit_index]) begin
                    first_set_bit = bit_index[3:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    function automatic logic [4:0] register_mask_count(
        input logic [15:0] mask
    );
        logic [4:0] count;
        begin
            count = 5'd0;
            for (int bit_index = 0; bit_index < 16; bit_index++)
                count = count + {4'd0, mask[bit_index]};
            return count;
        end
    endfunction

    function automatic logic [31:0] movem_register_value(
        input logic [3:0] mask_bit,
        input logic reversed_order,
        input logic [8*32-1:0] data_registers,
        input logic [8*32-1:0] address_registers
    );
        logic [3:0] architectural_index;
        begin
            architectural_index = reversed_order ?
                                    (4'd15 - mask_bit) : mask_bit;
            if (architectural_index < 4'd8)
                return packed_register_value(data_registers,
                                             architectural_index[2:0]);
            return packed_register_value(address_registers,
                                         architectural_index[2:0]);
        end
    endfunction

    function automatic mx_mem_size_t memory_size_for_operand(
        input mx_operand_size_t size
    );
        case (size)
            MX_OP_BYTE: return MX_SIZE_BYTE;
            MX_OP_WORD: return MX_SIZE_WORD;
            default: return MX_SIZE_LONG;
        endcase
    endfunction

    function automatic logic [31:0] merge_data_register(
        input logic [31:0] original,
        input logic [31:0] value,
        input mx_operand_size_t size
    );
        case (size)
            MX_OP_BYTE: return {original[31:8], value[7:0]};
            MX_OP_WORD: return {original[31:16], value[15:0]};
            default: return value;
        endcase
    endfunction

    function automatic logic chk_word_out_of_bounds(
        input logic [31:0] register_value,
        input logic [31:0] upper_bound
    );
        logic signed [15:0] checked;
        logic signed [15:0] bound;
        begin
            checked = register_value[15:0];
            bound = upper_bound[15:0];
            return (checked < 16'sd0) || (checked > bound);
        end
    endfunction

    function automatic logic [15:0] chk_word_result_sr(
        input logic [15:0] old_sr,
        input logic [31:0] register_value,
        input logic [31:0] upper_bound
    );
        logic [15:0] value;
        logic signed [15:0] checked;
        logic signed [15:0] bound;
        begin
            value = old_sr;
            checked = register_value[15:0];
            bound = upper_bound[15:0];
            if (checked < 16'sd0)
                value[MX_SR_N] = 1'b1;
            else if (checked > bound)
                value[MX_SR_N] = 1'b0;
            // N is architecturally undefined when the value is in range; the
            // implementation preserves it. X/Z/V/C are always unaffected or
            // undefined and are likewise preserved deterministically.
            return value;
        end
    endfunction

    function automatic logic [15:0] logical_result_sr(
        input logic [15:0] old_sr,
        input logic [31:0] result,
        input mx_operand_size_t size
    );
        logic [15:0] value;
        begin
            value = old_sr;
            case (size)
                MX_OP_BYTE: begin
                    value[MX_SR_N] = result[7];
                    value[MX_SR_Z] = (result[7:0] == 8'd0);
                end
                MX_OP_WORD: begin
                    value[MX_SR_N] = result[15];
                    value[MX_SR_Z] = (result[15:0] == 16'd0);
                end
                default: begin
                    value[MX_SR_N] = result[31];
                    value[MX_SR_Z] = (result == 32'd0);
                end
            endcase
            value[MX_SR_V] = 1'b0;
            value[MX_SR_C] = 1'b0;
            return value;
        end
    endfunction

    function automatic logic [15:0] add_result_sr(
        input logic [15:0] old_sr,
        input logic [31:0] destination_value,
        input logic [31:0] source_value,
        input mx_operand_size_t size
    );
        logic [15:0] value;
        logic [8:0] sum_byte;
        logic [16:0] sum_word;
        logic [32:0] sum_long;
        logic sign_destination;
        logic sign_source;
        logic sign_result;
        begin
            value = old_sr;
            sum_byte = {1'b0, destination_value[7:0]} +
                       {1'b0, source_value[7:0]};
            sum_word = {1'b0, destination_value[15:0]} +
                       {1'b0, source_value[15:0]};
            sum_long = {1'b0, destination_value} + {1'b0, source_value};
            case (size)
                MX_OP_BYTE: begin
                    value[MX_SR_N] = sum_byte[7];
                    value[MX_SR_Z] = (sum_byte[7:0] == 8'd0);
                    value[MX_SR_C] = sum_byte[8];
                    sign_destination = destination_value[7];
                    sign_source = source_value[7];
                    sign_result = sum_byte[7];
                end
                MX_OP_WORD: begin
                    value[MX_SR_N] = sum_word[15];
                    value[MX_SR_Z] = (sum_word[15:0] == 16'd0);
                    value[MX_SR_C] = sum_word[16];
                    sign_destination = destination_value[15];
                    sign_source = source_value[15];
                    sign_result = sum_word[15];
                end
                default: begin
                    value[MX_SR_N] = sum_long[31];
                    value[MX_SR_Z] = (sum_long[31:0] == 32'd0);
                    value[MX_SR_C] = sum_long[32];
                    sign_destination = destination_value[31];
                    sign_source = source_value[31];
                    sign_result = sum_long[31];
                end
            endcase
            value[MX_SR_V] = !(sign_destination ^ sign_source) &&
                             (sign_result ^ sign_destination);
            value[MX_SR_X] = value[MX_SR_C];
            return value;
        end
    endfunction

    function automatic logic [15:0] subtract_result_sr(
        input logic [15:0] old_sr,
        input logic [31:0] destination_value,
        input logic [31:0] source_value,
        input mx_operand_size_t size
    );
        logic [15:0] value;
        logic [31:0] result;
        logic sign_destination;
        logic sign_source;
        logic sign_result;
        begin
            value = old_sr;
            result = destination_value - source_value;
            case (size)
                MX_OP_BYTE: begin
                    value[MX_SR_N] = result[7];
                    value[MX_SR_Z] = (result[7:0] == 8'd0);
                    value[MX_SR_C] = source_value[7:0] >
                                     destination_value[7:0];
                    sign_destination = destination_value[7];
                    sign_source = source_value[7];
                    sign_result = result[7];
                end
                MX_OP_WORD: begin
                    value[MX_SR_N] = result[15];
                    value[MX_SR_Z] = (result[15:0] == 16'd0);
                    value[MX_SR_C] = source_value[15:0] >
                                     destination_value[15:0];
                    sign_destination = destination_value[15];
                    sign_source = source_value[15];
                    sign_result = result[15];
                end
                default: begin
                    value[MX_SR_N] = result[31];
                    value[MX_SR_Z] = (result == 32'd0);
                    value[MX_SR_C] = source_value > destination_value;
                    sign_destination = destination_value[31];
                    sign_source = source_value[31];
                    sign_result = result[31];
                end
            endcase
            value[MX_SR_V] = (sign_destination ^ sign_source) &&
                             (sign_result ^ sign_destination);
            value[MX_SR_X] = value[MX_SR_C];
            return value;
        end
    endfunction

    function automatic logic [15:0] extend_arithmetic_result_sr(
        input logic [15:0] old_sr,
        input mx_alu_result_t result
    );
        logic [15:0] value;
        begin
            value = old_sr;
            value[MX_SR_X] = result.flags.x;
            value[MX_SR_N] = result.flags.n;
            value[MX_SR_Z] = result.flags.z;
            value[MX_SR_V] = result.flags.v;
            value[MX_SR_C] = result.flags.c;
            return value;
        end
    endfunction

    function automatic logic [15:0] decimal_arithmetic_result_sr(
        input logic [15:0] old_sr,
        input mx_alu_result_t result
    );
        logic [15:0] value;
        begin
            // ABCD/SBCD leave N and V undefined.  Keeping the old values is a
            // deterministic implementation choice; software cannot rely on
            // them.  X/Z/C follow the PRM definitions.
            value = old_sr;
            value[MX_SR_X] = result.flags.x;
            value[MX_SR_Z] = result.flags.z;
            value[MX_SR_C] = result.flags.c;
            return value;
        end
    endfunction

    function automatic logic [31:0] execute_multiply_word(
        input logic [31:0] destination,
        input logic [31:0] source,
        input logic signed_operation
    );
        logic signed [31:0] signed_product;
        logic [31:0] unsigned_product;
        begin
            signed_product = $signed(destination[15:0]) *
                             $signed(source[15:0]);
            unsigned_product = destination[15:0] * source[15:0];
            return signed_operation ? signed_product : unsigned_product;
        end
    endfunction

    always_comb begin
        reset_request = '0;
        reset_request.command = MX_MEM_READ;
        reset_request.size = MX_SIZE_LINE;
        reset_request.addr = 32'd0;
        reset_request.txn_id = 4'd0;
        reset_request.source = DATA_SOURCE_ID;
        reset_request.instruction = 1'b1;
        reset_request.supervisor = 1'b1;
        reset_request.cacheable = 1'b0;
        reset_request.ordered = 1'b1;

        pending_operand_bytes = (pending_memory_action_q inside {
            MEMORY_ACTION_JSR_PUSH, MEMORY_ACTION_RTS_POP,
            MEMORY_ACTION_PEA_PUSH, MEMORY_ACTION_EXCEPTION_PUSH_PC,
            MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
            MEMORY_ACTION_EXCEPTION_VECTOR_READ,
            MEMORY_ACTION_RTE_LOAD_PC,
            MEMORY_ACTION_RTR_LOAD_PC}) ? 5'd4 :
            ((pending_memory_action_q inside {
              MEMORY_ACTION_EXCEPTION_PUSH_SR,
              MEMORY_ACTION_EXCEPTION_PUSH_IR,
              MEMORY_ACTION_EXCEPTION_PUSH_SSW,
              MEMORY_ACTION_RTE_LOAD_SR,
              MEMORY_ACTION_RTR_LOAD_CCR}) ? 5'd2 :
            ((pending_memory_uop_q.size == MX_OP_BYTE) ? 5'd1 :
             (pending_memory_uop_q.size == MX_OP_WORD) ? 5'd2 : 5'd4));
        pending_request_is_write = pending_memory_action_q inside {
            MEMORY_ACTION_MOVE_STORE, MEMORY_ACTION_CLEAR_STORE,
            MEMORY_ACTION_JSR_PUSH, MEMORY_ACTION_PEA_PUSH,
            MEMORY_ACTION_MOVEM_STORE, MEMORY_ACTION_LINK_PUSH,
            MEMORY_ACTION_RMW_STORE, MEMORY_ACTION_ATOMIC,
            MEMORY_ACTION_EXCEPTION_PUSH_PC,
            MEMORY_ACTION_EXCEPTION_PUSH_SR,
            MEMORY_ACTION_EXCEPTION_PUSH_IR,
            MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
            MEMORY_ACTION_EXCEPTION_PUSH_SSW};

        // The internal memory fabric transports one aligned 16-byte line per
        // transaction.  A legal MC68000 long access at line offset 14 spans
        // two lines, so issue it as two ordered word beats.  Architectural
        // state is committed only after the second beat completes.
        data_request_splits_long = !split_access_second_q &&
            (pending_operand_bytes == 5'd4) &&
            (pending_memory_address_q[3:0] == 4'he);
        data_request_operand_bytes =
            (data_request_splits_long || split_access_second_q) ?
            5'd2 : pending_operand_bytes;
        data_request_write_value = split_access_second_q ?
            {16'd0, pending_memory_write_value_q[15:0]} :
            data_request_splits_long ?
            {16'd0, pending_memory_write_value_q[31:16]} :
            pending_memory_write_value_q;
        completed_memory_address = split_access_second_q ?
            split_base_address_q : pending_memory_address_q;

        data_request = '0;
        data_request.command =
            (pending_memory_action_q == MEMORY_ACTION_ATOMIC) ?
                MX_MEM_ATOMIC :
            pending_request_is_write ? MX_MEM_WRITE : MX_MEM_READ;
        data_request.size = (data_request_splits_long ||
                             split_access_second_q) ? MX_SIZE_WORD :
            ((pending_memory_action_q inside {
            MEMORY_ACTION_JSR_PUSH, MEMORY_ACTION_RTS_POP,
            MEMORY_ACTION_PEA_PUSH, MEMORY_ACTION_EXCEPTION_PUSH_PC,
            MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
            MEMORY_ACTION_EXCEPTION_VECTOR_READ,
            MEMORY_ACTION_RTE_LOAD_PC,
            MEMORY_ACTION_RTR_LOAD_PC}) ? MX_SIZE_LONG :
            ((pending_memory_action_q inside {
              MEMORY_ACTION_EXCEPTION_PUSH_SR,
              MEMORY_ACTION_EXCEPTION_PUSH_IR,
              MEMORY_ACTION_EXCEPTION_PUSH_SSW,
              MEMORY_ACTION_RTE_LOAD_SR,
              MEMORY_ACTION_RTR_LOAD_CCR}) ? MX_SIZE_WORD :
            memory_size_for_operand(pending_memory_uop_q.size)));
        data_request.addr = pending_memory_address_q;
        data_request.txn_id = 4'd1;
        data_request.source = DATA_SOURCE_ID;
        data_request.supervisor = debug_sr[MX_SR_S] ||
            (pending_memory_action_q inside {
             MEMORY_ACTION_EXCEPTION_PUSH_PC,
             MEMORY_ACTION_EXCEPTION_PUSH_SR,
             MEMORY_ACTION_EXCEPTION_PUSH_IR,
             MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
             MEMORY_ACTION_EXCEPTION_PUSH_SSW,
             MEMORY_ACTION_EXCEPTION_VECTOR_READ,
             MEMORY_ACTION_RTE_LOAD_SR,
             MEMORY_ACTION_RTE_LOAD_PC});
        data_request.cacheable = 1'b1;
        if (pending_memory_action_q == MEMORY_ACTION_ATOMIC) begin
            data_request.atomic_op = MX_ATOMIC_OR;
            data_request.ordered = 1'b1;
            data_request.lock = 1'b1;
        end
        if (pending_request_is_write) begin
            case (data_request_operand_bytes)
                5'd1: begin
                    data_request.wstrb[pending_memory_address_q[3:0]] = 1'b1;
                    data_request.wdata[pending_memory_address_q[3:0]*8 +: 8] =
                        data_request_write_value[7:0];
                end
                5'd2: begin
                    data_request.wstrb[pending_memory_address_q[3:0]] = 1'b1;
                    data_request.wstrb[pending_memory_address_q[3:0] + 1'b1] = 1'b1;
                    data_request.wdata[pending_memory_address_q[3:0]*8 +: 8] =
                        data_request_write_value[15:8];
                    data_request.wdata[(pending_memory_address_q[3:0]+1'b1)*8 +: 8] =
                        data_request_write_value[7:0];
                end
                default: begin
                    for (int byte_index = 0; byte_index < 4;
                         byte_index = byte_index + 1) begin
                        data_request.wstrb[pending_memory_address_q[3:0] +
                                           byte_index] = 1'b1;
                        data_request.wdata[(pending_memory_address_q[3:0] +
                                            byte_index)*8 +: 8] =
                            data_request_write_value[31-byte_index*8 -: 8];
                    end
                end
            endcase
        end

        data_request_alignment_error =
            (data_request.size inside {MX_SIZE_WORD, MX_SIZE_LONG}) &&
            data_request.addr[0];
        dmem.req_valid = (state_q == CORE_RESET_SEND) ||
                         ((state_q == CORE_DATA_SEND) &&
                          !data_request_alignment_error);
        dmem.req = (state_q == CORE_DATA_SEND) ? data_request : reset_request;
        dmem.rsp_ready = (state_q == CORE_RESET_WAIT) ||
                         (state_q == CORE_DATA_WAIT);

        reset_response_ids_match =
            (dmem.rsp.txn_id == reset_request.txn_id) &&
            (dmem.rsp.source == reset_request.source);
        reset_response_fault = reset_response_ids_match ?
                               dmem.rsp.fault : MX_FAULT_BUS;
        reset_response_handshake = (state_q == CORE_RESET_WAIT) &&
                                   dmem.rsp_valid && dmem.rsp_ready;
        reset_ssp = {
            dmem.rsp.rdata[7:0], dmem.rsp.rdata[15:8],
            dmem.rsp.rdata[23:16], dmem.rsp.rdata[31:24]
        };
        reset_pc = {
            dmem.rsp.rdata[39:32], dmem.rsp.rdata[47:40],
            dmem.rsp.rdata[55:48], dmem.rsp.rdata[63:56]
        };
        data_response_ids_match =
            (dmem.rsp.txn_id == data_request.txn_id) &&
            (dmem.rsp.source == data_request.source);
        data_response_fault = data_response_ids_match ?
                              dmem.rsp.fault : MX_FAULT_BUS;
        if (data_response_ids_match &&
            (pending_memory_action_q == MEMORY_ACTION_ATOMIC) &&
            (dmem.rsp.fault == MX_FAULT_NONE) &&
            !dmem.rsp.atomic_success)
            data_response_fault = MX_FAULT_UNSUPPORTED;
        data_response_handshake = (state_q == CORE_DATA_WAIT) &&
                                  dmem.rsp_valid && dmem.rsp_ready;
        data_response_completes_access = data_response_handshake &&
                                         !data_request_splits_long;
        pending_exception_special = pending_exception_q.vector inside {
            MX_VECTOR_ACCESS_FAULT, MX_VECTOR_ADDRESS_ERROR};
        pending_action_is_exception_frame = pending_memory_action_q inside {
            MEMORY_ACTION_EXCEPTION_PUSH_PC,
            MEMORY_ACTION_EXCEPTION_PUSH_SR,
            MEMORY_ACTION_EXCEPTION_PUSH_IR,
            MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
            MEMORY_ACTION_EXCEPTION_PUSH_SSW,
            MEMORY_ACTION_EXCEPTION_VECTOR_READ};
        movem_remaining_mask = pending_movem_mask_q &
                               ~(16'h0001 << pending_movem_bit_q);
        movem_next_bit = first_set_bit(movem_remaining_mask);
        movem_final_transfer = (movem_remaining_mask == 16'd0);
        movem_load_write_valid = data_response_completes_access &&
            (data_response_fault == MX_FAULT_NONE) &&
            (pending_memory_action_q == MEMORY_ACTION_MOVEM_LOAD);
        data_response_beat_value = '0;
        case (data_request_operand_bytes)
            5'd1: data_response_beat_value = {24'd0,
                dmem.rsp.rdata[pending_memory_address_q[3:0]*8 +: 8]};
            5'd2: data_response_beat_value = {16'd0,
                dmem.rsp.rdata[pending_memory_address_q[3:0]*8 +: 8],
                dmem.rsp.rdata[(pending_memory_address_q[3:0]+1'b1)*8 +: 8]};
            default: begin
                for (int byte_index = 0; byte_index < 4;
                     byte_index = byte_index + 1)
                    data_response_beat_value[31-byte_index*8 -: 8] =
                        dmem.rsp.rdata[(pending_memory_address_q[3:0] +
                                        byte_index)*8 +: 8];
            end
        endcase
        data_response_value = split_access_second_q ?
            {split_read_high_q, data_response_beat_value[15:0]} :
            data_response_beat_value;

        frontend_redirect_valid = (state_q == CORE_START_FRONTEND) ||
                                  redirect_pending_q;
        frontend_redirect_pc = (state_q == CORE_START_FRONTEND) ?
                               debug_pc : redirect_target_q;

        condition_flags.n = debug_sr[MX_SR_N];
        condition_flags.z = debug_sr[MX_SR_Z];
        condition_flags.v = debug_sr[MX_SR_V];
        condition_flags.c = debug_sr[MX_SR_C];
        branch_taken = (instruction_uop.condition == 4'h0) ||
                       ((instruction_uop.condition >= 4'h2) &&
                        mx_condition_true(instruction_uop.condition,
                                          condition_flags));
        trap_taken = (instruction_uop.opcode == MX_UOP_TRAP) &&
            ((instruction_uop.flags_read == '0) ||
             mx_condition_true(instruction_uop.condition, condition_flags));
        dbcc_condition_false = !mx_condition_true(
            instruction_uop.condition, condition_flags);
        dbcc_taken = dbcc_condition_false &&
                     ((rf_data_read_b[15:0] - 16'd1) != 16'hffff);
        source_operand_value = instruction_uop.immediate;
        if (instruction_uop.source_a.kind == MX_OPERAND_SR)
            source_operand_value = {16'd0, debug_sr};
        else if (instruction_uop.source_a.kind == MX_OPERAND_USP)
            source_operand_value = debug_usp;
        else if ((instruction_uop.source_ea.kind == MX_EA_DATA_REGISTER) ||
            (instruction_uop.source_a.kind == MX_OPERAND_DATA_REGISTER))
            source_operand_value = rf_data_read_a;
        else if ((instruction_uop.source_ea.kind == MX_EA_ADDRESS_REGISTER) ||
                 (instruction_uop.source_a.kind == MX_OPERAND_ADDRESS_REGISTER))
            source_operand_value = rf_address_read_a;

        destination_operand_value = rf_data_read_b;
        if (instruction_uop.destination.kind == MX_OPERAND_ADDRESS_REGISTER)
            destination_operand_value = rf_address_read_b;
        else if (instruction_uop.destination.kind == MX_OPERAND_IMMEDIATE)
            destination_operand_value = instruction_uop.immediate;

        shift_count = instruction_uop.condition[0] ?
                      source_operand_value[5:0] :
                      instruction_uop.immediate[5:0];
        memory_shift_active = (pending_memory_uop_q.opcode == MX_UOP_SHIFT) &&
            (pending_memory_action_q inside {MEMORY_ACTION_RMW_LOAD,
                                             MEMORY_ACTION_RMW_STORE});
        shift_operand = memory_shift_active ?
            ((pending_memory_action_q == MEMORY_ACTION_RMW_LOAD) ?
             data_response_value : pending_destination_original_q) :
            destination_operand_value;
        shift_operation_size = memory_shift_active ?
            pending_memory_uop_q.size : instruction_uop.size;
        shift_operation_count = memory_shift_active ? 6'd1 : shift_count;
        shift_direction_left = memory_shift_active ?
            pending_memory_uop_q.condition[3] : instruction_uop.condition[3];
        shift_kind = memory_shift_active ?
            pending_memory_uop_q.condition[2:1] :
            instruction_uop.condition[2:1];
        direct_add_extend_result = instruction_uop.condition[1] ?
            mx_add_decimal_byte(destination_operand_value[7:0],
                                source_operand_value[7:0],
                                debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            mx_add(destination_operand_value, source_operand_value,
                   instruction_uop.size, debug_sr[MX_SR_X],
                   debug_sr[MX_SR_Z]);
        direct_subtract_extend_result = instruction_uop.condition[1] ?
            mx_subtract_decimal_byte(
                                     instruction_uop.condition[0] ?
                                         destination_operand_value[7:0] :
                                         8'd0,
                                     instruction_uop.condition[0] ?
                                         source_operand_value[7:0] :
                                         destination_operand_value[7:0],
                                     debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            instruction_uop.condition[0] ?
            mx_subtract(destination_operand_value, source_operand_value,
                        instruction_uop.size, debug_sr[MX_SR_X],
                        debug_sr[MX_SR_Z]) :
            mx_subtract(32'd0, destination_operand_value,
                        instruction_uop.size, debug_sr[MX_SR_X],
                        debug_sr[MX_SR_Z]);
        data_add_extend_result = pending_memory_uop_q.condition[1] ?
            mx_add_decimal_byte(pending_destination_original_q[7:0],
                                pending_source_operand_q[7:0],
                                debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            mx_add(pending_destination_original_q, pending_source_operand_q,
                   pending_memory_uop_q.size,
                   debug_sr[MX_SR_X], debug_sr[MX_SR_Z]);
        data_subtract_extend_result = pending_memory_uop_q.condition[1] ?
            mx_subtract_decimal_byte(
                                     pending_memory_uop_q.condition[0] ?
                                         pending_destination_original_q[7:0] :
                                         8'd0,
                                     pending_memory_uop_q.condition[0] ?
                                         pending_source_operand_q[7:0] :
                                         pending_destination_original_q[7:0],
                                     debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            pending_memory_uop_q.condition[0] ?
            mx_subtract(pending_destination_original_q,
                        pending_source_operand_q,
                        pending_memory_uop_q.size,
                        debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            mx_subtract(32'd0, pending_destination_original_q,
                        pending_memory_uop_q.size,
                        debug_sr[MX_SR_X], debug_sr[MX_SR_Z]);
        rmw_add_extend_result = pending_memory_uop_q.condition[1] ?
            mx_add_decimal_byte(data_response_value[7:0],
                                pending_source_operand_q[7:0],
                                debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            mx_add(data_response_value, pending_source_operand_q,
                   pending_memory_uop_q.size,
                   debug_sr[MX_SR_X], debug_sr[MX_SR_Z]);
        rmw_subtract_extend_result = pending_memory_uop_q.condition[1] ?
            mx_subtract_decimal_byte(
                                     pending_memory_uop_q.condition[0] ?
                                         data_response_value[7:0] : 8'd0,
                                     pending_memory_uop_q.condition[0] ?
                                         pending_source_operand_q[7:0] :
                                         data_response_value[7:0],
                                     debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            pending_memory_uop_q.condition[0] ?
            mx_subtract(data_response_value, pending_source_operand_q,
                        pending_memory_uop_q.size,
                        debug_sr[MX_SR_X], debug_sr[MX_SR_Z]) :
            mx_subtract(32'd0, data_response_value,
                        pending_memory_uop_q.size,
                        debug_sr[MX_SR_X], debug_sr[MX_SR_Z]);
        alu_source_value = source_operand_value;
        alu_operation_size = instruction_uop.size;
        if ((instruction_uop.opcode inside {
             MX_UOP_ADD, MX_UOP_SUBTRACT, MX_UOP_COMPARE}) &&
            (instruction_uop.destination.kind ==
             MX_OPERAND_ADDRESS_REGISTER)) begin
            if (instruction_uop.size == MX_OP_WORD)
                alu_source_value = {{16{source_operand_value[15]}},
                                    source_operand_value[15:0]};
            alu_operation_size = MX_OP_LONG;
        end

        source_ea_address = mx_ea_address(
            instruction_uop.source_ea, instruction_uop.size,
            rf_address_read_a,
            packed_register_value(debug_data_registers,
                instruction_uop.source_ea.extension_0[14:12]),
            packed_register_value(debug_address_registers,
                instruction_uop.source_ea.extension_0[14:12]));
        destination_ea_address = mx_ea_address(
            instruction_uop.destination_ea, instruction_uop.size,
            rf_address_read_b,
            packed_register_value(debug_data_registers,
                instruction_uop.destination_ea.extension_0[14:12]),
            packed_register_value(debug_address_registers,
                instruction_uop.destination_ea.extension_0[14:12]));
        sequence_source_step = {29'd0, mx_ea_step_bytes(
            instruction_uop.size,
            instruction_uop.source_ea.register_index)};
        sequence_destination_step = {29'd0, mx_ea_step_bytes(
            instruction_uop.size,
            instruction_uop.destination_ea.register_index)};

        starts_memory_sequence =
            (instruction_uop.opcode == MX_UOP_COMPARE_MEMORY) ||
            ((instruction_uop.opcode == MX_UOP_MOVE) &&
             mx_ea_is_memory(instruction_uop.destination_ea) &&
             !mx_ea_is_memory(instruction_uop.source_ea)) ||
            ((instruction_uop.opcode == MX_UOP_MOVE) &&
             mx_ea_is_memory(instruction_uop.destination_ea) &&
             mx_ea_is_memory(instruction_uop.source_ea)) ||
            (((instruction_uop.opcode == MX_UOP_MOVE) ||
              (instruction_uop.opcode == MX_UOP_MOVE_ADDRESS)) &&
             mx_ea_is_memory(instruction_uop.source_ea) &&
             !mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode inside {
              MX_UOP_ADD, MX_UOP_SUBTRACT, MX_UOP_AND, MX_UOP_OR,
              MX_UOP_XOR, MX_UOP_COMPARE, MX_UOP_MULTIPLY,
              MX_UOP_DIVIDE, MX_UOP_CHECK_BOUNDS}) &&
             mx_ea_is_memory(instruction_uop.source_ea)) ||
            ((instruction_uop.opcode == MX_UOP_CLEAR) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode == MX_UOP_SET_CONDITION) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode == MX_UOP_ATOMIC) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode == MX_UOP_TEST) &&
             mx_ea_is_memory(instruction_uop.source_ea)) ||
            ((instruction_uop.opcode == MX_UOP_BIT_TEST) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode == MX_UOP_SHIFT) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode == MX_UOP_COMPARE) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            ((instruction_uop.opcode inside {
              MX_UOP_ADD, MX_UOP_SUBTRACT, MX_UOP_AND, MX_UOP_OR,
              MX_UOP_XOR, MX_UOP_NOT, MX_UOP_NEGATE,
              MX_UOP_ADD_EXTEND, MX_UOP_SUBTRACT_EXTEND}) &&
             mx_ea_is_memory(instruction_uop.destination_ea)) ||
            (instruction_uop.opcode inside {
             MX_UOP_JUMP_SUBROUTINE, MX_UOP_BRANCH_SUBROUTINE}) ||
            (instruction_uop.opcode == MX_UOP_RETURN) ||
            (instruction_uop.opcode == MX_UOP_PUSH_EFFECTIVE_ADDRESS) ||
            // Each MOVEM mask bit selects one transfer.  An empty list is a
            // legal zero-transfer operation and must not issue a spurious D0
            // access or update its effective-address register.
            ((instruction_uop.opcode == MX_UOP_MOVE_MULTIPLE) &&
             (instruction_uop.immediate[15:0] != 16'd0)) ||
            (instruction_uop.opcode == MX_UOP_LINK) ||
            (instruction_uop.opcode == MX_UOP_UNLINK) ||
            (instruction_uop.opcode == MX_UOP_EXCEPTION_RETURN) ||
            (instruction_uop.opcode == MX_UOP_STORE);

        execute_supported = 1'b0;
        if (instruction_uop.valid) begin
            case (instruction_uop.opcode)
                MX_UOP_NOP,
                MX_UOP_RESET,
                MX_UOP_MOVE,
                MX_UOP_MOVE_ADDRESS,
                MX_UOP_CLEAR,
                MX_UOP_TEST,
                MX_UOP_ADD,
                MX_UOP_ADD_EXTEND,
                MX_UOP_SUBTRACT,
                MX_UOP_SUBTRACT_EXTEND,
                MX_UOP_COMPARE,
                MX_UOP_COMPARE_MEMORY,
                MX_UOP_NOT,
                MX_UOP_NEGATE,
                MX_UOP_EXCHANGE,
                MX_UOP_SWAP,
                MX_UOP_XOR,
                MX_UOP_BRANCH,
                MX_UOP_BRANCH_SUBROUTINE,
                MX_UOP_STORE,
                MX_UOP_CALCULATE_EA,
                MX_UOP_PUSH_EFFECTIVE_ADDRESS,
                MX_UOP_JUMP_SUBROUTINE,
                MX_UOP_RETURN,
                MX_UOP_JUMP,
                MX_UOP_AND,
                MX_UOP_OR,
                MX_UOP_DBCC,
                MX_UOP_SHIFT,
                MX_UOP_MOVE_MULTIPLE,
                MX_UOP_MULTIPLY,
                MX_UOP_DIVIDE,
                MX_UOP_TRAP,
                MX_UOP_EXCEPTION_RETURN,
                MX_UOP_LINK,
                MX_UOP_UNLINK,
                MX_UOP_SIGN_EXTEND,
                MX_UOP_BIT_TEST,
                MX_UOP_CHECK_BOUNDS,
                MX_UOP_SET_CONDITION,
                MX_UOP_ATOMIC,
                MX_UOP_STOP: execute_supported = 1'b1;
                default: execute_supported = 1'b0;
            endcase
        end
        privilege_fault = instruction_uop.valid &&
                          instruction_uop.privileged &&
                          !debug_sr[MX_SR_S];
        successful_uop = execute_supported && !privilege_fault;

        interrupt_level7_active = irq.request && (irq.level == 3'd7);
        interrupt_level7_rise = interrupt_level7_active &&
                                !interrupt_level7_seen_q;
        active_interrupt_level =
            (interrupt_level7_pending_q || interrupt_level7_rise) ? 3'd7 :
                                                                    irq.level;
        interrupt_take = !trace_pending_q &&
            ((state_q == CORE_RUN) ||
                          (state_q == CORE_STOPPED)) &&
            ((interrupt_level7_pending_q || interrupt_level7_rise) ||
             (irq.request && mx_interrupt_accepted(
                 irq.level, debug_sr[MX_SR_I2:MX_SR_I0], 1'b0)));
        accepted_interrupt_vector = irq.vector_valid ? irq.vector :
            (MX_VECTOR_AUTOVECTOR_BASE + {5'd0, active_interrupt_level});

        instruction_ready = (state_q == CORE_RUN) &&
                            !redirect_pending_q && !trace_pending_q &&
                            !interrupt_take;
        instruction_handshake = instruction_valid && instruction_ready;
        divider_start = !divider_busy && (
            ((state_q == CORE_RUN) && instruction_handshake &&
             !instruction_exception.valid && !privilege_fault &&
             execute_supported && !starts_memory_sequence &&
             (instruction_uop.opcode == MX_UOP_DIVIDE)) ||
            ((state_q == CORE_DATA_WAIT) && data_response_handshake &&
             (data_response_fault == MX_FAULT_NONE) &&
             !data_request_splits_long &&
             (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
             (pending_memory_uop_q.opcode == MX_UOP_DIVIDE)));
        divide_commit_valid = (state_q == CORE_DIVIDE_WAIT) &&
                              divider_done &&
                              !divider_divide_by_zero;
        sequence_checkpoint_commit_valid =
            data_response_completes_access &&
            (data_response_fault == MX_FAULT_NONE) &&
            (pending_memory_action_q == MEMORY_ACTION_SEQUENCE_READ) &&
            (sequence_step_q == MX_SEQUENCE_READ_SOURCE);
        direct_chk_trap =
            (instruction_uop.opcode == MX_UOP_CHECK_BOUNDS) &&
            !mx_ea_is_memory(instruction_uop.source_ea) &&
            chk_word_out_of_bounds(destination_operand_value,
                                   source_operand_value);
        data_chk_trap =
            (pending_memory_uop_q.opcode == MX_UOP_CHECK_BOUNDS) &&
            chk_word_out_of_bounds(pending_destination_original_q,
                                   data_response_value);
        direct_chk_sr = chk_word_result_sr(
            debug_sr, destination_operand_value, source_operand_value);
        data_chk_sr = chk_word_result_sr(
            debug_sr, pending_destination_original_q, data_response_value);

        direct_result_value = source_operand_value;
        if (instruction_uop.opcode == MX_UOP_CLEAR)
            direct_result_value = 32'd0;
        if ((instruction_uop.opcode == MX_UOP_MOVE_ADDRESS) &&
            (instruction_uop.size == MX_OP_WORD))
            direct_result_value = {{16{source_operand_value[15]}},
                                   source_operand_value[15:0]};
        if (instruction_uop.opcode == MX_UOP_CALCULATE_EA)
            direct_result_value = source_ea_address;
        if (instruction_uop.opcode == MX_UOP_ADD)
            direct_result_value = destination_operand_value +
                                  alu_source_value;
        if (instruction_uop.opcode == MX_UOP_ADD_EXTEND)
            direct_result_value = direct_add_extend_result.result;
        if (instruction_uop.opcode == MX_UOP_SUBTRACT)
            direct_result_value = destination_operand_value -
                                  alu_source_value;
        if (instruction_uop.opcode == MX_UOP_COMPARE)
            direct_result_value = destination_operand_value -
                                  alu_source_value;
        if (instruction_uop.opcode == MX_UOP_AND)
            direct_result_value = destination_operand_value &
                                  source_operand_value;
        if (instruction_uop.opcode == MX_UOP_OR)
            direct_result_value = destination_operand_value |
                                  source_operand_value;
        if (instruction_uop.opcode == MX_UOP_XOR)
            direct_result_value = destination_operand_value ^
                                  source_operand_value;
        if (instruction_uop.opcode == MX_UOP_NOT)
            direct_result_value = ~destination_operand_value;
        if (instruction_uop.opcode == MX_UOP_NEGATE)
            direct_result_value = 32'd0 - destination_operand_value;
        if (instruction_uop.opcode == MX_UOP_SUBTRACT_EXTEND)
            direct_result_value = direct_subtract_extend_result.result;
        if (instruction_uop.opcode == MX_UOP_SWAP)
            direct_result_value = {destination_operand_value[15:0],
                                   destination_operand_value[31:16]};
        if (instruction_uop.opcode == MX_UOP_SIGN_EXTEND)
            direct_result_value = instruction_uop.condition[0] ?
                {{16{destination_operand_value[15]}},
                  destination_operand_value[15:0]} :
                {{24{destination_operand_value[7]}},
                  destination_operand_value[7:0]};
        if (instruction_uop.opcode == MX_UOP_MULTIPLY)
            direct_result_value = execute_multiply_word(
                destination_operand_value, source_operand_value,
                instruction_uop.condition[0]);
        if (instruction_uop.opcode == MX_UOP_DBCC)
            direct_result_value = {destination_operand_value[31:16],
                                   destination_operand_value[15:0] - 16'd1};
        if (instruction_uop.opcode == MX_UOP_SHIFT)
            direct_result_value = shift_result.result;
        if (instruction_uop.opcode == MX_UOP_SET_CONDITION)
            direct_result_value = mx_condition_true(
                instruction_uop.condition, condition_flags) ? 32'h0000_00ff :
                                                               32'h0000_0000;
        if (instruction_uop.opcode == MX_UOP_ATOMIC)
            direct_result_value = destination_operand_value | 32'h0000_0080;
        direct_bit_index = source_operand_value[4:0];
        if (instruction_uop.opcode == MX_UOP_BIT_TEST) begin
            case (instruction_uop.condition[1:0])
                2'b01: direct_result_value = destination_operand_value ^
                    (32'd1 << direct_bit_index);
                2'b10: direct_result_value = destination_operand_value &
                    ~(32'd1 << direct_bit_index);
                2'b11: direct_result_value = destination_operand_value |
                    (32'd1 << direct_bit_index);
                default: direct_result_value = destination_operand_value;
            endcase
        end
        move_sr = logical_result_sr(debug_sr, direct_result_value,
                                    instruction_uop.size);
        direct_writes_flags = |instruction_uop.flags_write;
        direct_writes_sr = direct_writes_flags ||
            (instruction_uop.destination.kind == MX_OPERAND_SR) ||
            (instruction_uop.opcode == MX_UOP_STOP);
        direct_sr_value = move_sr;
        if (instruction_uop.opcode == MX_UOP_ADD)
            direct_sr_value = add_result_sr(debug_sr,
                                            destination_operand_value,
                                            source_operand_value,
                                            instruction_uop.size);
        if (instruction_uop.opcode == MX_UOP_ADD_EXTEND)
            direct_sr_value = instruction_uop.condition[1] ?
                decimal_arithmetic_result_sr(
                    debug_sr, direct_add_extend_result) :
                extend_arithmetic_result_sr(
                    debug_sr, direct_add_extend_result);
        if (instruction_uop.opcode == MX_UOP_SUBTRACT)
            direct_sr_value = subtract_result_sr(
                                                 debug_sr,
                                                 destination_operand_value,
                                                 source_operand_value,
                                                 instruction_uop.size);
        if (instruction_uop.opcode == MX_UOP_COMPARE) begin
            direct_sr_value = subtract_result_sr(
                debug_sr, destination_operand_value, alu_source_value,
                alu_operation_size);
            direct_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        end
        if (instruction_uop.opcode inside {
            MX_UOP_AND, MX_UOP_OR, MX_UOP_XOR, MX_UOP_NOT})
            direct_sr_value = logical_result_sr(debug_sr,
                                                direct_result_value,
                                                instruction_uop.size);
        if (instruction_uop.opcode == MX_UOP_NEGATE)
            direct_sr_value = subtract_result_sr(
                debug_sr, 32'd0, destination_operand_value,
                instruction_uop.size);
        if (instruction_uop.opcode == MX_UOP_SUBTRACT_EXTEND)
            direct_sr_value = instruction_uop.condition[1] ?
                decimal_arithmetic_result_sr(
                    debug_sr, direct_subtract_extend_result) :
                extend_arithmetic_result_sr(
                    debug_sr, direct_subtract_extend_result);
        if (instruction_uop.opcode == MX_UOP_SWAP) begin
            direct_sr_value = logical_result_sr(debug_sr,
                                                direct_result_value,
                                                MX_OP_LONG);
            direct_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        end
        if (instruction_uop.opcode == MX_UOP_SIGN_EXTEND) begin
            direct_sr_value = logical_result_sr(debug_sr,
                                                direct_result_value,
                                                instruction_uop.size);
            direct_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        end
        if (instruction_uop.opcode == MX_UOP_BIT_TEST) begin
            direct_sr_value = debug_sr;
            direct_sr_value[MX_SR_Z] =
                !destination_operand_value[direct_bit_index];
        end
        if (instruction_uop.opcode == MX_UOP_ATOMIC) begin
            // TAS condition codes describe the byte before bit 7 is set;
            // X is unaffected by logical_result_sr().
            direct_sr_value = logical_result_sr(
                debug_sr, destination_operand_value, MX_OP_BYTE);
        end
        if (instruction_uop.opcode == MX_UOP_MULTIPLY) begin
            direct_sr_value = logical_result_sr(debug_sr,
                                                direct_result_value,
                                                MX_OP_LONG);
            direct_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        end
        if (instruction_uop.opcode == MX_UOP_SHIFT) begin
            direct_sr_value = debug_sr;
            direct_sr_value[MX_SR_X] = shift_result.flags.x;
            direct_sr_value[MX_SR_N] = shift_result.flags.n;
            direct_sr_value[MX_SR_Z] = shift_result.flags.z;
            direct_sr_value[MX_SR_V] = shift_result.flags.v;
            direct_sr_value[MX_SR_C] = shift_result.flags.c;
        end
        if (instruction_uop.opcode == MX_UOP_CHECK_BOUNDS)
            direct_sr_value = direct_chk_sr;
        if (instruction_uop.destination.kind == MX_OPERAND_SR) begin
            if (instruction_uop.opcode == MX_UOP_MOVE)
                direct_sr_value = instruction_uop.condition[0] ?
                    {debug_sr[15:5], source_operand_value[4:0]} :
                    source_operand_value[15:0];
            else if (instruction_uop.opcode == MX_UOP_OR)
                direct_sr_value = debug_sr | instruction_uop.immediate[15:0];
            else if (instruction_uop.opcode == MX_UOP_XOR)
                direct_sr_value = debug_sr ^ instruction_uop.immediate[15:0];
            else
                direct_sr_value = debug_sr & instruction_uop.immediate[15:0];
            if ((instruction_uop.opcode inside {
                 MX_UOP_OR, MX_UOP_AND, MX_UOP_XOR}) &&
                instruction_uop.condition[0])
                direct_sr_value[15:8] = debug_sr[15:8];
        end else if (instruction_uop.opcode == MX_UOP_STOP) begin
            direct_sr_value = instruction_uop.immediate[15:0];
        end

        pending_writes_flags = |pending_memory_uop_q.flags_write;
        data_writeback_value = data_response_value;
        data_alu_source_value = data_response_value;
        data_alu_operation_size = pending_memory_uop_q.size;
        if ((pending_memory_uop_q.opcode inside {
             MX_UOP_ADD, MX_UOP_SUBTRACT, MX_UOP_COMPARE}) &&
            (pending_memory_uop_q.destination.kind ==
             MX_OPERAND_ADDRESS_REGISTER)) begin
            if (pending_memory_uop_q.size == MX_OP_WORD)
                data_alu_source_value = {{16{data_response_value[15]}},
                                         data_response_value[15:0]};
            data_alu_operation_size = MX_OP_LONG;
        end
        if (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) begin
            case (pending_memory_uop_q.opcode)
                MX_UOP_ADD: data_writeback_value =
                    pending_destination_original_q + data_alu_source_value;
                MX_UOP_SUBTRACT: data_writeback_value =
                    pending_destination_original_q - data_alu_source_value;
                MX_UOP_COMPARE: data_writeback_value =
                    mx_ea_is_memory(pending_memory_uop_q.destination_ea) ?
                    (data_response_value - pending_source_operand_q) :
                    (pending_destination_original_q - data_alu_source_value);
                MX_UOP_AND: data_writeback_value =
                    pending_destination_original_q & data_response_value;
                MX_UOP_OR: data_writeback_value =
                    pending_destination_original_q | data_response_value;
                MX_UOP_XOR: data_writeback_value =
                    pending_destination_original_q ^ data_response_value;
                MX_UOP_MULTIPLY: data_writeback_value =
                    execute_multiply_word(
                        pending_destination_original_q,
                        data_response_value,
                        pending_memory_uop_q.condition[0]);
                MX_UOP_DIVIDE: data_writeback_value =
                    divider_result;
                default: data_writeback_value = data_response_value;
            endcase
        end
        rmw_result_value = data_response_value;
        memory_bit_index = pending_source_operand_q[2:0];
        case (pending_memory_uop_q.opcode)
            MX_UOP_ADD: rmw_result_value = data_response_value +
                                                pending_source_operand_q;
            MX_UOP_SUBTRACT: rmw_result_value = data_response_value -
                                                pending_source_operand_q;
            MX_UOP_AND: rmw_result_value = data_response_value &
                                                pending_source_operand_q;
            MX_UOP_OR: rmw_result_value = data_response_value |
                                                pending_source_operand_q;
            MX_UOP_XOR: rmw_result_value = data_response_value ^
                                                pending_source_operand_q;
            MX_UOP_NOT: rmw_result_value = ~data_response_value;
            MX_UOP_NEGATE: rmw_result_value = 32'd0 - data_response_value;
            MX_UOP_ADD_EXTEND:
                rmw_result_value = rmw_add_extend_result.result;
            MX_UOP_SUBTRACT_EXTEND:
                rmw_result_value = rmw_subtract_extend_result.result;
            MX_UOP_SHIFT:
                rmw_result_value = shift_result.result;
            MX_UOP_MOVE,
            MX_UOP_CLEAR,
            MX_UOP_SET_CONDITION:
                // M68000PRM 4-74, 4-125 and 4-173: MC68000/MC68008
                // perform a destination read before CLR, MOVE SR,<ea>, and
                // Scc memory writes.  The written value does not depend on
                // that read for these operations.
                rmw_result_value = pending_memory_write_value_q;
            MX_UOP_BIT_TEST: begin
                case (pending_memory_uop_q.condition[1:0])
                    2'b01: rmw_result_value = data_response_value ^
                        (32'd1 << memory_bit_index);
                    2'b10: rmw_result_value = data_response_value &
                        ~(32'd1 << memory_bit_index);
                    2'b11: rmw_result_value = data_response_value |
                        (32'd1 << memory_bit_index);
                    default: rmw_result_value = data_response_value;
                endcase
            end
            default: begin end
        endcase
        data_sr_value = (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) ?
            ((pending_memory_uop_q.opcode == MX_UOP_ADD) ?
             add_result_sr(debug_sr, pending_destination_original_q,
                           data_response_value, pending_memory_uop_q.size) :
             (pending_memory_uop_q.opcode inside {
              MX_UOP_SUBTRACT, MX_UOP_COMPARE}) ?
             subtract_result_sr(debug_sr, pending_destination_original_q,
                                data_alu_source_value,
                                data_alu_operation_size) :
             logical_result_sr(debug_sr, data_writeback_value,
                               pending_memory_uop_q.size)) :
            logical_result_sr(
                debug_sr,
                (pending_memory_action_q inside {
                 MEMORY_ACTION_TEST_LOAD, MEMORY_ACTION_MOVE_LOAD}) ?
                    data_response_value : pending_memory_write_value_q,
                pending_memory_uop_q.size);
        if ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
            (pending_memory_uop_q.opcode == MX_UOP_COMPARE) &&
            mx_ea_is_memory(pending_memory_uop_q.destination_ea))
            data_sr_value = subtract_result_sr(
                debug_sr, data_response_value, pending_source_operand_q,
                pending_memory_uop_q.size);
        if ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
            (pending_memory_uop_q.opcode == MX_UOP_COMPARE))
            data_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        if ((pending_memory_action_q == MEMORY_ACTION_SEQUENCE_READ) &&
            (sequence_program_q == MX_SEQUENCE_CMPM) &&
            (sequence_step_q == MX_SEQUENCE_READ_DESTINATION)) begin
            data_sr_value = subtract_result_sr(
                debug_sr, data_response_value, pending_source_operand_q,
                pending_memory_uop_q.size);
            data_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        end
        if ((pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
            (pending_memory_uop_q.opcode == MX_UOP_MOVE) &&
            (pending_memory_uop_q.destination.kind == MX_OPERAND_SR))
            data_sr_value = pending_memory_uop_q.condition[0] ?
                {debug_sr[15:5], data_response_value[4:0]} :
                data_response_value[15:0];
        if (pending_memory_action_q == MEMORY_ACTION_BIT_TEST_LOAD) begin
            data_sr_value = debug_sr;
            data_sr_value[MX_SR_Z] =
                !data_response_value[memory_bit_index];
        end
        if (pending_memory_action_q == MEMORY_ACTION_RMW_STORE) begin
            if (pending_memory_uop_q.opcode == MX_UOP_ADD)
                data_sr_value = add_result_sr(
                    debug_sr, pending_destination_original_q,
                    pending_source_operand_q, pending_memory_uop_q.size);
            else if (pending_memory_uop_q.opcode == MX_UOP_SUBTRACT)
                data_sr_value = subtract_result_sr(
                    debug_sr, pending_destination_original_q,
                    pending_source_operand_q, pending_memory_uop_q.size);
            else if (pending_memory_uop_q.opcode == MX_UOP_NEGATE)
                data_sr_value = subtract_result_sr(
                    debug_sr, 32'd0, pending_destination_original_q,
                    pending_memory_uop_q.size);
            else if (pending_memory_uop_q.opcode == MX_UOP_ADD_EXTEND)
                data_sr_value = pending_memory_uop_q.condition[1] ?
                    decimal_arithmetic_result_sr(
                        debug_sr, data_add_extend_result) :
                    extend_arithmetic_result_sr(
                        debug_sr, data_add_extend_result);
            else if (pending_memory_uop_q.opcode ==
                     MX_UOP_SUBTRACT_EXTEND)
                data_sr_value = pending_memory_uop_q.condition[1] ?
                    decimal_arithmetic_result_sr(
                        debug_sr, data_subtract_extend_result) :
                    extend_arithmetic_result_sr(
                        debug_sr, data_subtract_extend_result);
            else if (pending_memory_uop_q.opcode == MX_UOP_BIT_TEST) begin
                data_sr_value = debug_sr;
                data_sr_value[MX_SR_Z] =
                    !pending_destination_original_q[memory_bit_index];
            end
            else if (pending_memory_uop_q.opcode == MX_UOP_SHIFT) begin
                data_sr_value = debug_sr;
                data_sr_value[MX_SR_X] = shift_result.flags.x;
                data_sr_value[MX_SR_N] = shift_result.flags.n;
                data_sr_value[MX_SR_Z] = shift_result.flags.z;
                data_sr_value[MX_SR_V] = shift_result.flags.v;
                data_sr_value[MX_SR_C] = shift_result.flags.c;
            end
            else
                data_sr_value = logical_result_sr(
                    debug_sr, pending_memory_write_value_q,
                    pending_memory_uop_q.size);
        end
        if (pending_memory_action_q == MEMORY_ACTION_ATOMIC)
            data_sr_value = logical_result_sr(
                debug_sr, data_response_value, MX_OP_BYTE);
        if ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
            (pending_memory_uop_q.opcode == MX_UOP_MULTIPLY)) begin
            data_sr_value = logical_result_sr(debug_sr,
                                              data_writeback_value,
                                              MX_OP_LONG);
            data_sr_value[MX_SR_X] = debug_sr[MX_SR_X];
        end
        if ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
            (pending_memory_uop_q.opcode == MX_UOP_DIVIDE)) begin
            data_sr_value = debug_sr;
            data_sr_value[MX_SR_C] = 1'b0;
            data_sr_value[MX_SR_V] = divider_overflow;
            if (!divider_overflow) begin
                data_sr_value[MX_SR_N] = divider_n;
                data_sr_value[MX_SR_Z] = divider_z;
            end
        end
        if ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
            (pending_memory_uop_q.opcode == MX_UOP_CHECK_BOUNDS))
            data_sr_value = data_chk_sr;

        direct_commit_valid = instruction_handshake && successful_uop &&
                              !starts_memory_sequence &&
                              (instruction_uop.opcode != MX_UOP_RESET) &&
                              (instruction_uop.opcode != MX_UOP_DIVIDE) &&
                              !trap_taken &&
                              !direct_chk_trap;
        exception_entry_commit_valid = data_response_completes_access &&
            (data_response_fault == MX_FAULT_NONE) &&
            (pending_memory_action_q ==
             MEMORY_ACTION_EXCEPTION_VECTOR_READ);
        rte_commit_valid = data_response_completes_access &&
            (data_response_fault == MX_FAULT_NONE) &&
            (pending_memory_action_q == MEMORY_ACTION_RTE_LOAD_PC);
        rtr_commit_valid = data_response_completes_access &&
            (data_response_fault == MX_FAULT_NONE) &&
            (pending_memory_action_q == MEMORY_ACTION_RTR_LOAD_PC);
        reset_instruction_commit_valid =
            (state_q == CORE_RESET_DEVICES) &&
            (reset_devices_cycles_q == 7'd123);
        data_commit_valid = divide_commit_valid ||
                           (data_response_completes_access &&
                            (data_response_fault == MX_FAULT_NONE) &&
                            (pending_memory_action_q !=
                             MEMORY_ACTION_MOVE_LOAD_TO_STORE) &&
                            (pending_memory_action_q !=
                             MEMORY_ACTION_EXTEND_SOURCE_LOAD) &&
                            (pending_memory_action_q !=
                             MEMORY_ACTION_EXTEND_DESTINATION_LOAD) &&
                            (pending_memory_action_q !=
                             MEMORY_ACTION_RMW_LOAD) &&
                            !((pending_memory_action_q ==
                               MEMORY_ACTION_SEQUENCE_READ) &&
                              (sequence_step_q !=
                               MX_SEQUENCE_READ_DESTINATION)) &&
                            (!(pending_memory_action_q inside {
                             MEMORY_ACTION_MOVEM_STORE,
                              MEMORY_ACTION_MOVEM_LOAD}) ||
                             movem_final_transfer) &&
                            !(pending_memory_action_q inside {
                              MEMORY_ACTION_EXCEPTION_PUSH_PC,
                              MEMORY_ACTION_EXCEPTION_PUSH_SR,
                              MEMORY_ACTION_EXCEPTION_PUSH_IR,
                              MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS,
                              MEMORY_ACTION_EXCEPTION_PUSH_SSW,
                              MEMORY_ACTION_EXCEPTION_VECTOR_READ,
                              MEMORY_ACTION_RTE_LOAD_SR,
                              MEMORY_ACTION_RTE_LOAD_PC,
                              MEMORY_ACTION_RTR_LOAD_CCR,
                              MEMORY_ACTION_RTR_LOAD_PC}) &&
                            !((pending_memory_action_q ==
                               MEMORY_ACTION_ALU_LOAD) &&
                              (pending_memory_uop_q.opcode ==
                               MX_UOP_DIVIDE)) &&
                            !((pending_memory_action_q ==
                               MEMORY_ACTION_ALU_LOAD) && data_chk_trap));
        chk_operand_commit_valid = data_response_completes_access &&
            (data_response_fault == MX_FAULT_NONE) &&
            (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
            data_chk_trap;
        rf_boot_valid = reset_response_handshake &&
                        (reset_response_fault == MX_FAULT_NONE);
        rf_commit_valid = direct_commit_valid || data_commit_valid ||
                          sequence_checkpoint_commit_valid ||
                          movem_load_write_valid ||
                          chk_operand_commit_valid ||
                          exception_entry_commit_valid || rte_commit_valid ||
                          rtr_commit_valid || reset_instruction_commit_valid;
        rf_data_write_enable =
            (direct_commit_valid &&
             ((instruction_uop.opcode == MX_UOP_MOVE) ||
              (instruction_uop.opcode == MX_UOP_CLEAR)) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
             (pending_memory_uop_q.opcode == MX_UOP_MOVE) &&
             (pending_memory_uop_q.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
             !(pending_memory_uop_q.opcode inside {
               MX_UOP_COMPARE, MX_UOP_CHECK_BOUNDS}) &&
             !((pending_memory_uop_q.opcode == MX_UOP_DIVIDE) &&
               divider_overflow) &&
             (pending_memory_uop_q.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_SET_CONDITION) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_ATOMIC) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_BIT_TEST) &&
             (instruction_uop.condition[1:0] != 2'b00) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_EXCHANGE) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode inside {
              MX_UOP_ADD, MX_UOP_ADD_EXTEND, MX_UOP_SUBTRACT,
              MX_UOP_AND, MX_UOP_OR,
              MX_UOP_XOR, MX_UOP_NOT, MX_UOP_NEGATE, MX_UOP_SWAP,
              MX_UOP_SUBTRACT_EXTEND,
              MX_UOP_SIGN_EXTEND, MX_UOP_DBCC, MX_UOP_SHIFT,
              MX_UOP_MULTIPLY, MX_UOP_DIVIDE}) &&
             ((instruction_uop.opcode != MX_UOP_DBCC) ||
              dbcc_condition_false) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_DATA_REGISTER)) ||
            (movem_load_write_valid && (pending_movem_bit_q < 4'd8));
        rf_data_write_index = movem_load_write_valid ?
            pending_movem_bit_q[2:0] : data_commit_valid ?
            pending_memory_uop_q.destination.index[2:0] :
            instruction_uop.destination.index[2:0];
        rf_data_write_value = movem_load_write_valid ?
            ((pending_memory_uop_q.size == MX_OP_WORD) ?
             {{16{data_response_value[15]}}, data_response_value[15:0]} :
             data_response_value) :
            ((data_commit_valid &&
              (pending_memory_uop_q.opcode inside {
               MX_UOP_MULTIPLY, MX_UOP_DIVIDE})) ?
             data_writeback_value : data_commit_valid ?
            merge_data_register(pending_destination_original_q,
                                data_writeback_value,
                                pending_memory_uop_q.size) :
            ((instruction_uop.opcode inside {
              MX_UOP_MULTIPLY, MX_UOP_DIVIDE}) ?
             direct_result_value :
            merge_data_register(rf_data_read_b, direct_result_value,
                                instruction_uop.size)));
        rf_data_write_enable_b = direct_commit_valid &&
            (instruction_uop.opcode == MX_UOP_EXCHANGE) &&
            (instruction_uop.source_a.kind == MX_OPERAND_DATA_REGISTER) &&
            (instruction_uop.destination.kind == MX_OPERAND_DATA_REGISTER);
        rf_data_write_index_b = instruction_uop.source_a.index[2:0];
        rf_data_write_value_b = destination_operand_value;
        rf_address_write_enable =
            sequence_checkpoint_commit_valid ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_EXCHANGE) &&
             ((instruction_uop.destination.kind ==
               MX_OPERAND_ADDRESS_REGISTER) ||
              (instruction_uop.source_a.kind ==
               MX_OPERAND_ADDRESS_REGISTER))) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_MOVE) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_MOVE_ADDRESS) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_CALCULATE_EA) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER)) ||
            (direct_commit_valid &&
             (instruction_uop.opcode inside {MX_UOP_ADD, MX_UOP_SUBTRACT}) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER)) ||
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
             (pending_memory_uop_q.opcode == MX_UOP_MOVE_ADDRESS)) ||
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
             (pending_memory_uop_q.opcode inside {
              MX_UOP_ADD, MX_UOP_SUBTRACT}) &&
             (pending_memory_uop_q.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER)) ||
            (data_commit_valid && pending_address_update_q &&
             (pending_memory_action_q != MEMORY_ACTION_MOVEM_LOAD)) ||
            (chk_operand_commit_valid && pending_address_update_q) ||
            (movem_load_write_valid && (pending_movem_bit_q >= 4'd8)) ||
            rtr_commit_valid ||
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_UNLINK_POP));
        rf_address_write_index =
            sequence_checkpoint_commit_valid ?
            sequence_checkpoint_index_q :
            rtr_commit_valid ? 3'd7 :
            movem_load_write_valid ? pending_movem_bit_q[2:0] :
            ((pending_memory_action_q == MEMORY_ACTION_UNLINK_POP) ?
             pending_memory_uop_q.source_ea.register_index :
            ((data_commit_valid &&
              (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
              (pending_memory_uop_q.destination.kind ==
               MX_OPERAND_ADDRESS_REGISTER) &&
              (pending_memory_uop_q.opcode inside {
               MX_UOP_ADD, MX_UOP_SUBTRACT})) ?
             pending_memory_uop_q.destination.index[2:0] :
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
             (pending_memory_uop_q.opcode == MX_UOP_MOVE_ADDRESS)) ?
            pending_memory_uop_q.destination.index[2:0] :
            (data_commit_valid || chk_operand_commit_valid) ?
            pending_address_update_index_q :
            ((direct_commit_valid &&
              (instruction_uop.opcode == MX_UOP_EXCHANGE) &&
              (instruction_uop.destination.kind !=
               MX_OPERAND_ADDRESS_REGISTER)) ?
             instruction_uop.source_a.index[2:0] :
             instruction_uop.destination.index[2:0])));
        rf_address_write_value =
            sequence_checkpoint_commit_valid ?
            sequence_checkpoint_value_q :
            rtr_commit_valid ? pending_control_target_q :
            movem_load_write_valid ?
            ((pending_memory_uop_q.size == MX_OP_WORD) ?
             {{16{data_response_value[15]}}, data_response_value[15:0]} :
             data_response_value) :
            ((pending_memory_action_q == MEMORY_ACTION_UNLINK_POP) ?
             ((pending_memory_uop_q.source_ea.register_index == 3'd7) ?
              (data_response_value + 32'd4) : data_response_value) :
            ((data_commit_valid &&
              (pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
              (pending_memory_uop_q.destination.kind ==
               MX_OPERAND_ADDRESS_REGISTER) &&
              (pending_memory_uop_q.opcode inside {
               MX_UOP_ADD, MX_UOP_SUBTRACT})) ? data_writeback_value :
            (data_commit_valid &&
             (pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
             (pending_memory_uop_q.opcode == MX_UOP_MOVE_ADDRESS)) ?
            ((pending_memory_uop_q.size == MX_OP_WORD) ?
             {{16{data_response_value[15]}}, data_response_value[15:0]} :
            data_response_value) :
            (data_commit_valid || chk_operand_commit_valid) ?
            pending_address_update_value_q :
            ((direct_commit_valid &&
              (instruction_uop.opcode == MX_UOP_EXCHANGE) &&
              (instruction_uop.destination.kind !=
               MX_OPERAND_ADDRESS_REGISTER)) ?
             destination_operand_value : direct_result_value)));
        rf_usp_write_enable = direct_commit_valid &&
            (instruction_uop.opcode == MX_UOP_MOVE) &&
            (instruction_uop.destination.kind == MX_OPERAND_USP);
        rf_usp_write_value = direct_result_value;
        rf_address_write_enable_b =
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_EXCHANGE) &&
             (instruction_uop.source_a.kind ==
              MX_OPERAND_ADDRESS_REGISTER) &&
             (instruction_uop.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER)) ||
            (data_commit_valid &&
            (pending_address_update_b_q ||
             ((pending_memory_action_q == MEMORY_ACTION_MOVEM_LOAD) &&
              pending_address_update_q) ||
             ((pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
              (pending_memory_uop_q.opcode == MX_UOP_MOVE_ADDRESS) &&
              pending_address_update_q) ||
             ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
              (pending_memory_uop_q.destination.kind ==
               MX_OPERAND_ADDRESS_REGISTER) &&
              (pending_memory_uop_q.opcode inside {
               MX_UOP_ADD, MX_UOP_SUBTRACT}) &&
              pending_address_update_q &&
              (pending_address_update_index_q !=
               pending_memory_uop_q.destination.index[2:0]))));
        rf_address_write_index_b =
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_EXCHANGE)) ?
            instruction_uop.source_a.index[2:0] :
            ((pending_memory_action_q == MEMORY_ACTION_MOVEM_LOAD) ||
             ((pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
              (pending_memory_uop_q.opcode == MX_UOP_MOVE_ADDRESS))) ?
            pending_address_update_index_q :
            ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
             (pending_memory_uop_q.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER) &&
             pending_address_update_q) ?
            pending_address_update_index_q : pending_address_update_index_b_q;
        rf_address_write_value_b =
            (direct_commit_valid &&
             (instruction_uop.opcode == MX_UOP_EXCHANGE)) ?
            destination_operand_value :
            ((pending_memory_action_q == MEMORY_ACTION_MOVEM_LOAD) ||
             ((pending_memory_action_q == MEMORY_ACTION_MOVE_LOAD) &&
              (pending_memory_uop_q.opcode == MX_UOP_MOVE_ADDRESS))) ?
            pending_address_update_value_q :
            ((pending_memory_action_q == MEMORY_ACTION_ALU_LOAD) &&
             (pending_memory_uop_q.destination.kind ==
              MX_OPERAND_ADDRESS_REGISTER) &&
             pending_address_update_q) ?
            pending_address_update_value_q : pending_address_update_value_b_q;
        exception_entry_sr =
            ((pending_exception_sr_q | 16'h2000) & 16'h3fff);
        if (pending_exception_q.exception_class == MX_EXC_INTERRUPT)
            exception_entry_sr[MX_SR_I2:MX_SR_I0] =
                pending_interrupt_level_q;
        rf_sr_write_enable = (direct_commit_valid && direct_writes_sr) ||
                             (data_commit_valid &&
                              (pending_writes_flags ||
                               ((pending_memory_action_q ==
                                 MEMORY_ACTION_MOVE_LOAD) &&
                                (pending_memory_uop_q.opcode == MX_UOP_MOVE) &&
                                (pending_memory_uop_q.destination.kind ==
                                 MX_OPERAND_SR)))) ||
                             chk_operand_commit_valid ||
                             exception_entry_commit_valid || rte_commit_valid ||
                             rtr_commit_valid;
        rf_sr_write_value = exception_entry_commit_valid ?
            exception_entry_sr :
            rte_commit_valid ? pending_source_operand_q[15:0] :
            rtr_commit_valid ? {debug_sr[15:8],
                                pending_source_operand_q[7:0]} :
            chk_operand_commit_valid ? data_chk_sr :
            data_commit_valid ? data_sr_value : direct_sr_value;
        rf_pc_write_enable = direct_commit_valid || data_commit_valid ||
                             exception_entry_commit_valid || rte_commit_valid ||
                             rtr_commit_valid || reset_instruction_commit_valid;
        rf_pc_write_value = exception_entry_commit_valid ?
            data_response_value :
            (rte_commit_valid || rtr_commit_valid) ? data_response_value :
            reset_instruction_commit_valid ?
                pending_memory_uop_q.sequential_pc :
                instruction_uop.sequential_pc;
        if (data_commit_valid) begin
            case (pending_memory_action_q)
                MEMORY_ACTION_JSR_PUSH:
                    rf_pc_write_value = pending_control_target_q;
                MEMORY_ACTION_RTS_POP:
                    rf_pc_write_value = data_response_value;
                default:
                    rf_pc_write_value = pending_memory_uop_q.sequential_pc;
            endcase
        end
        if (direct_commit_valid &&
            (instruction_uop.opcode == MX_UOP_BRANCH) && branch_taken)
            rf_pc_write_value = instruction_uop.immediate;
        if (direct_commit_valid &&
            (instruction_uop.opcode == MX_UOP_DBCC) && dbcc_taken)
            rf_pc_write_value = instruction_uop.immediate;
        if (direct_commit_valid &&
            (instruction_uop.opcode == MX_UOP_JUMP))
            rf_pc_write_value = source_ea_address;
        rf_ssp_write_enable = exception_entry_commit_valid || rte_commit_valid;
        rf_ssp_write_value = exception_entry_commit_valid ?
            (debug_ssp - (pending_exception_special ? 32'd14 : 32'd6)) :
            pending_control_target_q;

        reset_devices_n = (state_q != CORE_RESET_DEVICES);
        stopped = (state_q == CORE_STOPPED);
        faulted = (state_q == CORE_FAULTED);
        terminal_exception = terminal_exception_q;
        irq.acknowledge = interrupt_ack_q;
        irq.acknowledged_level = interrupt_ack_level_q;
    end

    property retired_instruction_is_successful;
        @(posedge clk) disable iff (!rst_n)
            retire_valid |-> $past(
                (direct_commit_valid && instruction_handshake) ||
                data_commit_valid || rte_commit_valid || rtr_commit_valid ||
                reset_instruction_commit_valid);
    endproperty
    assert property (retired_instruction_is_successful);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= CORE_RESET_SEND;
            terminal_exception_q <= '0;
            redirect_pending_q <= 1'b0;
            redirect_target_q <= '0;
            pending_memory_uop_q <= '0;
            pending_memory_action_q <= MEMORY_ACTION_NONE;
            pending_memory_address_q <= '0;
            pending_memory_write_value_q <= '0;
            split_access_second_q <= 1'b0;
            split_read_high_q <= '0;
            split_base_address_q <= '0;
            pending_control_target_q <= '0;
            pending_address_update_q <= 1'b0;
            pending_address_update_index_q <= '0;
            pending_address_update_value_q <= '0;
            pending_destination_original_q <= '0;
            pending_source_operand_q <= '0;
            pending_second_address_q <= '0;
            pending_address_update_b_q <= 1'b0;
            pending_address_update_index_b_q <= '0;
            pending_address_update_value_b_q <= '0;
            pending_movem_mask_q <= '0;
            pending_movem_bit_q <= '0;
            pending_exception_q <= '0;
            pending_exception_sr_q <= '0;
            pending_interrupt_level_q <= '0;
            interrupt_ack_q <= 1'b0;
            interrupt_ack_level_q <= '0;
            interrupt_level7_seen_q <= 1'b0;
            interrupt_level7_pending_q <= 1'b0;
            trace_pending_q <= 1'b0;
            trace_pending_pc_q <= '0;
            trace_pending_sr_q <= '0;
            pending_instruction_trace_q <= 1'b0;
            trace_after_exception_q <= 1'b0;
            sequence_program_q <= MX_SEQUENCE_NONE;
            sequence_step_q <= MX_SEQUENCE_IDLE;
            sequence_checkpoint_index_q <= '0;
            sequence_checkpoint_value_q <= '0;
            reset_devices_cycles_q <= '0;
            retire_valid <= 1'b0;
            retire_pc <= '0;
            retire_instruction_id <= '0;
        end else begin
            retire_valid <= 1'b0;
            interrupt_ack_q <= 1'b0;
            if (redirect_pending_q)
                redirect_pending_q <= 1'b0;

            interrupt_level7_seen_q <= interrupt_level7_active;
            if (interrupt_level7_rise)
                interrupt_level7_pending_q <= 1'b1;
            if (interrupt_take && (active_interrupt_level == 3'd7))
                interrupt_level7_pending_q <= 1'b0;

            case (state_q)
                CORE_RESET_SEND: begin
                    if (dmem.req_valid && dmem.req_ready)
                        state_q <= CORE_RESET_WAIT;
                end

                CORE_RESET_WAIT: begin
                    if (reset_response_handshake) begin
                        if (reset_response_fault == MX_FAULT_NONE) begin
                            state_q <= CORE_START_FRONTEND;
                        end else begin
                            terminal_exception_q <= make_terminal_exception(
                                MX_VECTOR_ACCESS_FAULT, MX_EXC_RESET,
                                MX_FAULT_STAGE_FETCH, 32'd0, 32'd0);
                            state_q <= CORE_FAULTED;
                        end
                    end
                end

                CORE_START_FRONTEND: state_q <= CORE_RUN;

                CORE_RUN: begin
                    if (trace_pending_q) begin
                        pending_exception_q <= make_trace_exception(
                            trace_pending_pc_q);
                        pending_exception_sr_q <= trace_pending_sr_q;
                        pending_memory_action_q <=
                            MEMORY_ACTION_EXCEPTION_PUSH_PC;
                        pending_memory_address_q <= debug_ssp - 32'd4;
                        pending_memory_write_value_q <= trace_pending_pc_q;
                        trace_pending_q <= 1'b0;
                        state_q <= CORE_DATA_SEND;
                    end else if (interrupt_take) begin
                        pending_exception_q <= make_interrupt_exception(
                            accepted_interrupt_vector, debug_pc);
                        pending_exception_sr_q <= debug_sr;
                        pending_interrupt_level_q <= active_interrupt_level;
                        pending_memory_action_q <=
                            MEMORY_ACTION_EXCEPTION_PUSH_PC;
                        pending_memory_address_q <= debug_ssp - 32'd4;
                        pending_memory_write_value_q <= debug_pc;
                        interrupt_ack_q <= 1'b1;
                        interrupt_ack_level_q <= active_interrupt_level;
                        state_q <= CORE_DATA_SEND;
                    end else if (instruction_handshake) begin
                        if (instruction_exception.valid) begin
                            if (instruction_exception.vector inside {
                                MX_VECTOR_ACCESS_FAULT,
                                MX_VECTOR_ADDRESS_ERROR}) begin
                                pending_exception_q <=
                                    make_m00_fetch_exception(
                                        instruction_exception,
                                        debug_sr[MX_SR_S]);
                                pending_exception_sr_q <= debug_sr;
                                pending_memory_action_q <=
                                    MEMORY_ACTION_EXCEPTION_PUSH_PC;
                                pending_memory_address_q <= debug_ssp - 32'd4;
                                pending_memory_write_value_q <=
                                    instruction_exception.next_pc;
                                trace_after_exception_q <= 1'b0;
                                state_q <= CORE_DATA_SEND;
                            end else begin
                                pending_exception_q <= instruction_exception;
                                pending_exception_sr_q <= debug_sr;
                                pending_memory_action_q <=
                                    MEMORY_ACTION_EXCEPTION_PUSH_PC;
                                pending_memory_address_q <= debug_ssp - 32'd4;
                                pending_memory_write_value_q <=
                                    instruction_exception.instruction_pc;
                                state_q <= CORE_DATA_SEND;
                            end
                        end else if (privilege_fault) begin
                            pending_exception_q <= make_execute_exception(
                                MX_VECTOR_PRIVILEGE, instruction_uop);
                            pending_exception_sr_q <= debug_sr;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                instruction_uop.instruction_pc;
                            state_q <= CORE_DATA_SEND;
                        end else if (!execute_supported) begin
                            pending_exception_q <= make_execute_exception(
                                MX_VECTOR_ILLEGAL, instruction_uop);
                            pending_exception_sr_q <= debug_sr;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                instruction_uop.instruction_pc;
                            state_q <= CORE_DATA_SEND;
                        end else if ((instruction_uop.opcode ==
                                     MX_UOP_DIVIDE) &&
                                    !starts_memory_sequence) begin
                            // DIVU/DIVS use the iterative execute unit.  Keep
                            // the complete architectural context stable until
                            // it reports either a result or the zero-divisor
                            // trap; no register state is committed here.
                            pending_memory_uop_q <= instruction_uop;
                            pending_memory_action_q <=
                                MEMORY_ACTION_ALU_LOAD;
                            pending_destination_original_q <=
                                destination_operand_value;
                            pending_address_update_q <= 1'b0;
                            pending_address_update_b_q <= 1'b0;
                            pending_instruction_trace_q <=
                                debug_sr[MX_SR_T1];
                            state_q <= CORE_DIVIDE_WAIT;
                        end else if (direct_chk_trap) begin
                            pending_exception_q <=
                                make_instruction_trap_exception(
                                MX_VECTOR_CHK, instruction_uop);
                            trace_after_exception_q <= debug_sr[MX_SR_T1];
                            pending_exception_sr_q <= direct_chk_sr;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                instruction_uop.sequential_pc;
                            state_q <= CORE_DATA_SEND;
                        end else if (trap_taken) begin
                            pending_exception_q <=
                                make_instruction_trap_exception(
                                instruction_uop.exception_vector,
                                instruction_uop);
                            trace_after_exception_q <= debug_sr[MX_SR_T1];
                            pending_exception_sr_q <= debug_sr;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                instruction_uop.sequential_pc;
                            state_q <= CORE_DATA_SEND;
                        end else if (instruction_uop.opcode == MX_UOP_RESET) begin
                            // M68000PRM 6-82 / MC68000UM 5.5.3: RESET is a
                            // privileged, 124-clock external-device reset.
                            // It does not alter the processor's registers or
                            // SR and only retires after the pulse completes.
                            pending_memory_uop_q <= instruction_uop;
                            reset_devices_cycles_q <= 7'd0;
                            state_q <= CORE_RESET_DEVICES;
                        end else begin
                            if (starts_memory_sequence) begin
                                pending_memory_uop_q <= instruction_uop;
                                pending_memory_action_q <= MEMORY_ACTION_NONE;
                                pending_memory_address_q <=
                                    instruction_uop.memory_address;
                                pending_memory_write_value_q <=
                                    source_operand_value;
                                pending_control_target_q <= '0;
                                pending_address_update_q <= 1'b0;
                                pending_address_update_index_q <= '0;
                                pending_address_update_value_q <= '0;
                                // The destination may be An (ADDA/SUBA).  Do
                                // not capture the numerically corresponding
                                // Dn read port while a memory source is in
                                // flight.
                                pending_destination_original_q <=
                                    destination_operand_value;
                                pending_source_operand_q <= source_operand_value;
                                pending_second_address_q <= '0;
                                pending_address_update_b_q <= 1'b0;
                                pending_address_update_index_b_q <= '0;
                                pending_address_update_value_b_q <= '0;
                                pending_movem_mask_q <= '0;
                                pending_movem_bit_q <= '0;
                                pending_instruction_trace_q <=
                                    debug_sr[MX_SR_T1];
                                sequence_program_q <= MX_SEQUENCE_NONE;
                                sequence_step_q <= MX_SEQUENCE_IDLE;
                                sequence_checkpoint_index_q <= '0;
                                sequence_checkpoint_value_q <= '0;

                                case (instruction_uop.opcode)
                                    MX_UOP_COMPARE_MEMORY: begin
                                        // CMPM is the first client of the
                                        // common ordered-memory sequencer:
                                        // READ_SOURCE/checkpoint followed by
                                        // READ_DESTINATION/final commit.
                                        sequence_program_q <= MX_SEQUENCE_CMPM;
                                        sequence_step_q <=
                                            MX_SEQUENCE_READ_SOURCE;
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_SEQUENCE_READ;
                                        pending_memory_address_q <=
                                            rf_address_read_a;
                                        pending_second_address_q <=
                                            (instruction_uop.source_ea.
                                                 register_index ==
                                             instruction_uop.destination_ea.
                                                 register_index) ?
                                            (rf_address_read_a +
                                             sequence_source_step) :
                                            rf_address_read_b;
                                        sequence_checkpoint_index_q <=
                                            instruction_uop.source_ea.
                                                register_index;
                                        sequence_checkpoint_value_q <=
                                            rf_address_read_a +
                                            sequence_source_step;
                                        pending_address_update_q <= 1'b1;
                                        pending_address_update_index_q <=
                                            instruction_uop.destination_ea.
                                                register_index;
                                        pending_address_update_value_q <=
                                            (instruction_uop.source_ea.
                                                 register_index ==
                                             instruction_uop.destination_ea.
                                                 register_index) ?
                                            (rf_address_read_a +
                                             sequence_source_step +
                                             sequence_destination_step) :
                                            (rf_address_read_b +
                                             sequence_destination_step);
                                    end
                                    MX_UOP_MOVE,
                                    MX_UOP_MOVE_ADDRESS: begin
                                        if (mx_ea_is_memory(
                                            instruction_uop.source_ea)) begin
                                            pending_memory_action_q <=
                                                mx_ea_is_memory(
                                                    instruction_uop.
                                                    destination_ea) ?
                                                MEMORY_ACTION_MOVE_LOAD_TO_STORE :
                                                MEMORY_ACTION_MOVE_LOAD;
                                            pending_memory_address_q <=
                                                source_ea_address;
                                            pending_second_address_q <=
                                                destination_ea_address;
                                            if (mx_ea_is_memory(
                                                instruction_uop.
                                                destination_ea)) begin
                                                if (instruction_uop.
                                                    destination_ea.kind ==
                                                    MX_EA_PREDECREMENT) begin
                                                    pending_address_update_b_q <=
                                                        1'b1;
                                                    pending_address_update_index_b_q <=
                                                        instruction_uop.
                                                        destination_ea.
                                                        register_index;
                                                    pending_address_update_value_b_q <=
                                                        destination_ea_address;
                                                end else if (instruction_uop.
                                                    destination_ea.kind ==
                                                    MX_EA_POSTINCREMENT) begin
                                                    pending_address_update_b_q <=
                                                        1'b1;
                                                    pending_address_update_index_b_q <=
                                                        instruction_uop.
                                                        destination_ea.
                                                        register_index;
                                                    pending_address_update_value_b_q <=
                                                        rf_address_read_b +
                                                        mx_ea_step_bytes(
                                                            instruction_uop.size,
                                                            instruction_uop.
                                                            destination_ea.
                                                            register_index);
                                                end
                                            end
                                            if (instruction_uop.source_ea.kind ==
                                                MX_EA_PREDECREMENT) begin
                                                pending_address_update_q <= 1'b1;
                                                pending_address_update_index_q <=
                                                    instruction_uop.source_ea.
                                                    register_index;
                                                pending_address_update_value_q <=
                                                    source_ea_address;
                                            end else if
                                                (instruction_uop.source_ea.kind ==
                                                 MX_EA_POSTINCREMENT) begin
                                                pending_address_update_q <= 1'b1;
                                                pending_address_update_index_q <=
                                                    instruction_uop.source_ea.
                                                    register_index;
                                                pending_address_update_value_q <=
                                                    rf_address_read_a +
                                                    mx_ea_step_bytes(
                                                        instruction_uop.size,
                                                        instruction_uop.source_ea.
                                                        register_index);
                                            end
                                        end else begin
                                            pending_memory_action_q <=
                                                (instruction_uop.source_a.kind ==
                                                 MX_OPERAND_SR) ?
                                                MEMORY_ACTION_RMW_LOAD :
                                                MEMORY_ACTION_MOVE_STORE;
                                            pending_memory_address_q <=
                                                destination_ea_address;
                                            pending_memory_write_value_q <=
                                                source_operand_value;
                                            if (instruction_uop.destination_ea.kind ==
                                                MX_EA_PREDECREMENT) begin
                                                pending_address_update_q <= 1'b1;
                                                pending_address_update_index_q <=
                                                    instruction_uop.destination_ea.
                                                    register_index;
                                                pending_address_update_value_q <=
                                                    destination_ea_address;
                                            end else if
                                                (instruction_uop.destination_ea.kind ==
                                                 MX_EA_POSTINCREMENT) begin
                                                pending_address_update_q <= 1'b1;
                                                pending_address_update_index_q <=
                                                    instruction_uop.destination_ea.
                                                    register_index;
                                                pending_address_update_value_q <=
                                                    rf_address_read_b +
                                                    mx_ea_step_bytes(
                                                        instruction_uop.size,
                                                        instruction_uop.
                                                        destination_ea.
                                                        register_index);
                                            end
                                        end
                                    end
                                    MX_UOP_STORE: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_MOVE_STORE;
                                        pending_memory_address_q <=
                                            instruction_uop.memory_address;
                                        pending_memory_write_value_q <=
                                            source_operand_value;
                                    end
                                    MX_UOP_ADD_EXTEND,
                                    MX_UOP_SUBTRACT_EXTEND: begin
                                        if (mx_ea_is_memory(
                                                instruction_uop.source_ea)) begin
                                            // M68000PRM 4-13/4-14 and
                                            // 4-183/4-184: memory ADDX/SUBX
                                            // first reads the independently
                                            // predecremented source, then the
                                            // independently predecremented
                                            // destination, and finally writes
                                            // the destination.  If both fields
                                            // name the same An, the second EA
                                            // observes the first decrement.
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_EXTEND_SOURCE_LOAD;
                                            pending_memory_address_q <=
                                                source_ea_address;
                                            pending_second_address_q <=
                                                (instruction_uop.source_ea.
                                                     register_index ==
                                                 instruction_uop.destination_ea.
                                                     register_index) ?
                                                (destination_ea_address -
                                                 mx_ea_step_bytes(
                                                     instruction_uop.size,
                                                     instruction_uop.
                                                     destination_ea.
                                                     register_index)) :
                                                destination_ea_address;
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.source_ea.
                                                    register_index;
                                            pending_address_update_value_q <=
                                                (instruction_uop.source_ea.
                                                     register_index ==
                                                 instruction_uop.destination_ea.
                                                     register_index) ?
                                                (destination_ea_address -
                                                 mx_ea_step_bytes(
                                                     instruction_uop.size,
                                                     instruction_uop.
                                                     destination_ea.
                                                     register_index)) :
                                                source_ea_address;
                                            if (instruction_uop.source_ea.
                                                    register_index !=
                                                instruction_uop.destination_ea.
                                                    register_index) begin
                                                pending_address_update_b_q <=
                                                    1'b1;
                                                pending_address_update_index_b_q <=
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index;
                                                pending_address_update_value_b_q <=
                                                    destination_ea_address;
                                            end
                                        end else begin
                                            // Unary NEGX uses the same ALU
                                            // operation but has only one RMW
                                            // destination operand.
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_RMW_LOAD;
                                            pending_memory_address_q <=
                                                destination_ea_address;
                                            if (instruction_uop.destination_ea.kind ==
                                                MX_EA_PREDECREMENT) begin
                                                pending_address_update_q <= 1'b1;
                                                pending_address_update_index_q <=
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index;
                                                pending_address_update_value_q <=
                                                    destination_ea_address;
                                            end else if
                                                (instruction_uop.destination_ea.kind ==
                                                 MX_EA_POSTINCREMENT) begin
                                                pending_address_update_q <= 1'b1;
                                                pending_address_update_index_q <=
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index;
                                                pending_address_update_value_q <=
                                                    rf_address_read_b +
                                                    mx_ea_step_bytes(
                                                        instruction_uop.size,
                                                        instruction_uop.
                                                        destination_ea.
                                                        register_index);
                                            end
                                        end
                                    end
                                    MX_UOP_ADD,
                                    MX_UOP_SUBTRACT,
                                    MX_UOP_AND,
                                    MX_UOP_OR,
                                    MX_UOP_XOR,
                                    MX_UOP_MULTIPLY,
                                    MX_UOP_DIVIDE,
                                    MX_UOP_CHECK_BOUNDS,
                                    MX_UOP_COMPARE: begin
                                        if ((instruction_uop.opcode ==
                                             MX_UOP_COMPARE) &&
                                            mx_ea_is_memory(
                                             instruction_uop.destination_ea)) begin
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_ALU_LOAD;
                                            pending_memory_address_q <=
                                                destination_ea_address;
                                        end else if (mx_ea_is_memory(
                                            instruction_uop.destination_ea)) begin
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_RMW_LOAD;
                                            pending_memory_address_q <=
                                                destination_ea_address;
                                        end else begin
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_ALU_LOAD;
                                            pending_memory_address_q <=
                                                source_ea_address;
                                        end
                                        if ((mx_ea_is_memory(
                                             instruction_uop.destination_ea) &&
                                             (instruction_uop.destination_ea.kind ==
                                              MX_EA_PREDECREMENT)) ||
                                            (!mx_ea_is_memory(
                                             instruction_uop.destination_ea) &&
                                             (instruction_uop.source_ea.kind ==
                                              MX_EA_PREDECREMENT))) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                mx_ea_is_memory(
                                                    instruction_uop.destination_ea) ?
                                                instruction_uop.destination_ea.
                                                    register_index :
                                                instruction_uop.source_ea.
                                                    register_index;
                                            pending_address_update_value_q <=
                                                mx_ea_is_memory(
                                                    instruction_uop.destination_ea) ?
                                                destination_ea_address :
                                                source_ea_address;
                                            // Address-register arithmetic has
                                            // one architecturally visible An
                                            // result.  When its memory source
                                            // predecrements that same An, the
                                            // decremented address is the
                                            // arithmetic destination value.
                                            if (!mx_ea_is_memory(
                                                    instruction_uop.
                                                    destination_ea) &&
                                                (instruction_uop.destination.kind ==
                                                 MX_OPERAND_ADDRESS_REGISTER) &&
                                                (instruction_uop.source_ea.
                                                 register_index ==
                                                 instruction_uop.destination.
                                                 index[2:0]))
                                                pending_destination_original_q <=
                                                    source_ea_address;
                                        end else if
                                            ((mx_ea_is_memory(
                                              instruction_uop.destination_ea) &&
                                              (instruction_uop.destination_ea.kind ==
                                               MX_EA_POSTINCREMENT)) ||
                                             (!mx_ea_is_memory(
                                              instruction_uop.destination_ea) &&
                                              (instruction_uop.source_ea.kind ==
                                               MX_EA_POSTINCREMENT))) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                mx_ea_is_memory(
                                                    instruction_uop.destination_ea) ?
                                                instruction_uop.destination_ea.
                                                    register_index :
                                                instruction_uop.source_ea.
                                                    register_index;
                                            pending_address_update_value_q <=
                                                (mx_ea_is_memory(
                                                    instruction_uop.destination_ea) ?
                                                 rf_address_read_b :
                                                 rf_address_read_a) +
                                                mx_ea_step_bytes(
                                                    instruction_uop.size,
                                                    mx_ea_is_memory(
                                                        instruction_uop.
                                                        destination_ea) ?
                                                    instruction_uop.destination_ea.
                                                        register_index :
                                                    instruction_uop.source_ea.
                                                        register_index);
                                            // Likewise, ADDA/SUBA (An)+,An
                                            // operates on An after the source
                                            // EA postincrement.  Linux uses
                                            // ADDA.L (SP)+,SP in its interrupt
                                            // return path.
                                            if (!mx_ea_is_memory(
                                                    instruction_uop.
                                                    destination_ea) &&
                                                (instruction_uop.destination.kind ==
                                                 MX_OPERAND_ADDRESS_REGISTER) &&
                                                (instruction_uop.source_ea.
                                                 register_index ==
                                                 instruction_uop.destination.
                                                 index[2:0]))
                                                pending_destination_original_q <=
                                                    rf_address_read_a +
                                                    mx_ea_step_bytes(
                                                        instruction_uop.size,
                                                        instruction_uop.source_ea.
                                                        register_index);
                                        end
                                    end
                                    MX_UOP_CLEAR: begin
                                        pending_memory_action_q <=
                                            // M68000PRM 4-74: MC68000 and
                                            // MC68008 read a memory location
                                            // before clearing it.
                                            MEMORY_ACTION_RMW_LOAD;
                                        pending_memory_address_q <=
                                            destination_ea_address;
                                        pending_memory_write_value_q <= 32'd0;
                                        if (instruction_uop.destination_ea.kind ==
                                            MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                destination_ea_address;
                                        end else if
                                            (instruction_uop.destination_ea.kind ==
                                             MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_b +
                                                mx_ea_step_bytes(
                                                    instruction_uop.size,
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index);
                                        end
                                    end
                                    MX_UOP_SET_CONDITION: begin
                                        pending_memory_action_q <=
                                            // M68000PRM 4-173: unlike later
                                            // family members, MC68000/68008
                                            // read a memory destination before
                                            // writing the Scc result.
                                            MEMORY_ACTION_RMW_LOAD;
                                        pending_memory_address_q <=
                                            destination_ea_address;
                                        pending_memory_write_value_q <=
                                            direct_result_value;
                                        if (instruction_uop.destination_ea.kind ==
                                            MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                destination_ea_address;
                                        end else if
                                            (instruction_uop.destination_ea.kind ==
                                             MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_b +
                                                mx_ea_step_bytes(
                                                    instruction_uop.size,
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index);
                                        end
                                    end
                                    MX_UOP_ATOMIC: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_ATOMIC;
                                        pending_memory_address_q <=
                                            destination_ea_address;
                                        pending_memory_write_value_q <=
                                            32'h0000_0080;
                                        if (instruction_uop.destination_ea.kind ==
                                            MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                destination_ea_address;
                                        end else if
                                            (instruction_uop.destination_ea.kind ==
                                             MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_b +
                                                mx_ea_step_bytes(
                                                    MX_OP_BYTE,
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index);
                                        end
                                    end
                                    MX_UOP_NOT,
                                    MX_UOP_NEGATE,
                                    MX_UOP_SHIFT: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_RMW_LOAD;
                                        pending_memory_address_q <=
                                            destination_ea_address;
                                        if (instruction_uop.destination_ea.kind ==
                                            MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                destination_ea_address;
                                        end else if
                                            (instruction_uop.destination_ea.kind ==
                                             MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_b +
                                                mx_ea_step_bytes(
                                                    instruction_uop.size,
                                                    instruction_uop.
                                                    destination_ea.
                                                    register_index);
                                        end
                                    end
                                    MX_UOP_TEST: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_TEST_LOAD;
                                        pending_memory_address_q <=
                                            source_ea_address;
                                        if (instruction_uop.source_ea.kind ==
                                            MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.source_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_a +
                                                mx_ea_step_bytes(
                                                    instruction_uop.size,
                                                    instruction_uop.source_ea.
                                                    register_index);
                                        end else if
                                            (instruction_uop.source_ea.kind ==
                                             MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.source_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                source_ea_address;
                                        end
                                    end
                                    MX_UOP_BIT_TEST: begin
                                        pending_memory_action_q <=
                                            (instruction_uop.condition[1:0] ==
                                             2'b00) ?
                                            MEMORY_ACTION_BIT_TEST_LOAD :
                                            MEMORY_ACTION_RMW_LOAD;
                                        pending_memory_address_q <=
                                            destination_ea_address;
                                        if (instruction_uop.destination_ea.kind ==
                                            MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_b +
                                                mx_ea_step_bytes(
                                                    instruction_uop.size,
                                                    instruction_uop.destination_ea.
                                                    register_index);
                                        end else if
                                            (instruction_uop.destination_ea.kind ==
                                             MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.destination_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                destination_ea_address;
                                        end
                                    end
                                    MX_UOP_JUMP_SUBROUTINE,
                                    MX_UOP_BRANCH_SUBROUTINE: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_JSR_PUSH;
                                        pending_memory_address_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4;
                                        pending_memory_write_value_q <=
                                            instruction_uop.sequential_pc;
                                        pending_control_target_q <=
                                            (instruction_uop.opcode ==
                                             MX_UOP_BRANCH_SUBROUTINE) ?
                                            instruction_uop.immediate :
                                            source_ea_address;
                                        pending_address_update_q <= 1'b1;
                                        pending_address_update_index_q <= 3'd7;
                                        pending_address_update_value_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4;
                                    end
                                    MX_UOP_RETURN: begin
                                        pending_memory_address_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7);
                                        if (instruction_uop.condition[0]) begin
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_RTR_LOAD_CCR;
                                            pending_control_target_q <=
                                                packed_register_value(
                                                    debug_address_registers,
                                                    3'd7) + 32'd6;
                                        end else begin
                                            pending_memory_action_q <=
                                                MEMORY_ACTION_RTS_POP;
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <= 3'd7;
                                            pending_address_update_value_q <=
                                                packed_register_value(
                                                    debug_address_registers,
                                                    3'd7) + 32'd4;
                                        end
                                    end
                                    MX_UOP_PUSH_EFFECTIVE_ADDRESS: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_PEA_PUSH;
                                        pending_memory_address_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4;
                                        pending_memory_write_value_q <=
                                            source_ea_address;
                                        pending_address_update_q <= 1'b1;
                                        pending_address_update_index_q <= 3'd7;
                                        pending_address_update_value_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4;
                                    end
                                    MX_UOP_MOVE_MULTIPLE: begin
                                        pending_memory_action_q <=
                                            instruction_uop.condition[0] ?
                                            MEMORY_ACTION_MOVEM_LOAD :
                                            MEMORY_ACTION_MOVEM_STORE;
                                        pending_movem_mask_q <=
                                            instruction_uop.immediate[15:0];
                                        pending_movem_bit_q <= first_set_bit(
                                            instruction_uop.immediate[15:0]);
                                        pending_memory_address_q <=
                                            source_ea_address;
                                        pending_memory_write_value_q <=
                                            movem_register_value(
                                                first_set_bit(
                                                    instruction_uop.
                                                    immediate[15:0]),
                                                instruction_uop.source_ea.kind ==
                                                    MX_EA_PREDECREMENT,
                                                debug_data_registers,
                                                debug_address_registers);
                                        if (instruction_uop.source_ea.kind ==
                                            MX_EA_PREDECREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.source_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_a -
                                                (register_mask_count(
                                                    instruction_uop.
                                                    immediate[15:0]) *
                                                 ((instruction_uop.size ==
                                                   MX_OP_WORD) ? 5'd2 :
                                                                  5'd4));
                                        end else if
                                            (instruction_uop.source_ea.kind ==
                                             MX_EA_POSTINCREMENT) begin
                                            pending_address_update_q <= 1'b1;
                                            pending_address_update_index_q <=
                                                instruction_uop.source_ea.
                                                register_index;
                                            pending_address_update_value_q <=
                                                rf_address_read_a +
                                                (register_mask_count(
                                                    instruction_uop.
                                                    immediate[15:0]) *
                                                 ((instruction_uop.size ==
                                                   MX_OP_WORD) ? 5'd2 :
                                                                  5'd4));
                                        end
                                    end
                                    MX_UOP_LINK: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_LINK_PUSH;
                                        pending_memory_address_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4;
                                        // PRM 4-110 gives the operations in
                                        // architectural order: SP is first
                                        // decremented, then An is stored.  If
                                        // An is A7, the value being stored is
                                        // therefore the decremented SP rather
                                        // than its value on instruction entry.
                                        pending_memory_write_value_q <=
                                            (instruction_uop.source_ea.
                                             register_index == 3'd7) ?
                                            (packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4) :
                                            rf_address_read_a;
                                        pending_address_update_q <= 1'b1;
                                        pending_address_update_index_q <=
                                            instruction_uop.source_ea.
                                            register_index;
                                        pending_address_update_value_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4;
                                        pending_address_update_b_q <= 1'b1;
                                        pending_address_update_index_b_q <=
                                            3'd7;
                                        pending_address_update_value_b_q <=
                                            packed_register_value(
                                                debug_address_registers,
                                                3'd7) - 32'd4 +
                                            instruction_uop.immediate;
                                    end
                                    MX_UOP_UNLINK: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_UNLINK_POP;
                                        pending_memory_address_q <=
                                            rf_address_read_a;
                                        // For UNLK A7, the pulled value and
                                        // the final SP are the same register:
                                        // (SP)->A7 followed by SP+4->SP.  The
                                        // primary write port commits that
                                        // final value below; a second write
                                        // with the old address would violate
                                        // the documented ordering.
                                        pending_address_update_b_q <=
                                            instruction_uop.source_ea.
                                            register_index != 3'd7;
                                        pending_address_update_index_b_q <=
                                            3'd7;
                                        pending_address_update_value_b_q <=
                                            rf_address_read_a + 32'd4;
                                    end
                                    MX_UOP_EXCEPTION_RETURN: begin
                                        pending_memory_action_q <=
                                            MEMORY_ACTION_RTE_LOAD_SR;
                                        pending_memory_address_q <= debug_ssp;
                                        pending_control_target_q <=
                                            debug_ssp + 32'd6;
                                    end
                                    default: begin end
                                endcase
                                state_q <= CORE_DATA_SEND;
                            end else begin
                                retire_valid <= 1'b1;
                                retire_pc <= instruction_uop.instruction_pc;
                                retire_instruction_id <= instruction_uop.instruction_id;

                                if (debug_sr[MX_SR_T1]) begin
                                    trace_pending_q <= 1'b1;
                                    trace_pending_pc_q <= rf_pc_write_value;
                                    trace_pending_sr_q <= direct_writes_sr ?
                                        direct_sr_value : debug_sr;
                                end

                                if ((instruction_uop.opcode == MX_UOP_BRANCH) &&
                                    branch_taken) begin
                                    redirect_target_q <= instruction_uop.immediate;
                                    redirect_pending_q <= 1'b1;
                                end
                                if ((instruction_uop.opcode == MX_UOP_DBCC) &&
                                    dbcc_taken) begin
                                    redirect_target_q <= instruction_uop.immediate;
                                    redirect_pending_q <= 1'b1;
                                end
                                if (instruction_uop.opcode == MX_UOP_JUMP) begin
                                    redirect_target_q <= source_ea_address;
                                    redirect_pending_q <= 1'b1;
                                end

                                if (instruction_uop.opcode == MX_UOP_STOP)
                                    state_q <= debug_sr[MX_SR_T1] ?
                                               CORE_RUN : CORE_STOPPED;
                            end
                        end
                    end
                end

                CORE_DATA_SEND: begin
                    if (data_request_alignment_error) begin
                        split_access_second_q <= 1'b0;
                        sequence_program_q <= MX_SEQUENCE_NONE;
                        sequence_step_q <= MX_SEQUENCE_IDLE;
                        if (pending_action_is_exception_frame) begin
                            terminal_exception_q <= make_frame_exception(
                                pending_exception_q,
                                pending_memory_address_q);
                            state_q <= CORE_FAULTED;
                        end else begin
                            pending_exception_q <= make_data_exception(
                                MX_FAULT_ALIGNMENT,
                                pending_memory_uop_q,
                                pending_memory_address_q,
                                pending_request_is_write,
                                debug_sr[MX_SR_S]);
                            pending_exception_sr_q <= debug_sr;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                pending_memory_uop_q.sequential_pc;
                            pending_instruction_trace_q <= 1'b0;
                            trace_after_exception_q <= 1'b0;
                            state_q <= CORE_DATA_SEND;
                        end
                    end else if (dmem.req_valid && dmem.req_ready)
                        state_q <= CORE_DATA_WAIT;
                end

                CORE_DATA_WAIT: begin
                    if (data_response_handshake) begin
                        // A fault is attributed to the exact beat that failed.
                        // A successful first split beat is the only path that
                        // reasserts this state below.
                        split_access_second_q <= 1'b0;
                        if (data_response_fault != MX_FAULT_NONE) begin
                            sequence_program_q <= MX_SEQUENCE_NONE;
                            sequence_step_q <= MX_SEQUENCE_IDLE;
                            if (pending_action_is_exception_frame)
                                terminal_exception_q <= make_frame_exception(
                                    pending_exception_q,
                                    pending_memory_address_q);
                            else begin
                                pending_exception_q <= make_data_exception(
                                    data_response_fault,
                                    pending_memory_uop_q,
                                    pending_memory_address_q,
                                    pending_request_is_write,
                                    debug_sr[MX_SR_S]);
                                pending_exception_sr_q <= debug_sr;
                                pending_memory_action_q <=
                                    MEMORY_ACTION_EXCEPTION_PUSH_PC;
                                pending_memory_address_q <= debug_ssp - 32'd4;
                                pending_memory_write_value_q <=
                                    pending_memory_uop_q.sequential_pc;
                                pending_instruction_trace_q <= 1'b0;
                                trace_after_exception_q <= 1'b0;
                            end
                            state_q <= pending_action_is_exception_frame ?
                                CORE_FAULTED : CORE_DATA_SEND;
                        end else if (data_request_splits_long) begin
                            split_access_second_q <= 1'b1;
                            split_base_address_q <=
                                pending_memory_address_q;
                            if (!pending_request_is_write)
                                split_read_high_q <=
                                    data_response_beat_value[15:0];
                            pending_memory_address_q <=
                                pending_memory_address_q + 32'd2;
                            state_q <= CORE_DATA_SEND;
                        end else if ((pending_memory_action_q ==
                                     MEMORY_ACTION_ALU_LOAD) &&
                                    (pending_memory_uop_q.opcode ==
                                     MX_UOP_DIVIDE)) begin
                            // The memory operand has completed successfully
                            // and was sampled by the divider on this edge.
                            // Address-update state remains pending until the
                            // arithmetic operation commits, matching the
                            // pre-existing precise-state policy.
                            state_q <= CORE_DIVIDE_WAIT;
                        end else if ((pending_memory_action_q ==
                                     MEMORY_ACTION_SEQUENCE_READ) &&
                                    (sequence_step_q ==
                                     MX_SEQUENCE_READ_SOURCE)) begin
                            pending_source_operand_q <= data_response_value;
                            sequence_step_q <=
                                MX_SEQUENCE_READ_DESTINATION;
                            pending_memory_address_q <=
                                pending_second_address_q;
                            state_q <= CORE_DATA_SEND;
                        end else if ((pending_memory_action_q ==
                                     MEMORY_ACTION_ALU_LOAD) &&
                                    data_chk_trap) begin
                            pending_exception_q <=
                                make_instruction_trap_exception(
                                MX_VECTOR_CHK, pending_memory_uop_q);
                            trace_after_exception_q <=
                                pending_instruction_trace_q;
                            pending_exception_sr_q <= data_chk_sr;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                pending_memory_uop_q.sequential_pc;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXCEPTION_PUSH_PC) begin
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_SR;
                            pending_memory_address_q <= debug_ssp - 32'd6;
                            pending_memory_write_value_q <=
                                {16'd0, pending_exception_sr_q};
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXCEPTION_PUSH_SR) begin
                            if (pending_exception_special) begin
                                pending_memory_action_q <=
                                    MEMORY_ACTION_EXCEPTION_PUSH_IR;
                                pending_memory_address_q <= debug_ssp - 32'd8;
                                pending_memory_write_value_q <=
                                    {16'd0, pending_exception_q.opcode};
                            end else begin
                                pending_memory_action_q <=
                                    MEMORY_ACTION_EXCEPTION_VECTOR_READ;
                                pending_memory_address_q <=
                                    {22'd0, pending_exception_q.vector, 2'b00};
                                pending_memory_write_value_q <= '0;
                            end
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXCEPTION_PUSH_IR) begin
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS;
                            pending_memory_address_q <= debug_ssp - 32'd12;
                            pending_memory_write_value_q <=
                                pending_exception_q.logical_address;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXCEPTION_PUSH_FAULT_ADDRESS) begin
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_SSW;
                            pending_memory_address_q <= debug_ssp - 32'd14;
                            pending_memory_write_value_q <=
                                {16'd0, pending_exception_q.special_status};
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXCEPTION_PUSH_SSW) begin
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_VECTOR_READ;
                            pending_memory_address_q <=
                                {22'd0, pending_exception_q.vector, 2'b00};
                            pending_memory_write_value_q <= '0;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXCEPTION_VECTOR_READ) begin
                            redirect_target_q <= data_response_value;
                            redirect_pending_q <= 1'b1;
                            if (trace_after_exception_q) begin
                                trace_pending_q <= 1'b1;
                                trace_pending_pc_q <= data_response_value;
                                trace_pending_sr_q <= exception_entry_sr;
                                trace_after_exception_q <= 1'b0;
                            end
                            pending_exception_q <= '0;
                            pending_memory_uop_q <= '0;
                            pending_memory_action_q <= MEMORY_ACTION_NONE;
                            sequence_program_q <= MX_SEQUENCE_NONE;
                            sequence_step_q <= MX_SEQUENCE_IDLE;
                            pending_address_update_q <= 1'b0;
                            pending_address_update_b_q <= 1'b0;
                            pending_movem_mask_q <= '0;
                            pending_instruction_trace_q <= 1'b0;
                            state_q <= CORE_RUN;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_RTE_LOAD_SR) begin
                            pending_source_operand_q <= data_response_value;
                            pending_memory_action_q <=
                                MEMORY_ACTION_RTE_LOAD_PC;
                            pending_memory_address_q <= debug_ssp + 32'd2;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_RTE_LOAD_PC) begin
                            retire_valid <= 1'b1;
                            retire_pc <= pending_memory_uop_q.instruction_pc;
                            retire_instruction_id <=
                                pending_memory_uop_q.instruction_id;
                            redirect_target_q <= data_response_value;
                            redirect_pending_q <= 1'b1;
                            if (pending_instruction_trace_q) begin
                                trace_pending_q <= 1'b1;
                                trace_pending_pc_q <= data_response_value;
                                trace_pending_sr_q <=
                                    pending_source_operand_q[15:0];
                            end
                            pending_instruction_trace_q <= 1'b0;
                            pending_memory_uop_q <= '0;
                            pending_memory_action_q <= MEMORY_ACTION_NONE;
                            state_q <= CORE_RUN;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_RTR_LOAD_CCR) begin
                            pending_source_operand_q <= data_response_value;
                            pending_memory_action_q <=
                                MEMORY_ACTION_RTR_LOAD_PC;
                            pending_memory_address_q <=
                                pending_memory_address_q + 32'd2;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_RTR_LOAD_PC) begin
                            retire_valid <= 1'b1;
                            retire_pc <= pending_memory_uop_q.instruction_pc;
                            retire_instruction_id <=
                                pending_memory_uop_q.instruction_id;
                            redirect_target_q <= data_response_value;
                            redirect_pending_q <= 1'b1;
                            if (pending_instruction_trace_q) begin
                                trace_pending_q <= 1'b1;
                                trace_pending_pc_q <= data_response_value;
                                trace_pending_sr_q <=
                                    {debug_sr[15:8],
                                     pending_source_operand_q[7:0]};
                            end
                            pending_instruction_trace_q <= 1'b0;
                            pending_memory_uop_q <= '0;
                            pending_memory_action_q <= MEMORY_ACTION_NONE;
                            state_q <= CORE_RUN;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXTEND_SOURCE_LOAD) begin
                            pending_source_operand_q <= data_response_value;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXTEND_DESTINATION_LOAD;
                            pending_memory_address_q <=
                                pending_second_address_q;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_EXTEND_DESTINATION_LOAD) begin
                            pending_destination_original_q <=
                                data_response_value;
                            pending_memory_action_q <=
                                MEMORY_ACTION_RMW_STORE;
                            pending_memory_address_q <=
                                completed_memory_address;
                            pending_memory_write_value_q <= rmw_result_value;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_MOVE_LOAD_TO_STORE) begin
                            // Memory-to-memory MOVE is a precise two-phase
                            // operation: no architectural state is committed
                            // until the destination write succeeds.
                            pending_memory_action_q <=
                                MEMORY_ACTION_MOVE_STORE;
                            pending_memory_address_q <=
                                pending_second_address_q;
                            pending_memory_write_value_q <=
                                data_response_value;
                            state_q <= CORE_DATA_SEND;
                        end else if (pending_memory_action_q ==
                                     MEMORY_ACTION_RMW_LOAD) begin
                            pending_memory_action_q <= MEMORY_ACTION_RMW_STORE;
                            pending_memory_address_q <=
                                completed_memory_address;
                            pending_destination_original_q <=
                                data_response_value;
                            pending_memory_write_value_q <= rmw_result_value;
                            state_q <= CORE_DATA_SEND;
                        end else if ((pending_memory_action_q inside {
                                      MEMORY_ACTION_MOVEM_STORE,
                                      MEMORY_ACTION_MOVEM_LOAD}) &&
                                     !movem_final_transfer) begin
                            pending_movem_mask_q <= movem_remaining_mask;
                            pending_movem_bit_q <= movem_next_bit;
                            if ((pending_memory_action_q ==
                                 MEMORY_ACTION_MOVEM_STORE) &&
                                (pending_memory_uop_q.source_ea.kind ==
                                 MX_EA_PREDECREMENT))
                                pending_memory_address_q <=
                                    completed_memory_address -
                                    ((pending_memory_uop_q.size == MX_OP_WORD) ?
                                     32'd2 : 32'd4);
                            else
                                pending_memory_address_q <=
                                    completed_memory_address +
                                    ((pending_memory_uop_q.size == MX_OP_WORD) ?
                                     32'd2 : 32'd4);
                            if (pending_memory_action_q ==
                                MEMORY_ACTION_MOVEM_STORE)
                                pending_memory_write_value_q <=
                                    movem_register_value(
                                        movem_next_bit,
                                        pending_memory_uop_q.source_ea.kind ==
                                            MX_EA_PREDECREMENT,
                                        debug_data_registers,
                                        debug_address_registers);
                            state_q <= CORE_DATA_SEND;
                        end else begin
                            retire_valid <= 1'b1;
                            retire_pc <= pending_memory_uop_q.instruction_pc;
                            retire_instruction_id <=
                                pending_memory_uop_q.instruction_id;
                            if (pending_instruction_trace_q) begin
                                trace_pending_q <= 1'b1;
                                trace_pending_pc_q <= rf_pc_write_value;
                                trace_pending_sr_q <= pending_writes_flags ?
                                    data_sr_value : debug_sr;
                            end
                            if (pending_memory_action_q ==
                                MEMORY_ACTION_JSR_PUSH) begin
                                redirect_target_q <= pending_control_target_q;
                                redirect_pending_q <= 1'b1;
                            end else if (pending_memory_action_q ==
                                         MEMORY_ACTION_RTS_POP) begin
                                redirect_target_q <= data_response_value;
                                redirect_pending_q <= 1'b1;
                            end
                            pending_memory_uop_q <= '0;
                            pending_memory_action_q <= MEMORY_ACTION_NONE;
                            sequence_program_q <= MX_SEQUENCE_NONE;
                            sequence_step_q <= MX_SEQUENCE_IDLE;
                            pending_address_update_q <= 1'b0;
                            pending_address_update_b_q <= 1'b0;
                            pending_movem_mask_q <= '0;
                            pending_instruction_trace_q <= 1'b0;
                            state_q <= CORE_RUN;
                        end
                    end
                end

                CORE_DIVIDE_WAIT: begin
                    if (divider_done) begin
                        if (divider_divide_by_zero) begin
                            pending_exception_q <=
                                make_instruction_trap_exception(
                                    MX_VECTOR_ZERO_DIVIDE,
                                    pending_memory_uop_q);
                            trace_after_exception_q <=
                                pending_instruction_trace_q;
                            // M68000PRM 4-92/4-96: divide by zero leaves X
                            // unaffected, makes N/Z/V undefined, and always
                            // clears C.  Preserve the undefined bits
                            // deterministically, but stack the architecturally
                            // required cleared carry in the vector-5 frame.
                            pending_exception_sr_q <= debug_sr & 16'hfffe;
                            pending_memory_action_q <=
                                MEMORY_ACTION_EXCEPTION_PUSH_PC;
                            pending_memory_address_q <= debug_ssp - 32'd4;
                            pending_memory_write_value_q <=
                                pending_memory_uop_q.sequential_pc;
                            pending_instruction_trace_q <= 1'b0;
                            state_q <= CORE_DATA_SEND;
                        end else begin
                            retire_valid <= 1'b1;
                            retire_pc <= pending_memory_uop_q.instruction_pc;
                            retire_instruction_id <=
                                pending_memory_uop_q.instruction_id;
                            if (pending_instruction_trace_q) begin
                                trace_pending_q <= 1'b1;
                                trace_pending_pc_q <=
                                    pending_memory_uop_q.sequential_pc;
                                trace_pending_sr_q <= data_sr_value;
                            end
                            pending_memory_uop_q <= '0;
                            pending_memory_action_q <= MEMORY_ACTION_NONE;
                            pending_address_update_q <= 1'b0;
                            pending_address_update_b_q <= 1'b0;
                            pending_instruction_trace_q <= 1'b0;
                            state_q <= CORE_RUN;
                        end
                    end
                end

                CORE_STOPPED: begin
                    if (interrupt_take) begin
                        pending_exception_q <= make_interrupt_exception(
                            accepted_interrupt_vector, debug_pc);
                        pending_exception_sr_q <= debug_sr;
                        pending_interrupt_level_q <= active_interrupt_level;
                        pending_memory_action_q <=
                            MEMORY_ACTION_EXCEPTION_PUSH_PC;
                        pending_memory_address_q <= debug_ssp - 32'd4;
                        pending_memory_write_value_q <= debug_pc;
                        interrupt_ack_q <= 1'b1;
                        interrupt_ack_level_q <= active_interrupt_level;
                        state_q <= CORE_DATA_SEND;
                    end
                end

                CORE_RESET_DEVICES: begin
                    if (reset_devices_cycles_q == 7'd123) begin
                        retire_valid <= 1'b1;
                        retire_pc <= pending_memory_uop_q.instruction_pc;
                        retire_instruction_id <=
                            pending_memory_uop_q.instruction_id;
                        if (debug_sr[MX_SR_T1]) begin
                            trace_pending_q <= 1'b1;
                            trace_pending_pc_q <=
                                pending_memory_uop_q.sequential_pc;
                            trace_pending_sr_q <= debug_sr;
                        end
                        pending_memory_uop_q <= '0;
                        reset_devices_cycles_q <= '0;
                        state_q <= CORE_RUN;
                    end else begin
                        reset_devices_cycles_q <= reset_devices_cycles_q + 1'b1;
                    end
                end
                CORE_FAULTED: begin end
                default: state_q <= CORE_FAULTED;
            endcase
        end
    end
endmodule
