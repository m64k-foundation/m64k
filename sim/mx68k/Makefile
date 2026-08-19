VERILATOR ?= verilator
PYTHON ?= python3
ROOT := ../..
BRIDGE_BUILD_DIR := $(ROOT)/build/mx68k_mem_bridge
BRIDGE_TOP := mx68k_mem_bridge_tb
FX68K_BUILD_DIR := $(ROOT)/build/mx68k_fx68k_smoke
FX68K_TOP := mx68k_fx68k_smoke_tb
ARCH_BUILD_DIR := $(ROOT)/build/mx68k_arch_pkg
ARCH_TOP := mx68k_arch_pkg_tb
SHIFTER_BUILD_DIR := $(ROOT)/build/mx68k_shifter
SHIFTER_TOP := mx68k_shifter_tb
DIVIDER_BUILD_DIR := $(ROOT)/build/mx68k_divider
DIVIDER_TOP := mx68k_divider_tb
RAM_BUILD_DIR := $(ROOT)/build/mx68k_ram_protocol
RAM_TOP := mx68k_ram_protocol_tb
ROUTER_BUILD_DIR := $(ROOT)/build/mx68k_router
ROUTER_TOP := mx68k_router_tb
FETCH_BUILD_DIR := $(ROOT)/build/mx68k_fetch_frontend
FETCH_TOP := mx68k_fetch_frontend_tb
INSTR_BUILD_DIR := $(ROOT)/build/mx68k_instruction_buffer
INSTR_TOP := mx68k_instruction_buffer_tb
DECODE_BUILD_DIR := $(ROOT)/build/mx68k_predecoder
DECODE_TOP := mx68k_predecoder_tb
DECODE_FRONTEND_BUILD_DIR := $(ROOT)/build/mx68k_decode_frontend
DECODE_FRONTEND_TOP := mx68k_decode_frontend_tb
REGFILE_BUILD_DIR := $(ROOT)/build/mx68k_register_file
REGFILE_TOP := mx68k_register_file_tb
CORE_M00_BUILD_DIR := $(ROOT)/build/mx68k_core_m00
CORE_M00_TOP := mx68k_core_m00_tb
CORE_UART_BUILD_DIR := $(ROOT)/build/mx68k_core_uart
CORE_UART_TOP := mx68k_core_uart_tb
CORE_IRQ_BUILD_DIR := $(ROOT)/build/mx68k_core_irq
CORE_IRQ_TOP := mx68k_core_irq_tb
CORE_CHK_BUILD_DIR := $(ROOT)/build/mx68k_core_chk
CORE_CHK_TOP := mx68k_core_chk_tb
CORE_TRACE_BUILD_DIR := $(ROOT)/build/mx68k_core_trace
CORE_TRACE_TOP := mx68k_core_trace_tb
CORE_BUS_ERROR_BUILD_DIR := $(ROOT)/build/mx68k_core_bus_error
CORE_BUS_ERROR_TOP := mx68k_core_bus_error_tb
CORE_LINE_CROSS_BUILD_DIR := $(ROOT)/build/mx68k_core_line_cross
CORE_LINE_CROSS_TOP := mx68k_core_line_cross_tb
CORE_NEGX_BUILD_DIR := $(ROOT)/build/mx68k_core_negx
CORE_NEGX_TOP := mx68k_core_negx_tb
CORE_ADDX_SUBX_BUILD_DIR := $(ROOT)/build/mx68k_core_addx_subx
CORE_ADDX_SUBX_TOP := mx68k_core_addx_subx_tb
CORE_BCD_BUILD_DIR := $(ROOT)/build/mx68k_core_bcd
CORE_BCD_TOP := mx68k_core_bcd_tb
CORE_EXTEND_MEMORY_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_extend_memory_fault
CORE_EXTEND_MEMORY_FAULT_TOP := mx68k_core_extend_memory_fault_tb
CORE_EXG_BUILD_DIR := $(ROOT)/build/mx68k_core_exg
CORE_EXG_TOP := mx68k_core_exg_tb
CORE_TAS_BUILD_DIR := $(ROOT)/build/mx68k_core_tas
CORE_TAS_TOP := mx68k_core_tas_tb
CORE_ADDA_MEM_BUILD_DIR := $(ROOT)/build/mx68k_core_adda_mem
CORE_ADDA_MEM_TOP := mx68k_core_adda_mem_tb
CORE_SR_BUILD_DIR := $(ROOT)/build/mx68k_core_sr
CORE_SR_TOP := mx68k_core_sr_tb
CORE_BIT_BUILD_DIR := $(ROOT)/build/mx68k_core_bit
CORE_BIT_TOP := mx68k_core_bit_tb
CORE_SCC_BUILD_DIR := $(ROOT)/build/mx68k_core_scc
CORE_SCC_TOP := mx68k_core_scc_tb
CORE_SCC_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_scc_matrix
CORE_SCC_MATRIX_TOP := mx68k_core_scc_matrix_tb
CORE_SCC_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_scc_fault
CORE_SCC_FAULT_TOP := mx68k_core_scc_fault_tb
CORE_CLR_BUILD_DIR := $(ROOT)/build/mx68k_core_clr
CORE_CLR_TOP := mx68k_core_clr_tb
CORE_TST_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_tst_matrix
CORE_TST_MATRIX_TOP := mx68k_core_tst_matrix_tb
CORE_TST_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_tst_fault
CORE_TST_FAULT_TOP := mx68k_core_tst_fault_tb
CORE_UNARY_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_unary_matrix
CORE_UNARY_MATRIX_TOP := mx68k_core_unary_matrix_tb
CORE_UNARY_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_unary_fault
CORE_UNARY_FAULT_TOP := mx68k_core_unary_fault_tb
CORE_QUICK_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_quick_matrix
CORE_QUICK_MATRIX_TOP := mx68k_core_quick_matrix_tb
CORE_QUICK_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_quick_fault
CORE_QUICK_FAULT_TOP := mx68k_core_quick_fault_tb
CORE_USP_BUILD_DIR := $(ROOT)/build/mx68k_core_usp
CORE_USP_TOP := mx68k_core_usp_tb
CORE_PEA_BUILD_DIR := $(ROOT)/build/mx68k_core_pea
CORE_PEA_TOP := mx68k_core_pea_tb
CORE_CMPA_BUILD_DIR := $(ROOT)/build/mx68k_core_cmpa
CORE_CMPA_TOP := mx68k_core_cmpa_tb
CORE_BSR_BUILD_DIR := $(ROOT)/build/mx68k_core_bsr
CORE_BSR_TOP := mx68k_core_bsr_tb
CORE_RTR_BUILD_DIR := $(ROOT)/build/mx68k_core_rtr
CORE_RTR_TOP := mx68k_core_rtr_tb
CORE_DBCC_BUILD_DIR := $(ROOT)/build/mx68k_core_dbcc
CORE_DBCC_TOP := mx68k_core_dbcc_tb
CORE_TRAP_BUILD_DIR := $(ROOT)/build/mx68k_core_trap
CORE_TRAP_TOP := mx68k_core_trap_tb
CORE_RESET_INSTRUCTION_BUILD_DIR := $(ROOT)/build/mx68k_core_reset_instruction
CORE_RESET_INSTRUCTION_TOP := mx68k_core_reset_instruction_tb
CORE_LOGICAL_SR_BUILD_DIR := $(ROOT)/build/mx68k_core_logical_sr
CORE_LOGICAL_SR_TOP := mx68k_core_logical_sr_tb
CORE_SYSTEM_CONTROL_BUILD_DIR := $(ROOT)/build/mx68k_core_system_control
CORE_SYSTEM_CONTROL_TOP := mx68k_core_system_control_tb
CORE_UNARY_QUICK_BUILD_DIR := $(ROOT)/build/mx68k_core_unary_quick
CORE_UNARY_QUICK_TOP := mx68k_core_unary_quick_tb
CORE_IMMEDIATE_BUILD_DIR := $(ROOT)/build/mx68k_core_immediate
CORE_IMMEDIATE_TOP := mx68k_core_immediate_tb
CORE_IMMEDIATE_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_immediate_matrix
CORE_IMMEDIATE_MATRIX_TOP := mx68k_core_immediate_matrix_tb
CORE_IMMEDIATE_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_immediate_fault
CORE_IMMEDIATE_FAULT_TOP := mx68k_core_immediate_fault_tb
CORE_MULDIV_BUILD_DIR := $(ROOT)/build/mx68k_core_muldiv
CORE_MULDIV_TOP := mx68k_core_muldiv_tb
CORE_MULDIV_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_muldiv_matrix
CORE_MULDIV_MATRIX_TOP := mx68k_core_muldiv_matrix_tb
CORE_MULDIV_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_muldiv_fault
CORE_MULDIV_FAULT_TOP := mx68k_core_muldiv_fault_tb
CORE_DIVIDE_EXCEPTION_BUILD_DIR := $(ROOT)/build/mx68k_core_divide_exception
CORE_DIVIDE_EXCEPTION_TOP := mx68k_core_divide_exception_tb
CORE_SHIFT_BUILD_DIR := $(ROOT)/build/mx68k_core_shift
CORE_SHIFT_TOP := mx68k_core_shift_tb
CORE_MEMORY_SHIFT_BUILD_DIR := $(ROOT)/build/mx68k_core_memory_shift
CORE_MEMORY_SHIFT_TOP := mx68k_core_memory_shift_tb
CORE_MEMORY_SHIFT_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_memory_shift_fault
CORE_MEMORY_SHIFT_FAULT_TOP := mx68k_core_memory_shift_fault_tb
CORE_CMPM_BUILD_DIR := $(ROOT)/build/mx68k_core_cmpm
CORE_CMPM_TOP := mx68k_core_cmpm_tb
CORE_CMPM_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_cmpm_fault
CORE_CMPM_FAULT_TOP := mx68k_core_cmpm_fault_tb
CORE_CONTROL_ADDRESS_BUILD_DIR := $(ROOT)/build/mx68k_core_control_address
CORE_CONTROL_ADDRESS_TOP := mx68k_core_control_address_tb
CORE_BINARY_BUILD_DIR := $(ROOT)/build/mx68k_core_binary
CORE_BINARY_TOP := mx68k_core_binary_tb
CORE_BINARY_SOURCE_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_binary_source_matrix
CORE_BINARY_SOURCE_MATRIX_TOP := mx68k_core_binary_source_matrix_tb
CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_binary_destination_matrix
CORE_BINARY_DESTINATION_MATRIX_TOP := mx68k_core_binary_destination_matrix_tb
CORE_BINARY_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_binary_fault
CORE_BINARY_FAULT_TOP := mx68k_core_binary_fault_tb
CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR := $(ROOT)/build/mx68k_core_address_arithmetic_matrix
CORE_ADDRESS_ARITHMETIC_MATRIX_TOP := mx68k_core_address_arithmetic_matrix_tb
CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR := $(ROOT)/build/mx68k_core_address_arithmetic_fault
CORE_ADDRESS_ARITHMETIC_FAULT_TOP := mx68k_core_address_arithmetic_fault_tb
CORE_MOVE_MOVEM_BUILD_DIR := $(ROOT)/build/mx68k_core_move_movem
CORE_MOVE_MOVEM_TOP := mx68k_core_move_movem_tb
HIGH_IRQ_BUILD_DIR := $(ROOT)/build/mx68k_high_model_irq
HIGH_IRQ_TOP := mx68k_high_model_irq_tb
SD_MODEL_BUILD_DIR := $(ROOT)/build/mx68k_sd_spi_model
SD_MODEL_TOP := mx68k_sd_spi_model_tb
LINUX_WORKLOAD_MEMORY_BUILD_DIR := $(ROOT)/build/mx68k_linux_workload_memory
LINUX_WORKLOAD_MEMORY_TOP := mx68k_linux_workload_memory_tb
FIRMWARE_PROBE_BUILD_DIR := $(ROOT)/build/mx68k_firmware_probe
FIRMWARE_PROBE_TOP := mx68k_firmware_probe_tb
FIRMWARE_SIM_BUILD_DIR := $(ROOT)/build/mx68k_firmware_sim
FIRMWARE_SIM_TOP := mx68k_firmware_sim_top
DECODE_DB := $(ROOT)/isa/mx68k_m00.json
DECODE_GENERATOR := $(ROOT)/scripts/gen_mx68k_decode.py
DECODE_GENERATED := $(ROOT)/rtl/mx68k/core/decode/generated/mx68k_m00_decode_table_pkg.sv
AUDIT_DB := $(ROOT)/isa/mx68k_m00_audit.json
AUDIT_CHECKER := $(ROOT)/scripts/check_mx68k_audit.py
FX68K := $(ROOT)/third_party/fx68k

