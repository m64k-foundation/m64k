# Emit a machine-gated final constraint-integrity report.
#
# OpenSTA writes nothing when every requested check passes. The host acceptance
# gate requires this file to exist and be empty, so an absent check and an
# unconstrained design both fail closed.

check_setup \
    -no_input_delay \
    -no_output_delay \
    -multiple_clock \
    -no_clock \
    -unconstrained_endpoints \
    -loops \
    > $::env(REPORTS_DIR)/6_constraint_integrity.rpt
