export DESIGN_NICKNAME = m64k_native_scalar_multiply
export DESIGN_NAME = m64k_scalar_multiply
export PLATFORM = nangate45

export VERILOG_FILES = \
    /workspace/rtl/packages/m64k_arch_types_pkg.sv \
    /workspace/rtl/core/execute/common/m64k_execute_backend_pkg.sv \
    /workspace/rtl/core/execute/multiply/m64k_scalar_multiply_pkg.sv \
    /workspace/rtl/core/execute/multiply/m64k_scalar_multiply.sv

export SYNTH_HDL_FRONTEND = slang
export SDC_FILE = /workspace/asic/physical/nangate45/native_scalar_multiply/constraints.sdc
export PRE_GLOBAL_ROUTE_TCL = /workspace/asic/physical/remove_unused_cell_output_nets.tcl
export POST_FINAL_REPORT_TCL = /workspace/asic/physical/report_final_constraint_integrity.tcl

export CORE_UTILIZATION = 50
# Align the lower-left core origin to the Nangate45 0.19 um site width and
# 1.40 um row height instead of asking initialize_floorplan to snap it.
export CORE_MARGIN = 1.40 1.40 1.14 1.14
export PLACE_DENSITY_LB_ADDON = 0.10
export TNS_END_PERCENT = 100
export PDN_TCL = /workspace/asic/physical/nangate45/standard_cell_pdn.tcl
override export KLAYOUT_TECH_FILE = /workspace/build/asic/physical/native_scalar_multiply/m64k-FreePDK45.lyt

# Nangate45 provides no ANTENNACELL-class diode. Do not invoke an impossible
# repair operation; the independent acceptance gate still requires the final
# detailed-route antenna report and detailed-route DRC report to be empty.
export SKIP_ANTENNA_REPAIR = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
