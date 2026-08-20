PHYSICAL_FLOW_DIRECTORY := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPOSITORY_ROOT := $(abspath $(PHYSICAL_FLOW_DIRECTORY)/../..)
CONTAINER := $(REPOSITORY_ROOT)/scripts/run_asic_container.py
ORFS_FLOW := /OpenROAD-flow-scripts/flow
PHYSICAL_BUILD_ROOT := /workspace/build/asic/physical
HOST_PHYSICAL_BUILD_ROOT := $(REPOSITORY_ROOT)/build/asic/physical
LOG_CHECK := $(PHYSICAL_FLOW_DIRECTORY)/check_logs.py
KLAYOUT_TECH_PREPARE := /workspace/asic/physical/prepare_klayout_technology.py
NANGATE45_KLAYOUT_TECH := /OpenROAD-flow-scripts/flow/platforms/nangate45/FreePDK45.lyt
MULTIPLY_CONFIG := /workspace/asic/physical/nangate45/native_scalar_multiply/config.mk
DIVIDER_CONFIG := /workspace/asic/physical/nangate45/native_scalar_divider/config.mk

.PHONY: nangate45-native-multiply nangate45-native-multiply-orfs nangate45-native-divider nangate45-native-divider-orfs

nangate45-native-multiply: nangate45-native-multiply-orfs
	PYTHONWARNINGS=error python3 $(LOG_CHECK) $(HOST_PHYSICAL_BUILD_ROOT)/native_scalar_multiply/logs/nangate45/m64k_native_scalar_multiply/explore_4ns --report-root $(HOST_PHYSICAL_BUILD_ROOT)/native_scalar_multiply/reports/nangate45/m64k_native_scalar_multiply/explore_4ns

nangate45-native-multiply-orfs:
	PYTHONWARNINGS=error python3 $(CONTAINER) -- python3 $(KLAYOUT_TECH_PREPARE) $(NANGATE45_KLAYOUT_TECH) $(PHYSICAL_BUILD_ROOT)/native_scalar_multiply/m64k-FreePDK45.lyt
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; install -d -m 700 /tmp/m64k-xdg-runtime; export XDG_RUNTIME_DIR=/tmp/m64k-xdg-runtime; source /OpenROAD-flow-scripts/env.sh; $(MAKE) -C $(ORFS_FLOW) DESIGN_CONFIG=$(MULTIPLY_CONFIG) WORK_HOME=$(PHYSICAL_BUILD_ROOT)/native_scalar_multiply FLOW_VARIANT=explore_4ns finish'

nangate45-native-divider: nangate45-native-divider-orfs
	PYTHONWARNINGS=error python3 $(LOG_CHECK) $(HOST_PHYSICAL_BUILD_ROOT)/native_scalar_divider/logs/nangate45/m64k_native_scalar_divider/explore_4ns --report-root $(HOST_PHYSICAL_BUILD_ROOT)/native_scalar_divider/reports/nangate45/m64k_native_scalar_divider/explore_4ns

nangate45-native-divider-orfs:
	PYTHONWARNINGS=error python3 $(CONTAINER) -- python3 $(KLAYOUT_TECH_PREPARE) $(NANGATE45_KLAYOUT_TECH) $(PHYSICAL_BUILD_ROOT)/native_scalar_divider/m64k-FreePDK45.lyt
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; install -d -m 700 /tmp/m64k-xdg-runtime; export XDG_RUNTIME_DIR=/tmp/m64k-xdg-runtime; source /OpenROAD-flow-scripts/env.sh; $(MAKE) -C $(ORFS_FLOW) DESIGN_CONFIG=$(DIVIDER_CONFIG) WORK_HOME=$(PHYSICAL_BUILD_ROOT)/native_scalar_divider FLOW_VARIANT=explore_4ns finish'