COMMON_SOURCES := \
	$(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/compat/fx68k_mem_bridge.sv
BRIDGE_SOURCES := $(COMMON_SOURCES) mx68k_mem_bridge_tb.sv
FX68K_SOURCES := $(COMMON_SOURCES) \
	$(FX68K)/fx68k.sv $(FX68K)/fx68kAlu.sv $(FX68K)/uaddrPla.sv \
	mx68k_fx68k_smoke_tb.sv
ARCH_SOURCES := $(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv mx68k_arch_pkg_tb.sv
SHIFTER_SOURCES := $(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	mx68k_shift_reference_pkg.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_shifter.sv mx68k_shifter_tb.sv
DIVIDER_SOURCES := $(ROOT)/rtl/mx68k/core/execute/mx68k_divider.sv \
	mx68k_divider_tb.sv
RAM_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv mx68k_ram_protocol_tb.sv
ROUTER_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/fabric/mx68k_router_3.sv mx68k_router_tb.sv
FETCH_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_fetch_frontend.sv \
	mx68k_fetch_frontend_tb.sv
INSTR_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_ea_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_uop_pkg.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_instruction_buffer.sv \
	mx68k_instruction_buffer_tb.sv
DECODE_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_ea_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_uop_pkg.sv \
	$(DECODE_GENERATED) \
	$(ROOT)/rtl/mx68k/core/decode/mx68k_predecoder.sv \
	mx68k_predecoder_tb.sv
DECODE_FRONTEND_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_ea_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_uop_pkg.sv \
	$(DECODE_GENERATED) \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_fetch_frontend.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_instruction_buffer.sv \
	$(ROOT)/rtl/mx68k/core/decode/mx68k_predecoder.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_decode_frontend.sv \
	mx68k_decode_frontend_tb.sv
REGFILE_SOURCES := $(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/backend/mx68k_register_file.sv \
	mx68k_register_file_tb.sv
CORE_M00_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/mx68k_irq_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_ea_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_uop_pkg.sv \
	$(DECODE_GENERATED) \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_fetch_frontend.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_instruction_buffer.sv \
	$(ROOT)/rtl/mx68k/core/decode/mx68k_predecoder.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_decode_frontend.sv \
	$(ROOT)/rtl/mx68k/core/backend/mx68k_register_file.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_sequence_pkg.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_shifter.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_divider.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_core_m00.sv \
	mx68k_core_m00_tb.sv
CORE_UART_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/mx68k_irq_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_uart_16550_model.sv \
	$(ROOT)/rtl/mx68k/fabric/mx68k_router_3.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_ea_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_uop_pkg.sv \
	$(DECODE_GENERATED) \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_fetch_frontend.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_instruction_buffer.sv \
	$(ROOT)/rtl/mx68k/core/decode/mx68k_predecoder.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_decode_frontend.sv \
	$(ROOT)/rtl/mx68k/core/backend/mx68k_register_file.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_sequence_pkg.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_shifter.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_divider.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_core_m00.sv \
	mx68k_core_uart_tb.sv
CORE_IRQ_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_irq_tb.sv
CORE_CHK_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_chk_tb.sv
CORE_TRACE_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_trace_tb.sv
CORE_BUS_ERROR_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_bus_error_tb.sv
CORE_LINE_CROSS_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_line_cross_tb.sv
CORE_NEGX_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_negx_tb.sv
CORE_ADDX_SUBX_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_addx_subx_tb.sv
CORE_BCD_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_bcd_tb.sv
CORE_EXTEND_MEMORY_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_extend_memory_fault_tb.sv
CORE_EXG_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_exg_tb.sv
CORE_TAS_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_tas_tb.sv
CORE_ADDA_MEM_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_adda_mem_tb.sv
CORE_SR_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_sr_tb.sv
CORE_BIT_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_bit_tb.sv
CORE_SCC_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_scc_tb.sv
CORE_SCC_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_scc_matrix_tb.sv
CORE_SCC_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_scc_fault_tb.sv
CORE_CLR_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_clr_tb.sv
CORE_TST_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_tst_matrix_tb.sv
CORE_TST_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_tst_fault_tb.sv
CORE_UNARY_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_unary_matrix_tb.sv
CORE_UNARY_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_unary_fault_tb.sv
CORE_QUICK_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_quick_matrix_tb.sv
CORE_QUICK_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_quick_fault_tb.sv
CORE_USP_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_usp_tb.sv
CORE_PEA_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_pea_tb.sv
CORE_CMPA_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_cmpa_tb.sv
CORE_BSR_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_bsr_tb.sv
CORE_RTR_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_rtr_tb.sv
CORE_DBCC_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_dbcc_tb.sv
CORE_TRAP_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_trap_tb.sv
CORE_RESET_INSTRUCTION_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_reset_instruction_tb.sv
CORE_LOGICAL_SR_SOURCES := $(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_logical_sr_tb.sv
CORE_SYSTEM_CONTROL_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_system_control_tb.sv
CORE_UNARY_QUICK_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_unary_quick_tb.sv
CORE_IMMEDIATE_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_immediate_tb.sv
CORE_IMMEDIATE_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_immediate_matrix_tb.sv
CORE_IMMEDIATE_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_immediate_fault_tb.sv
CORE_MULDIV_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_muldiv_tb.sv
CORE_MULDIV_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_muldiv_matrix_tb.sv
CORE_MULDIV_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_muldiv_fault_tb.sv
CORE_DIVIDE_EXCEPTION_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_divide_exception_tb.sv
CORE_SHIFT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_shift_reference_pkg.sv \
	mx68k_core_shift_tb.sv
CORE_MEMORY_SHIFT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_memory_shift_tb.sv
CORE_MEMORY_SHIFT_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_memory_shift_fault_tb.sv
CORE_CMPM_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_cmpm_tb.sv
CORE_CMPM_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_cmpm_fault_tb.sv
CORE_CONTROL_ADDRESS_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_control_address_tb.sv
CORE_BINARY_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_binary_tb.sv
CORE_BINARY_SOURCE_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_binary_source_matrix_tb.sv
CORE_BINARY_DESTINATION_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_binary_destination_matrix_tb.sv
CORE_BINARY_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_binary_fault_tb.sv
CORE_ADDRESS_ARITHMETIC_MATRIX_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_address_arithmetic_matrix_tb.sv
CORE_ADDRESS_ARITHMETIC_FAULT_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_address_arithmetic_fault_tb.sv
CORE_MOVE_MOVEM_SOURCES := \
	$(filter-out mx68k_core_m00_tb.sv,$(CORE_M00_SOURCES)) \
	mx68k_core_move_movem_tb.sv
HIGH_IRQ_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	mx68k_sd_spi_model.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_mackerel_f_high_model.sv \
	mx68k_high_model_irq_tb.sv
SD_MODEL_SOURCES := mx68k_sd_spi_model.sv mx68k_sd_spi_model_tb.sv
LINUX_WORKLOAD_MEMORY_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_linux_workload_memory.sv \
	mx68k_linux_workload_memory_tb.sv
FIRMWARE_PROBE_SOURCES := $(ROOT)/rtl/mx68k/mx68k_pkg.sv \
	$(ROOT)/rtl/mx68k/mx68k_mem_if.sv \
	$(ROOT)/rtl/mx68k/mx68k_irq_if.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_ram.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_dual_port_ram.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_linux_workload_memory.sv \
	mx68k_sd_spi_model.sv \
	$(ROOT)/rtl/mx68k/models/mx68k_mackerel_f_high_model.sv \
	$(ROOT)/rtl/mx68k/fabric/mx68k_router_3.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_arch_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_ea_pkg.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_uop_pkg.sv \
	$(DECODE_GENERATED) \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_fetch_frontend.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_instruction_buffer.sv \
	$(ROOT)/rtl/mx68k/core/decode/mx68k_predecoder.sv \
	$(ROOT)/rtl/mx68k/core/frontend/mx68k_decode_frontend.sv \
	$(ROOT)/rtl/mx68k/core/backend/mx68k_register_file.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_sequence_pkg.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_shifter.sv \
	$(ROOT)/rtl/mx68k/core/execute/mx68k_divider.sv \
	$(ROOT)/rtl/mx68k/core/mx68k_core_m00.sv \
	mx68k_firmware_probe_tb.sv
FIRMWARE_SIM_RTL_SOURCES := $(filter-out mx68k_firmware_probe_tb.sv,$(FIRMWARE_PROBE_SOURCES)) \
	mx68k_firmware_sim_top.sv
FIRMWARE_SIM_SOURCES := $(FIRMWARE_SIM_RTL_SOURCES) mx68k_firmware_sim.cpp

FX68K_WARNING_FLAGS := -Wno-BLKANDNBLK --no-assert-case \
	-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	-Wno-VARHIDDEN -Wno-UNUSEDSIGNAL

.PHONY: all test lint decode-check audit-check generate-decode firmware-probe \
	firmware-sim firmware-run firmware-smoke firmware-linux-smoke clean

all: test

$(BRIDGE_BUILD_DIR)/V$(BRIDGE_TOP): $(BRIDGE_SOURCES)
	mkdir -p $(BRIDGE_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(BRIDGE_TOP) \
		-Mdir $(BRIDGE_BUILD_DIR) $(BRIDGE_SOURCES)

$(FX68K_BUILD_DIR)/V$(FX68K_TOP): $(FX68K_SOURCES)
	mkdir -p $(FX68K_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal $(FX68K_WARNING_FLAGS) -I$(FX68K) \
		--top-module $(FX68K_TOP) -Mdir $(FX68K_BUILD_DIR) $(FX68K_SOURCES)

$(ARCH_BUILD_DIR)/V$(ARCH_TOP): $(ARCH_SOURCES)
	mkdir -p $(ARCH_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(ARCH_TOP) \
		-Mdir $(ARCH_BUILD_DIR) $(ARCH_SOURCES)

$(SHIFTER_BUILD_DIR)/V$(SHIFTER_TOP): $(SHIFTER_SOURCES)
	mkdir -p $(SHIFTER_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(SHIFTER_TOP) \
		-Mdir $(SHIFTER_BUILD_DIR) $(SHIFTER_SOURCES)

$(DIVIDER_BUILD_DIR)/V$(DIVIDER_TOP): $(DIVIDER_SOURCES)
	mkdir -p $(DIVIDER_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(DIVIDER_TOP) \
		-Mdir $(DIVIDER_BUILD_DIR) $(DIVIDER_SOURCES)

$(RAM_BUILD_DIR)/V$(RAM_TOP): $(RAM_SOURCES)
	mkdir -p $(RAM_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(RAM_TOP) \
		-Mdir $(RAM_BUILD_DIR) $(RAM_SOURCES)

$(ROUTER_BUILD_DIR)/V$(ROUTER_TOP): $(ROUTER_SOURCES)
	mkdir -p $(ROUTER_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(ROUTER_TOP) \
		-Mdir $(ROUTER_BUILD_DIR) $(ROUTER_SOURCES)

$(FETCH_BUILD_DIR)/V$(FETCH_TOP): $(FETCH_SOURCES)
	mkdir -p $(FETCH_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(FETCH_TOP) \
		-Mdir $(FETCH_BUILD_DIR) $(FETCH_SOURCES)

$(INSTR_BUILD_DIR)/V$(INSTR_TOP): $(INSTR_SOURCES)
	mkdir -p $(INSTR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(INSTR_TOP) \
		-Mdir $(INSTR_BUILD_DIR) $(INSTR_SOURCES)

$(DECODE_BUILD_DIR)/V$(DECODE_TOP): $(DECODE_SOURCES)
	mkdir -p $(DECODE_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(DECODE_TOP) \
		-Mdir $(DECODE_BUILD_DIR) $(DECODE_SOURCES)

$(DECODE_FRONTEND_BUILD_DIR)/V$(DECODE_FRONTEND_TOP): $(DECODE_FRONTEND_SOURCES)
	mkdir -p $(DECODE_FRONTEND_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(DECODE_FRONTEND_TOP) \
		-Mdir $(DECODE_FRONTEND_BUILD_DIR) $(DECODE_FRONTEND_SOURCES)

$(REGFILE_BUILD_DIR)/V$(REGFILE_TOP): $(REGFILE_SOURCES)
	mkdir -p $(REGFILE_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(REGFILE_TOP) \
		-Mdir $(REGFILE_BUILD_DIR) $(REGFILE_SOURCES)

$(CORE_M00_BUILD_DIR)/V$(CORE_M00_TOP): $(CORE_M00_SOURCES)
	mkdir -p $(CORE_M00_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_M00_TOP) \
		-Mdir $(CORE_M00_BUILD_DIR) $(CORE_M00_SOURCES)

$(CORE_UART_BUILD_DIR)/V$(CORE_UART_TOP): $(CORE_UART_SOURCES)
	mkdir -p $(CORE_UART_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_UART_TOP) \
		-Mdir $(CORE_UART_BUILD_DIR) $(CORE_UART_SOURCES)

$(CORE_IRQ_BUILD_DIR)/V$(CORE_IRQ_TOP): $(CORE_IRQ_SOURCES)
	mkdir -p $(CORE_IRQ_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_IRQ_TOP) \
		-Mdir $(CORE_IRQ_BUILD_DIR) $(CORE_IRQ_SOURCES)

$(CORE_CHK_BUILD_DIR)/V$(CORE_CHK_TOP): $(CORE_CHK_SOURCES)
	mkdir -p $(CORE_CHK_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CHK_TOP) \
		-Mdir $(CORE_CHK_BUILD_DIR) $(CORE_CHK_SOURCES)

$(CORE_TRACE_BUILD_DIR)/V$(CORE_TRACE_TOP): $(CORE_TRACE_SOURCES)
	mkdir -p $(CORE_TRACE_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_TRACE_TOP) \
		-Mdir $(CORE_TRACE_BUILD_DIR) $(CORE_TRACE_SOURCES)

$(CORE_BUS_ERROR_BUILD_DIR)/V$(CORE_BUS_ERROR_TOP): $(CORE_BUS_ERROR_SOURCES)
	mkdir -p $(CORE_BUS_ERROR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BUS_ERROR_TOP) \
		-Mdir $(CORE_BUS_ERROR_BUILD_DIR) $(CORE_BUS_ERROR_SOURCES)

$(CORE_LINE_CROSS_BUILD_DIR)/V$(CORE_LINE_CROSS_TOP): $(CORE_LINE_CROSS_SOURCES)
	mkdir -p $(CORE_LINE_CROSS_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_LINE_CROSS_TOP) \
		-Mdir $(CORE_LINE_CROSS_BUILD_DIR) $(CORE_LINE_CROSS_SOURCES)

$(CORE_NEGX_BUILD_DIR)/V$(CORE_NEGX_TOP): $(CORE_NEGX_SOURCES)
	mkdir -p $(CORE_NEGX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_NEGX_TOP) \
		-Mdir $(CORE_NEGX_BUILD_DIR) $(CORE_NEGX_SOURCES)

$(CORE_ADDX_SUBX_BUILD_DIR)/V$(CORE_ADDX_SUBX_TOP): $(CORE_ADDX_SUBX_SOURCES)
	mkdir -p $(CORE_ADDX_SUBX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_ADDX_SUBX_TOP) \
		-Mdir $(CORE_ADDX_SUBX_BUILD_DIR) $(CORE_ADDX_SUBX_SOURCES)

$(CORE_BCD_BUILD_DIR)/V$(CORE_BCD_TOP): $(CORE_BCD_SOURCES)
	mkdir -p $(CORE_BCD_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BCD_TOP) \
		-Mdir $(CORE_BCD_BUILD_DIR) $(CORE_BCD_SOURCES)

$(CORE_EXTEND_MEMORY_FAULT_BUILD_DIR)/V$(CORE_EXTEND_MEMORY_FAULT_TOP): \
		$(CORE_EXTEND_MEMORY_FAULT_SOURCES)
	mkdir -p $(CORE_EXTEND_MEMORY_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_EXTEND_MEMORY_FAULT_TOP) \
		-Mdir $(CORE_EXTEND_MEMORY_FAULT_BUILD_DIR) \
		$(CORE_EXTEND_MEMORY_FAULT_SOURCES)

$(CORE_EXG_BUILD_DIR)/V$(CORE_EXG_TOP): $(CORE_EXG_SOURCES)
	mkdir -p $(CORE_EXG_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_EXG_TOP) \
		-Mdir $(CORE_EXG_BUILD_DIR) $(CORE_EXG_SOURCES)

$(CORE_TAS_BUILD_DIR)/V$(CORE_TAS_TOP): $(CORE_TAS_SOURCES)
	mkdir -p $(CORE_TAS_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_TAS_TOP) \
		-Mdir $(CORE_TAS_BUILD_DIR) $(CORE_TAS_SOURCES)

$(CORE_ADDA_MEM_BUILD_DIR)/V$(CORE_ADDA_MEM_TOP): $(CORE_ADDA_MEM_SOURCES)
	mkdir -p $(CORE_ADDA_MEM_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_ADDA_MEM_TOP) \
		-Mdir $(CORE_ADDA_MEM_BUILD_DIR) $(CORE_ADDA_MEM_SOURCES)

$(CORE_SR_BUILD_DIR)/V$(CORE_SR_TOP): $(CORE_SR_SOURCES)
	mkdir -p $(CORE_SR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_SR_TOP) \
		-Mdir $(CORE_SR_BUILD_DIR) $(CORE_SR_SOURCES)

$(CORE_BIT_BUILD_DIR)/V$(CORE_BIT_TOP): $(CORE_BIT_SOURCES)
	mkdir -p $(CORE_BIT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BIT_TOP) \
		-Mdir $(CORE_BIT_BUILD_DIR) $(CORE_BIT_SOURCES)

$(CORE_SCC_BUILD_DIR)/V$(CORE_SCC_TOP): $(CORE_SCC_SOURCES)
	mkdir -p $(CORE_SCC_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_SCC_TOP) \
		-Mdir $(CORE_SCC_BUILD_DIR) $(CORE_SCC_SOURCES)

$(CORE_SCC_MATRIX_BUILD_DIR)/V$(CORE_SCC_MATRIX_TOP): \
		$(CORE_SCC_MATRIX_SOURCES)
	mkdir -p $(CORE_SCC_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_SCC_MATRIX_TOP) \
		-Mdir $(CORE_SCC_MATRIX_BUILD_DIR) $(CORE_SCC_MATRIX_SOURCES)

$(CORE_SCC_FAULT_BUILD_DIR)/V$(CORE_SCC_FAULT_TOP): \
		$(CORE_SCC_FAULT_SOURCES)
	mkdir -p $(CORE_SCC_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_SCC_FAULT_TOP) \
		-Mdir $(CORE_SCC_FAULT_BUILD_DIR) $(CORE_SCC_FAULT_SOURCES)

$(CORE_CLR_BUILD_DIR)/V$(CORE_CLR_TOP): $(CORE_CLR_SOURCES)
	mkdir -p $(CORE_CLR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CLR_TOP) \
		-Mdir $(CORE_CLR_BUILD_DIR) $(CORE_CLR_SOURCES)

$(CORE_TST_MATRIX_BUILD_DIR)/V$(CORE_TST_MATRIX_TOP): \
		$(CORE_TST_MATRIX_SOURCES)
	mkdir -p $(CORE_TST_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_TST_MATRIX_TOP) \
		-Mdir $(CORE_TST_MATRIX_BUILD_DIR) $(CORE_TST_MATRIX_SOURCES)

$(CORE_TST_FAULT_BUILD_DIR)/V$(CORE_TST_FAULT_TOP): \
		$(CORE_TST_FAULT_SOURCES)
	mkdir -p $(CORE_TST_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_TST_FAULT_TOP) \
		-Mdir $(CORE_TST_FAULT_BUILD_DIR) $(CORE_TST_FAULT_SOURCES)

$(CORE_UNARY_MATRIX_BUILD_DIR)/V$(CORE_UNARY_MATRIX_TOP): \
		$(CORE_UNARY_MATRIX_SOURCES)
	mkdir -p $(CORE_UNARY_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_UNARY_MATRIX_TOP) \
		-Mdir $(CORE_UNARY_MATRIX_BUILD_DIR) $(CORE_UNARY_MATRIX_SOURCES)

$(CORE_UNARY_FAULT_BUILD_DIR)/V$(CORE_UNARY_FAULT_TOP): \
		$(CORE_UNARY_FAULT_SOURCES)
	mkdir -p $(CORE_UNARY_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_UNARY_FAULT_TOP) \
		-Mdir $(CORE_UNARY_FAULT_BUILD_DIR) $(CORE_UNARY_FAULT_SOURCES)

$(CORE_QUICK_MATRIX_BUILD_DIR)/V$(CORE_QUICK_MATRIX_TOP): \
		$(CORE_QUICK_MATRIX_SOURCES)
	mkdir -p $(CORE_QUICK_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_QUICK_MATRIX_TOP) \
		-Mdir $(CORE_QUICK_MATRIX_BUILD_DIR) $(CORE_QUICK_MATRIX_SOURCES)

$(CORE_QUICK_FAULT_BUILD_DIR)/V$(CORE_QUICK_FAULT_TOP): \
		$(CORE_QUICK_FAULT_SOURCES)
	mkdir -p $(CORE_QUICK_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_QUICK_FAULT_TOP) \
		-Mdir $(CORE_QUICK_FAULT_BUILD_DIR) $(CORE_QUICK_FAULT_SOURCES)

$(CORE_USP_BUILD_DIR)/V$(CORE_USP_TOP): $(CORE_USP_SOURCES)
	mkdir -p $(CORE_USP_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_USP_TOP) \
		-Mdir $(CORE_USP_BUILD_DIR) $(CORE_USP_SOURCES)

$(CORE_PEA_BUILD_DIR)/V$(CORE_PEA_TOP): $(CORE_PEA_SOURCES)
	mkdir -p $(CORE_PEA_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_PEA_TOP) \
		-Mdir $(CORE_PEA_BUILD_DIR) $(CORE_PEA_SOURCES)

$(CORE_CMPA_BUILD_DIR)/V$(CORE_CMPA_TOP): $(CORE_CMPA_SOURCES)
	mkdir -p $(CORE_CMPA_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CMPA_TOP) \
		-Mdir $(CORE_CMPA_BUILD_DIR) $(CORE_CMPA_SOURCES)

$(CORE_BSR_BUILD_DIR)/V$(CORE_BSR_TOP): $(CORE_BSR_SOURCES)
	mkdir -p $(CORE_BSR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BSR_TOP) \
		-Mdir $(CORE_BSR_BUILD_DIR) $(CORE_BSR_SOURCES)

$(CORE_RTR_BUILD_DIR)/V$(CORE_RTR_TOP): $(CORE_RTR_SOURCES)
	mkdir -p $(CORE_RTR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_RTR_TOP) \
		-Mdir $(CORE_RTR_BUILD_DIR) $(CORE_RTR_SOURCES)

$(CORE_DBCC_BUILD_DIR)/V$(CORE_DBCC_TOP): $(CORE_DBCC_SOURCES)
	mkdir -p $(CORE_DBCC_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_DBCC_TOP) \
		-Mdir $(CORE_DBCC_BUILD_DIR) $(CORE_DBCC_SOURCES)

$(CORE_TRAP_BUILD_DIR)/V$(CORE_TRAP_TOP): $(CORE_TRAP_SOURCES)
	mkdir -p $(CORE_TRAP_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_TRAP_TOP) \
		-Mdir $(CORE_TRAP_BUILD_DIR) $(CORE_TRAP_SOURCES)

$(CORE_RESET_INSTRUCTION_BUILD_DIR)/V$(CORE_RESET_INSTRUCTION_TOP): \
		$(CORE_RESET_INSTRUCTION_SOURCES)
	mkdir -p $(CORE_RESET_INSTRUCTION_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_RESET_INSTRUCTION_TOP) \
		-Mdir $(CORE_RESET_INSTRUCTION_BUILD_DIR) \
		$(CORE_RESET_INSTRUCTION_SOURCES)

$(CORE_LOGICAL_SR_BUILD_DIR)/V$(CORE_LOGICAL_SR_TOP): \
		$(CORE_LOGICAL_SR_SOURCES)
	mkdir -p $(CORE_LOGICAL_SR_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_LOGICAL_SR_TOP) \
		-Mdir $(CORE_LOGICAL_SR_BUILD_DIR) $(CORE_LOGICAL_SR_SOURCES)

$(CORE_SYSTEM_CONTROL_BUILD_DIR)/V$(CORE_SYSTEM_CONTROL_TOP): \
		$(CORE_SYSTEM_CONTROL_SOURCES)
	mkdir -p $(CORE_SYSTEM_CONTROL_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_SYSTEM_CONTROL_TOP) \
		-Mdir $(CORE_SYSTEM_CONTROL_BUILD_DIR) \
		$(CORE_SYSTEM_CONTROL_SOURCES)

$(CORE_UNARY_QUICK_BUILD_DIR)/V$(CORE_UNARY_QUICK_TOP): \
		$(CORE_UNARY_QUICK_SOURCES)
	mkdir -p $(CORE_UNARY_QUICK_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_UNARY_QUICK_TOP) \
		-Mdir $(CORE_UNARY_QUICK_BUILD_DIR) $(CORE_UNARY_QUICK_SOURCES)

$(CORE_IMMEDIATE_BUILD_DIR)/V$(CORE_IMMEDIATE_TOP): \
		$(CORE_IMMEDIATE_SOURCES)
	mkdir -p $(CORE_IMMEDIATE_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_IMMEDIATE_TOP) \
		-Mdir $(CORE_IMMEDIATE_BUILD_DIR) $(CORE_IMMEDIATE_SOURCES)

$(CORE_IMMEDIATE_MATRIX_BUILD_DIR)/V$(CORE_IMMEDIATE_MATRIX_TOP): \
		$(CORE_IMMEDIATE_MATRIX_SOURCES)
	mkdir -p $(CORE_IMMEDIATE_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_IMMEDIATE_MATRIX_TOP) \
		-Mdir $(CORE_IMMEDIATE_MATRIX_BUILD_DIR) \
		$(CORE_IMMEDIATE_MATRIX_SOURCES)

$(CORE_IMMEDIATE_FAULT_BUILD_DIR)/V$(CORE_IMMEDIATE_FAULT_TOP): \
		$(CORE_IMMEDIATE_FAULT_SOURCES)
	mkdir -p $(CORE_IMMEDIATE_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_IMMEDIATE_FAULT_TOP) \
		-Mdir $(CORE_IMMEDIATE_FAULT_BUILD_DIR) \
		$(CORE_IMMEDIATE_FAULT_SOURCES)

$(CORE_MULDIV_BUILD_DIR)/V$(CORE_MULDIV_TOP): $(CORE_MULDIV_SOURCES)
	mkdir -p $(CORE_MULDIV_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_MULDIV_TOP) \
		-Mdir $(CORE_MULDIV_BUILD_DIR) $(CORE_MULDIV_SOURCES)

$(CORE_MULDIV_MATRIX_BUILD_DIR)/V$(CORE_MULDIV_MATRIX_TOP): \
		$(CORE_MULDIV_MATRIX_SOURCES)
	mkdir -p $(CORE_MULDIV_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_MULDIV_MATRIX_TOP) \
		-Mdir $(CORE_MULDIV_MATRIX_BUILD_DIR) \
		$(CORE_MULDIV_MATRIX_SOURCES)

$(CORE_MULDIV_FAULT_BUILD_DIR)/V$(CORE_MULDIV_FAULT_TOP): \
		$(CORE_MULDIV_FAULT_SOURCES)
	mkdir -p $(CORE_MULDIV_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_MULDIV_FAULT_TOP) \
		-Mdir $(CORE_MULDIV_FAULT_BUILD_DIR) \
		$(CORE_MULDIV_FAULT_SOURCES)

$(CORE_DIVIDE_EXCEPTION_BUILD_DIR)/V$(CORE_DIVIDE_EXCEPTION_TOP): \
		$(CORE_DIVIDE_EXCEPTION_SOURCES)
	mkdir -p $(CORE_DIVIDE_EXCEPTION_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_DIVIDE_EXCEPTION_TOP) \
		-Mdir $(CORE_DIVIDE_EXCEPTION_BUILD_DIR) \
		$(CORE_DIVIDE_EXCEPTION_SOURCES)

$(CORE_CMPM_BUILD_DIR)/V$(CORE_CMPM_TOP): $(CORE_CMPM_SOURCES)
	mkdir -p $(CORE_CMPM_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CMPM_TOP) \
		-Mdir $(CORE_CMPM_BUILD_DIR) $(CORE_CMPM_SOURCES)

$(CORE_CMPM_FAULT_BUILD_DIR)/V$(CORE_CMPM_FAULT_TOP): $(CORE_CMPM_FAULT_SOURCES)
	mkdir -p $(CORE_CMPM_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CMPM_FAULT_TOP) \
		-Mdir $(CORE_CMPM_FAULT_BUILD_DIR) $(CORE_CMPM_FAULT_SOURCES)

$(CORE_SHIFT_BUILD_DIR)/V$(CORE_SHIFT_TOP): $(CORE_SHIFT_SOURCES)
	mkdir -p $(CORE_SHIFT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_SHIFT_TOP) \
		-Mdir $(CORE_SHIFT_BUILD_DIR) $(CORE_SHIFT_SOURCES)

$(CORE_MEMORY_SHIFT_BUILD_DIR)/V$(CORE_MEMORY_SHIFT_TOP): $(CORE_MEMORY_SHIFT_SOURCES)
	mkdir -p $(CORE_MEMORY_SHIFT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_MEMORY_SHIFT_TOP) \
		-Mdir $(CORE_MEMORY_SHIFT_BUILD_DIR) $(CORE_MEMORY_SHIFT_SOURCES)

$(CORE_MEMORY_SHIFT_FAULT_BUILD_DIR)/V$(CORE_MEMORY_SHIFT_FAULT_TOP): $(CORE_MEMORY_SHIFT_FAULT_SOURCES)
	mkdir -p $(CORE_MEMORY_SHIFT_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_MEMORY_SHIFT_FAULT_TOP) \
		-Mdir $(CORE_MEMORY_SHIFT_FAULT_BUILD_DIR) $(CORE_MEMORY_SHIFT_FAULT_SOURCES)

$(CORE_CONTROL_ADDRESS_BUILD_DIR)/V$(CORE_CONTROL_ADDRESS_TOP): \
		$(CORE_CONTROL_ADDRESS_SOURCES)
	mkdir -p $(CORE_CONTROL_ADDRESS_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CONTROL_ADDRESS_TOP) \
		-Mdir $(CORE_CONTROL_ADDRESS_BUILD_DIR) \
		$(CORE_CONTROL_ADDRESS_SOURCES)

$(CORE_BINARY_BUILD_DIR)/V$(CORE_BINARY_TOP): $(CORE_BINARY_SOURCES)
	mkdir -p $(CORE_BINARY_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BINARY_TOP) \
		-Mdir $(CORE_BINARY_BUILD_DIR) $(CORE_BINARY_SOURCES)

$(CORE_BINARY_SOURCE_MATRIX_BUILD_DIR)/V$(CORE_BINARY_SOURCE_MATRIX_TOP): \
		$(CORE_BINARY_SOURCE_MATRIX_SOURCES)
	mkdir -p $(CORE_BINARY_SOURCE_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BINARY_SOURCE_MATRIX_TOP) \
		-Mdir $(CORE_BINARY_SOURCE_MATRIX_BUILD_DIR) \
		$(CORE_BINARY_SOURCE_MATRIX_SOURCES)

$(CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR)/V$(CORE_BINARY_DESTINATION_MATRIX_TOP): \
		$(CORE_BINARY_DESTINATION_MATRIX_SOURCES)
	mkdir -p $(CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BINARY_DESTINATION_MATRIX_TOP) \
		-Mdir $(CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR) \
		$(CORE_BINARY_DESTINATION_MATRIX_SOURCES)

$(CORE_BINARY_FAULT_BUILD_DIR)/V$(CORE_BINARY_FAULT_TOP): \
		$(CORE_BINARY_FAULT_SOURCES)
	mkdir -p $(CORE_BINARY_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BINARY_FAULT_TOP) \
		-Mdir $(CORE_BINARY_FAULT_BUILD_DIR) \
		$(CORE_BINARY_FAULT_SOURCES)

$(CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR)/V$(CORE_ADDRESS_ARITHMETIC_MATRIX_TOP): \
		$(CORE_ADDRESS_ARITHMETIC_MATRIX_SOURCES)
	mkdir -p $(CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_ADDRESS_ARITHMETIC_MATRIX_TOP) \
		-Mdir $(CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR) \
		$(CORE_ADDRESS_ARITHMETIC_MATRIX_SOURCES)

$(CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR)/V$(CORE_ADDRESS_ARITHMETIC_FAULT_TOP): \
		$(CORE_ADDRESS_ARITHMETIC_FAULT_SOURCES)
	mkdir -p $(CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_ADDRESS_ARITHMETIC_FAULT_TOP) \
		-Mdir $(CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR) \
		$(CORE_ADDRESS_ARITHMETIC_FAULT_SOURCES)

$(CORE_MOVE_MOVEM_BUILD_DIR)/V$(CORE_MOVE_MOVEM_TOP): \
		$(CORE_MOVE_MOVEM_SOURCES)
	mkdir -p $(CORE_MOVE_MOVEM_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_MOVE_MOVEM_TOP) \
		-Mdir $(CORE_MOVE_MOVEM_BUILD_DIR) $(CORE_MOVE_MOVEM_SOURCES)

$(HIGH_IRQ_BUILD_DIR)/V$(HIGH_IRQ_TOP): $(HIGH_IRQ_SOURCES)
	mkdir -p $(HIGH_IRQ_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(HIGH_IRQ_TOP) \
		-Mdir $(HIGH_IRQ_BUILD_DIR) $(HIGH_IRQ_SOURCES)

$(SD_MODEL_BUILD_DIR)/V$(SD_MODEL_TOP): $(SD_MODEL_SOURCES)
	mkdir -p $(SD_MODEL_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(SD_MODEL_TOP) \
		-Mdir $(SD_MODEL_BUILD_DIR) $(SD_MODEL_SOURCES)

$(SD_MODEL_BUILD_DIR)/sd-card.img:
	mkdir -p $(SD_MODEL_BUILD_DIR)
	truncate -s 1048576 $@

$(LINUX_WORKLOAD_MEMORY_BUILD_DIR)/V$(LINUX_WORKLOAD_MEMORY_TOP): \
		$(LINUX_WORKLOAD_MEMORY_SOURCES)
	mkdir -p $(LINUX_WORKLOAD_MEMORY_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(LINUX_WORKLOAD_MEMORY_TOP) \
		-Mdir $(LINUX_WORKLOAD_MEMORY_BUILD_DIR) \
		$(LINUX_WORKLOAD_MEMORY_SOURCES)

$(FIRMWARE_PROBE_BUILD_DIR)/V$(FIRMWARE_PROBE_TOP): $(FIRMWARE_PROBE_SOURCES)
	mkdir -p $(FIRMWARE_PROBE_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(FIRMWARE_PROBE_TOP) \
		-Mdir $(FIRMWARE_PROBE_BUILD_DIR) $(FIRMWARE_PROBE_SOURCES)

$(FIRMWARE_SIM_BUILD_DIR)/V$(FIRMWARE_SIM_TOP): $(FIRMWARE_SIM_SOURCES)
	mkdir -p $(FIRMWARE_SIM_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --cc --exe --build --assert \
		--timescale 1ns/1ps -Wall -Wno-fatal \
		--top-module $(FIRMWARE_SIM_TOP) -Mdir $(FIRMWARE_SIM_BUILD_DIR) \
		-CFLAGS "-O3" $(FIRMWARE_SIM_RTL_SOURCES) mx68k_firmware_sim.cpp

firmware-probe: $(FIRMWARE_PROBE_BUILD_DIR)/V$(FIRMWARE_PROBE_TOP)
	test -n "$(FIRMWARE_HEX)"
	$(FIRMWARE_PROBE_BUILD_DIR)/V$(FIRMWARE_PROBE_TOP) \
		+FIRMWARE_HEX=$(abspath $(FIRMWARE_HEX))

firmware-sim: $(FIRMWARE_SIM_BUILD_DIR)/V$(FIRMWARE_SIM_TOP)

firmware-run: firmware-sim
	test -n "$(FIRMWARE_HEX)"
	$(FIRMWARE_SIM_BUILD_DIR)/V$(FIRMWARE_SIM_TOP) \
		--firmware $(abspath $(FIRMWARE_HEX)) \
		$(if $(SD_IMAGE),--sd-image $(abspath $(SD_IMAGE))) \
		$(if $(filter 1 yes true,$(SD_WRITABLE)),--sd-writable) $(SIM_ARGS)

firmware-smoke: firmware-sim
	test -n "$(FIRMWARE_HEX)"
	$(FIRMWARE_SIM_BUILD_DIR)/V$(FIRMWARE_SIM_TOP) \
		--firmware $(abspath $(FIRMWARE_HEX)) --no-stdin \
		--command info --expect "DRAM:" --max-cycles 5000000

firmware-linux-smoke: firmware-sim
	test -n "$(FIRMWARE_HEX)"
	test -n "$(IMAGE)"
	$(FIRMWARE_SIM_BUILD_DIR)/V$(FIRMWARE_SIM_TOP) \
		--firmware $(abspath $(FIRMWARE_HEX)) \
		--image $(abspath $(IMAGE)) \
		--platform $(if $(PLATFORM),$(PLATFORM),mackerel-f) \
		--time-scale $(if $(TIME_SCALE),$(TIME_SCALE),1) \
		$(if $(SD_IMAGE),--sd-image $(abspath $(SD_IMAGE))) \
		$(if $(filter 1 yes true,$(SD_WRITABLE)),--sd-writable) \
		$(if $(ROM),--rom $(abspath $(ROM))) --no-stdin \
		--shell-command "uname -a" \
		--expect "$(if $(EXPECT),$(EXPECT),Linux version)" \
		--max-cycles $(if $(MAX_CYCLES),$(MAX_CYCLES),100000000)

decode-check:
	$(PYTHON) $(DECODE_GENERATOR) $(DECODE_DB) $(DECODE_GENERATED) --check

audit-check:
	$(PYTHON) $(AUDIT_CHECKER) $(DECODE_DB) $(AUDIT_DB)

generate-decode:
	$(PYTHON) $(DECODE_GENERATOR) $(DECODE_DB) $(DECODE_GENERATED)

test: decode-check audit-check $(BRIDGE_BUILD_DIR)/V$(BRIDGE_TOP) $(FX68K_BUILD_DIR)/V$(FX68K_TOP) \
		$(ARCH_BUILD_DIR)/V$(ARCH_TOP) $(SHIFTER_BUILD_DIR)/V$(SHIFTER_TOP) \
		$(DIVIDER_BUILD_DIR)/V$(DIVIDER_TOP) \
		$(RAM_BUILD_DIR)/V$(RAM_TOP) \
		$(ROUTER_BUILD_DIR)/V$(ROUTER_TOP) $(FETCH_BUILD_DIR)/V$(FETCH_TOP) \
		$(INSTR_BUILD_DIR)/V$(INSTR_TOP) $(DECODE_BUILD_DIR)/V$(DECODE_TOP) \
		$(DECODE_FRONTEND_BUILD_DIR)/V$(DECODE_FRONTEND_TOP) \
		$(REGFILE_BUILD_DIR)/V$(REGFILE_TOP) \
		$(CORE_M00_BUILD_DIR)/V$(CORE_M00_TOP) \
		$(CORE_UART_BUILD_DIR)/V$(CORE_UART_TOP) \
		$(CORE_IRQ_BUILD_DIR)/V$(CORE_IRQ_TOP) \
		$(CORE_CHK_BUILD_DIR)/V$(CORE_CHK_TOP) \
		$(CORE_TRACE_BUILD_DIR)/V$(CORE_TRACE_TOP) \
		$(CORE_BUS_ERROR_BUILD_DIR)/V$(CORE_BUS_ERROR_TOP) \
		$(CORE_LINE_CROSS_BUILD_DIR)/V$(CORE_LINE_CROSS_TOP) \
		$(CORE_NEGX_BUILD_DIR)/V$(CORE_NEGX_TOP) \
		$(CORE_ADDX_SUBX_BUILD_DIR)/V$(CORE_ADDX_SUBX_TOP) \
		$(CORE_BCD_BUILD_DIR)/V$(CORE_BCD_TOP) \
		$(CORE_EXTEND_MEMORY_FAULT_BUILD_DIR)/V$(CORE_EXTEND_MEMORY_FAULT_TOP) \
		$(CORE_EXG_BUILD_DIR)/V$(CORE_EXG_TOP) \
		$(CORE_TAS_BUILD_DIR)/V$(CORE_TAS_TOP) \
		$(CORE_ADDA_MEM_BUILD_DIR)/V$(CORE_ADDA_MEM_TOP) \
		$(CORE_SR_BUILD_DIR)/V$(CORE_SR_TOP) \
		$(CORE_BIT_BUILD_DIR)/V$(CORE_BIT_TOP) \
		$(CORE_SCC_BUILD_DIR)/V$(CORE_SCC_TOP) \
		$(CORE_SCC_MATRIX_BUILD_DIR)/V$(CORE_SCC_MATRIX_TOP) \
		$(CORE_SCC_FAULT_BUILD_DIR)/V$(CORE_SCC_FAULT_TOP) \
		$(CORE_CLR_BUILD_DIR)/V$(CORE_CLR_TOP) \
		$(CORE_TST_MATRIX_BUILD_DIR)/V$(CORE_TST_MATRIX_TOP) \
		$(CORE_TST_FAULT_BUILD_DIR)/V$(CORE_TST_FAULT_TOP) \
		$(CORE_UNARY_MATRIX_BUILD_DIR)/V$(CORE_UNARY_MATRIX_TOP) \
		$(CORE_UNARY_FAULT_BUILD_DIR)/V$(CORE_UNARY_FAULT_TOP) \
		$(CORE_QUICK_MATRIX_BUILD_DIR)/V$(CORE_QUICK_MATRIX_TOP) \
		$(CORE_QUICK_FAULT_BUILD_DIR)/V$(CORE_QUICK_FAULT_TOP) \
		$(CORE_USP_BUILD_DIR)/V$(CORE_USP_TOP) \
		$(CORE_PEA_BUILD_DIR)/V$(CORE_PEA_TOP) \
		$(CORE_CMPA_BUILD_DIR)/V$(CORE_CMPA_TOP) \
		$(CORE_BSR_BUILD_DIR)/V$(CORE_BSR_TOP) \
		$(CORE_RTR_BUILD_DIR)/V$(CORE_RTR_TOP) \
		$(CORE_DBCC_BUILD_DIR)/V$(CORE_DBCC_TOP) \
		$(CORE_TRAP_BUILD_DIR)/V$(CORE_TRAP_TOP) \
		$(CORE_RESET_INSTRUCTION_BUILD_DIR)/V$(CORE_RESET_INSTRUCTION_TOP) \
		$(CORE_LOGICAL_SR_BUILD_DIR)/V$(CORE_LOGICAL_SR_TOP) \
		$(CORE_SYSTEM_CONTROL_BUILD_DIR)/V$(CORE_SYSTEM_CONTROL_TOP) \
		$(CORE_UNARY_QUICK_BUILD_DIR)/V$(CORE_UNARY_QUICK_TOP) \
		$(CORE_IMMEDIATE_BUILD_DIR)/V$(CORE_IMMEDIATE_TOP) \
		$(CORE_IMMEDIATE_MATRIX_BUILD_DIR)/V$(CORE_IMMEDIATE_MATRIX_TOP) \
		$(CORE_IMMEDIATE_FAULT_BUILD_DIR)/V$(CORE_IMMEDIATE_FAULT_TOP) \
		$(CORE_MULDIV_BUILD_DIR)/V$(CORE_MULDIV_TOP) \
		$(CORE_MULDIV_MATRIX_BUILD_DIR)/V$(CORE_MULDIV_MATRIX_TOP) \
		$(CORE_MULDIV_FAULT_BUILD_DIR)/V$(CORE_MULDIV_FAULT_TOP) \
		$(CORE_DIVIDE_EXCEPTION_BUILD_DIR)/V$(CORE_DIVIDE_EXCEPTION_TOP) \
		$(CORE_CMPM_BUILD_DIR)/V$(CORE_CMPM_TOP) \
		$(CORE_CMPM_FAULT_BUILD_DIR)/V$(CORE_CMPM_FAULT_TOP) \
		$(CORE_SHIFT_BUILD_DIR)/V$(CORE_SHIFT_TOP) \
		$(CORE_MEMORY_SHIFT_BUILD_DIR)/V$(CORE_MEMORY_SHIFT_TOP) \
		$(CORE_MEMORY_SHIFT_FAULT_BUILD_DIR)/V$(CORE_MEMORY_SHIFT_FAULT_TOP) \
		$(CORE_CONTROL_ADDRESS_BUILD_DIR)/V$(CORE_CONTROL_ADDRESS_TOP) \
		$(CORE_BINARY_BUILD_DIR)/V$(CORE_BINARY_TOP) \
		$(CORE_BINARY_SOURCE_MATRIX_BUILD_DIR)/V$(CORE_BINARY_SOURCE_MATRIX_TOP) \
		$(CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR)/V$(CORE_BINARY_DESTINATION_MATRIX_TOP) \
		$(CORE_BINARY_FAULT_BUILD_DIR)/V$(CORE_BINARY_FAULT_TOP) \
		$(CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR)/V$(CORE_ADDRESS_ARITHMETIC_MATRIX_TOP) \
		$(CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR)/V$(CORE_ADDRESS_ARITHMETIC_FAULT_TOP) \
		$(CORE_MOVE_MOVEM_BUILD_DIR)/V$(CORE_MOVE_MOVEM_TOP) \
		$(HIGH_IRQ_BUILD_DIR)/V$(HIGH_IRQ_TOP) \
		$(SD_MODEL_BUILD_DIR)/V$(SD_MODEL_TOP) \
		$(SD_MODEL_BUILD_DIR)/sd-card.img \
		$(LINUX_WORKLOAD_MEMORY_BUILD_DIR)/V$(LINUX_WORKLOAD_MEMORY_TOP)
	$(BRIDGE_BUILD_DIR)/V$(BRIDGE_TOP)
	cd $(FX68K) && ../../build/mx68k_fx68k_smoke/V$(FX68K_TOP)
	$(ARCH_BUILD_DIR)/V$(ARCH_TOP)
	$(SHIFTER_BUILD_DIR)/V$(SHIFTER_TOP)
	$(DIVIDER_BUILD_DIR)/V$(DIVIDER_TOP)
	$(RAM_BUILD_DIR)/V$(RAM_TOP)
	$(ROUTER_BUILD_DIR)/V$(ROUTER_TOP)
	$(FETCH_BUILD_DIR)/V$(FETCH_TOP)
	$(INSTR_BUILD_DIR)/V$(INSTR_TOP)
	$(DECODE_BUILD_DIR)/V$(DECODE_TOP)
	$(DECODE_FRONTEND_BUILD_DIR)/V$(DECODE_FRONTEND_TOP)
	$(REGFILE_BUILD_DIR)/V$(REGFILE_TOP)
	$(CORE_M00_BUILD_DIR)/V$(CORE_M00_TOP)
	$(CORE_UART_BUILD_DIR)/V$(CORE_UART_TOP)
	$(CORE_IRQ_BUILD_DIR)/V$(CORE_IRQ_TOP)
	$(CORE_CHK_BUILD_DIR)/V$(CORE_CHK_TOP)
	$(CORE_TRACE_BUILD_DIR)/V$(CORE_TRACE_TOP)
	$(CORE_BUS_ERROR_BUILD_DIR)/V$(CORE_BUS_ERROR_TOP)
	$(CORE_LINE_CROSS_BUILD_DIR)/V$(CORE_LINE_CROSS_TOP)
	$(CORE_NEGX_BUILD_DIR)/V$(CORE_NEGX_TOP)
	$(CORE_ADDX_SUBX_BUILD_DIR)/V$(CORE_ADDX_SUBX_TOP)
	$(CORE_BCD_BUILD_DIR)/V$(CORE_BCD_TOP)
	$(CORE_EXTEND_MEMORY_FAULT_BUILD_DIR)/V$(CORE_EXTEND_MEMORY_FAULT_TOP)
	$(CORE_EXG_BUILD_DIR)/V$(CORE_EXG_TOP)
	$(CORE_TAS_BUILD_DIR)/V$(CORE_TAS_TOP)
	$(CORE_ADDA_MEM_BUILD_DIR)/V$(CORE_ADDA_MEM_TOP)
	$(CORE_SR_BUILD_DIR)/V$(CORE_SR_TOP)
	$(CORE_BIT_BUILD_DIR)/V$(CORE_BIT_TOP)
	$(CORE_SCC_BUILD_DIR)/V$(CORE_SCC_TOP)
	$(CORE_SCC_MATRIX_BUILD_DIR)/V$(CORE_SCC_MATRIX_TOP)
	$(CORE_SCC_FAULT_BUILD_DIR)/V$(CORE_SCC_FAULT_TOP)
	$(CORE_CLR_BUILD_DIR)/V$(CORE_CLR_TOP)
	$(CORE_TST_MATRIX_BUILD_DIR)/V$(CORE_TST_MATRIX_TOP)
	$(CORE_TST_FAULT_BUILD_DIR)/V$(CORE_TST_FAULT_TOP)
	$(CORE_UNARY_MATRIX_BUILD_DIR)/V$(CORE_UNARY_MATRIX_TOP)
	$(CORE_UNARY_FAULT_BUILD_DIR)/V$(CORE_UNARY_FAULT_TOP)
	$(CORE_QUICK_MATRIX_BUILD_DIR)/V$(CORE_QUICK_MATRIX_TOP)
	$(CORE_QUICK_FAULT_BUILD_DIR)/V$(CORE_QUICK_FAULT_TOP)
	$(CORE_USP_BUILD_DIR)/V$(CORE_USP_TOP)
	$(CORE_PEA_BUILD_DIR)/V$(CORE_PEA_TOP)
	$(CORE_CMPA_BUILD_DIR)/V$(CORE_CMPA_TOP)
	$(CORE_BSR_BUILD_DIR)/V$(CORE_BSR_TOP)
	$(CORE_RTR_BUILD_DIR)/V$(CORE_RTR_TOP)
	$(CORE_DBCC_BUILD_DIR)/V$(CORE_DBCC_TOP)
	$(CORE_TRAP_BUILD_DIR)/V$(CORE_TRAP_TOP)
	$(CORE_RESET_INSTRUCTION_BUILD_DIR)/V$(CORE_RESET_INSTRUCTION_TOP)
	$(CORE_LOGICAL_SR_BUILD_DIR)/V$(CORE_LOGICAL_SR_TOP)
	$(CORE_SYSTEM_CONTROL_BUILD_DIR)/V$(CORE_SYSTEM_CONTROL_TOP)
	$(CORE_UNARY_QUICK_BUILD_DIR)/V$(CORE_UNARY_QUICK_TOP)
	$(CORE_IMMEDIATE_BUILD_DIR)/V$(CORE_IMMEDIATE_TOP)
	$(CORE_IMMEDIATE_MATRIX_BUILD_DIR)/V$(CORE_IMMEDIATE_MATRIX_TOP)
	$(CORE_IMMEDIATE_FAULT_BUILD_DIR)/V$(CORE_IMMEDIATE_FAULT_TOP)
	$(CORE_MULDIV_BUILD_DIR)/V$(CORE_MULDIV_TOP)
	$(CORE_MULDIV_MATRIX_BUILD_DIR)/V$(CORE_MULDIV_MATRIX_TOP)
	$(CORE_MULDIV_FAULT_BUILD_DIR)/V$(CORE_MULDIV_FAULT_TOP)
	$(CORE_DIVIDE_EXCEPTION_BUILD_DIR)/V$(CORE_DIVIDE_EXCEPTION_TOP)
	$(CORE_CMPM_BUILD_DIR)/V$(CORE_CMPM_TOP)
	$(CORE_CMPM_FAULT_BUILD_DIR)/V$(CORE_CMPM_FAULT_TOP)
	$(CORE_SHIFT_BUILD_DIR)/V$(CORE_SHIFT_TOP)
	$(CORE_MEMORY_SHIFT_BUILD_DIR)/V$(CORE_MEMORY_SHIFT_TOP)
	$(CORE_MEMORY_SHIFT_FAULT_BUILD_DIR)/V$(CORE_MEMORY_SHIFT_FAULT_TOP)
	$(CORE_CONTROL_ADDRESS_BUILD_DIR)/V$(CORE_CONTROL_ADDRESS_TOP)
	$(CORE_BINARY_BUILD_DIR)/V$(CORE_BINARY_TOP)
	$(CORE_BINARY_SOURCE_MATRIX_BUILD_DIR)/V$(CORE_BINARY_SOURCE_MATRIX_TOP)
	$(CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR)/V$(CORE_BINARY_DESTINATION_MATRIX_TOP)
	$(CORE_BINARY_FAULT_BUILD_DIR)/V$(CORE_BINARY_FAULT_TOP)
	$(CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR)/V$(CORE_ADDRESS_ARITHMETIC_MATRIX_TOP)
	$(CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR)/V$(CORE_ADDRESS_ARITHMETIC_FAULT_TOP)
	$(CORE_MOVE_MOVEM_BUILD_DIR)/V$(CORE_MOVE_MOVEM_TOP)
	$(HIGH_IRQ_BUILD_DIR)/V$(HIGH_IRQ_TOP)
	$(SD_MODEL_BUILD_DIR)/V$(SD_MODEL_TOP) \
		+SD_IMAGE=$(abspath $(SD_MODEL_BUILD_DIR)/sd-card.img) +SD_WRITABLE
	$(LINUX_WORKLOAD_MEMORY_BUILD_DIR)/V$(LINUX_WORKLOAD_MEMORY_TOP)

lint: decode-check
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(BRIDGE_TOP) $(BRIDGE_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(RAM_TOP) $(RAM_SOURCES)
	$(VERILATOR) --lint-only --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(ARCH_TOP) $(ARCH_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(ROUTER_TOP) $(ROUTER_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(FETCH_TOP) $(FETCH_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(INSTR_TOP) $(INSTR_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(DECODE_TOP) $(DECODE_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(DECODE_FRONTEND_TOP) \
		$(DECODE_FRONTEND_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(REGFILE_TOP) $(REGFILE_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_M00_TOP) $(CORE_M00_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_UART_TOP) $(CORE_UART_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_IRQ_TOP) $(CORE_IRQ_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_CHK_TOP) $(CORE_CHK_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_TRACE_TOP) $(CORE_TRACE_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_BUS_ERROR_TOP) \
		$(CORE_BUS_ERROR_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_LINE_CROSS_TOP) \
		$(CORE_LINE_CROSS_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(CORE_NEGX_TOP) \
		$(CORE_NEGX_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(HIGH_IRQ_TOP) $(HIGH_IRQ_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(LINUX_WORKLOAD_MEMORY_TOP) \
		$(LINUX_WORKLOAD_MEMORY_SOURCES)

clean:
	rm -rf $(BRIDGE_BUILD_DIR) $(FX68K_BUILD_DIR) $(ARCH_BUILD_DIR) \
		$(SHIFTER_BUILD_DIR) $(DIVIDER_BUILD_DIR) $(RAM_BUILD_DIR) \
		$(ROUTER_BUILD_DIR) $(FETCH_BUILD_DIR) \
		$(INSTR_BUILD_DIR) $(DECODE_BUILD_DIR) $(DECODE_FRONTEND_BUILD_DIR)
	$(RM) -r $(REGFILE_BUILD_DIR)
	$(RM) -r $(CORE_M00_BUILD_DIR)
	$(RM) -r $(CORE_UART_BUILD_DIR)
	$(RM) -r $(CORE_IRQ_BUILD_DIR)
	$(RM) -r $(CORE_CHK_BUILD_DIR)
	$(RM) -r $(CORE_TRACE_BUILD_DIR)
	$(RM) -r $(CORE_BUS_ERROR_BUILD_DIR)
	$(RM) -r $(CORE_LINE_CROSS_BUILD_DIR)
	$(RM) -r $(CORE_NEGX_BUILD_DIR)
	$(RM) -r $(CORE_MEMORY_SHIFT_BUILD_DIR)
	$(RM) -r $(CORE_MEMORY_SHIFT_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_ADDX_SUBX_BUILD_DIR)
	$(RM) -r $(CORE_BCD_BUILD_DIR)
	$(RM) -r $(CORE_EXTEND_MEMORY_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_EXG_BUILD_DIR)
	$(RM) -r $(CORE_TAS_BUILD_DIR)
	$(RM) -r $(CORE_ADDA_MEM_BUILD_DIR)
	$(RM) -r $(CORE_SR_BUILD_DIR)
	$(RM) -r $(CORE_BIT_BUILD_DIR)
	$(RM) -r $(CORE_SCC_BUILD_DIR)
	$(RM) -r $(CORE_SCC_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_SCC_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_CLR_BUILD_DIR)
	$(RM) -r $(CORE_TST_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_TST_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_UNARY_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_UNARY_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_QUICK_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_QUICK_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_USP_BUILD_DIR)
	$(RM) -r $(CORE_PEA_BUILD_DIR)
	$(RM) -r $(CORE_CMPA_BUILD_DIR)
	$(RM) -r $(CORE_BSR_BUILD_DIR)
	$(RM) -r $(CORE_RTR_BUILD_DIR)
	$(RM) -r $(CORE_DBCC_BUILD_DIR)
	$(RM) -r $(CORE_TRAP_BUILD_DIR)
	$(RM) -r $(CORE_RESET_INSTRUCTION_BUILD_DIR)
	$(RM) -r $(CORE_LOGICAL_SR_BUILD_DIR)
	$(RM) -r $(CORE_SYSTEM_CONTROL_BUILD_DIR)
	$(RM) -r $(CORE_UNARY_QUICK_BUILD_DIR)
	$(RM) -r $(CORE_IMMEDIATE_BUILD_DIR)
	$(RM) -r $(CORE_IMMEDIATE_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_IMMEDIATE_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_MULDIV_BUILD_DIR)
	$(RM) -r $(CORE_MULDIV_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_MULDIV_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_DIVIDE_EXCEPTION_BUILD_DIR)
	$(RM) -r $(CORE_CMPM_BUILD_DIR)
	$(RM) -r $(CORE_CMPM_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_SHIFT_BUILD_DIR)
	$(RM) -r $(CORE_CONTROL_ADDRESS_BUILD_DIR)
	$(RM) -r $(CORE_BINARY_BUILD_DIR)
	$(RM) -r $(CORE_BINARY_SOURCE_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_BINARY_DESTINATION_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_BINARY_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_ADDRESS_ARITHMETIC_MATRIX_BUILD_DIR)
	$(RM) -r $(CORE_ADDRESS_ARITHMETIC_FAULT_BUILD_DIR)
	$(RM) -r $(CORE_MOVE_MOVEM_BUILD_DIR)
	$(RM) -r $(HIGH_IRQ_BUILD_DIR)
	$(RM) -r $(SD_MODEL_BUILD_DIR)
	$(RM) -r $(LINUX_WORKLOAD_MEMORY_BUILD_DIR)
	$(RM) -r $(FIRMWARE_PROBE_BUILD_DIR)
	$(RM) -r $(FIRMWARE_SIM_BUILD_DIR)
