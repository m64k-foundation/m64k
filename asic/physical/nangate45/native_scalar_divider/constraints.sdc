current_design m64k_scalar_divider

set clock_period_ns 4.0
set io_budget_fraction 0.20
set clock_port [get_ports clock]

create_clock -name execution_clock -period $clock_period_ns $clock_port

set non_clock_inputs [all_inputs -no_clocks]
set_input_delay [expr {$clock_period_ns * $io_budget_fraction}] -clock execution_clock $non_clock_inputs
set_output_delay [expr {$clock_period_ns * $io_budget_fraction}] -clock execution_clock [all_outputs]
