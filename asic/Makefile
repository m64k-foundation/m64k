REPOSITORY_ROOT := $(abspath ..)
CONTAINER := $(REPOSITORY_ROOT)/scripts/run_asic_container.py
MANIFEST_CHECK := $(REPOSITORY_ROOT)/scripts/check_asic_manifest.py
WARNING_CHECK := $(REPOSITORY_ROOT)/scripts/check_yosys_log.py
QOR_SUMMARY := $(REPOSITORY_ROOT)/scripts/summarize_yosys_stat.py
EQUIV_SUMMARY := $(REPOSITORY_ROOT)/scripts/summarize_yosys_equivalence.py
SEQUENTIAL_CHECK := $(REPOSITORY_ROOT)/scripts/check_yosys_sequential.py
INTEGER_ALU_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_integer_alu.f
INTEGER_ALU_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(INTEGER_ALU_MANIFEST) --print-sources)
INTEGER_ALU_TOP := m64k_integer_alu
INTEGER_ALU_BUILD := $(REPOSITORY_ROOT)/build/asic/native_integer_alu/generic
INTEGER_EXECUTE_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_integer_execute.f
INTEGER_EXECUTE_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(INTEGER_EXECUTE_MANIFEST) --print-sources)
INTEGER_EXECUTE_TOP := m64k_integer_execute
INTEGER_EXECUTE_BUILD := $(REPOSITORY_ROOT)/build/asic/native_integer_execute/generic
SHIFT_ROTATE_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_shift_rotate.f
SHIFT_ROTATE_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SHIFT_ROTATE_MANIFEST) --print-sources)
SHIFT_ROTATE_TOP := m64k_shift_rotate
SHIFT_ROTATE_BUILD := $(REPOSITORY_ROOT)/build/asic/native_shift_rotate/generic
SHIFT_ROTATE_FAST_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_shift_rotate_fast.f
SHIFT_ROTATE_FAST_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SHIFT_ROTATE_FAST_MANIFEST) --print-sources)
SHIFT_ROTATE_FAST_TOP := m64k_shift_rotate_fast
SHIFT_ROTATE_FAST_BUILD := $(REPOSITORY_ROOT)/build/asic/native_shift_rotate_fast/generic
SHIFT_ROTATE_FAST_MITER := verification/equiv/m64k_shift_rotate_fast_miter.sv
SHIFT_ROTATE_SHARED_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_shift_rotate_shared.f
SHIFT_ROTATE_SHARED_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SHIFT_ROTATE_SHARED_MANIFEST) --print-sources)
SHIFT_ROTATE_SHARED_TOP := m64k_shift_rotate_shared
SHIFT_ROTATE_SHARED_BUILD := $(REPOSITORY_ROOT)/build/asic/native_shift_rotate_shared/generic
ROTATE_EXTEND_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_rotate_extend_iterative.f
ROTATE_EXTEND_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(ROTATE_EXTEND_MANIFEST) --print-sources)
ROTATE_EXTEND_TOP := m64k_rotate_extend_iterative
ROTATE_EXTEND_BUILD := $(REPOSITORY_ROOT)/build/asic/native_rotate_extend_iterative/generic
SCALAR_MULTIPLY_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_scalar_multiply.f
SCALAR_MULTIPLY_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SCALAR_MULTIPLY_MANIFEST) --print-sources)
SCALAR_MULTIPLY_TOP := m64k_scalar_multiply
SCALAR_MULTIPLY_BUILD := $(REPOSITORY_ROOT)/build/asic/native_scalar_multiply/generic
SCALAR_DIVIDER_MANIFEST := $(REPOSITORY_ROOT)/asic/manifests/native_scalar_divider.f
SCALAR_DIVIDER_SOURCES := $(shell PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SCALAR_DIVIDER_MANIFEST) --print-sources)
SCALAR_DIVIDER_TOP := m64k_scalar_divider
SCALAR_DIVIDER_BUILD := $(REPOSITORY_ROOT)/build/asic/native_scalar_divider/generic

.PHONY: tools manifest-check native-integer-lint native-integer-synth-check native-integer-synth native-integer-execute-lint native-integer-execute-synth-check native-integer-execute-synth native-shift-lint native-shift-synth-check native-shift-synth native-shift-netlist-equiv native-shift-fast-lint native-shift-fast-synth-check native-shift-fast-synth native-shift-fast-equiv native-shift-shared-lint native-shift-shared-synth-check native-shift-shared-synth native-rotate-extend-lint native-rotate-extend-synth-check native-rotate-extend-synth native-multiply-lint native-multiply-synth-check native-multiply-synth native-divider-lint native-divider-synth-check native-divider-synth clean

tools:
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -V | grep -F "Yosys 0.68+post"; yosys -p "help read_slang" | grep -F "Read SystemVerilog"; openroad -version | grep -F "26Q3-1305-gf552262465"; sta -version | grep -F "3.1.0"'

manifest-check:
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(INTEGER_ALU_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(INTEGER_EXECUTE_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SHIFT_ROTATE_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SHIFT_ROTATE_FAST_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SHIFT_ROTATE_SHARED_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(ROTATE_EXTEND_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SCALAR_MULTIPLY_MANIFEST)
	PYTHONWARNINGS=error python3 $(MANIFEST_CHECK) $(SCALAR_DIVIDER_MANIFEST)

native-integer-execute-lint: manifest-check
	mkdir -p $(INTEGER_EXECUTE_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_integer_execute/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(INTEGER_EXECUTE_TOP) -Werror $(INTEGER_EXECUTE_SOURCES); hierarchy -check -top $(INTEGER_EXECUTE_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(INTEGER_EXECUTE_BUILD)/slang-lint.log

native-integer-execute-synth-check: manifest-check
	mkdir -p $(INTEGER_EXECUTE_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_integer_execute/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(INTEGER_EXECUTE_TOP) -Werror $(INTEGER_EXECUTE_SOURCES); hierarchy -check -top $(INTEGER_EXECUTE_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(INTEGER_EXECUTE_BUILD)/yosys-check.log

native-integer-execute-synth: manifest-check
	mkdir -p $(INTEGER_EXECUTE_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_integer_execute/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(INTEGER_EXECUTE_TOP) -Werror $(INTEGER_EXECUTE_SOURCES); hierarchy -check -top $(INTEGER_EXECUTE_TOP); synth -top $(INTEGER_EXECUTE_TOP); check -assert; tee -o build/asic/native_integer_execute/generic/stat.json stat -json; write_verilog -noattr build/asic/native_integer_execute/generic/m64k_integer_execute.v"'
	PYTHONWARNINGS=error python3 $(SEQUENTIAL_CHECK) $(INTEGER_EXECUTE_BUILD)/stat.json --top $(INTEGER_EXECUTE_TOP) --minimum-cells 100
	# ABC reports one exact informational diagnostic for the extracted combinational cone feeding the proven response register. The classifier rejects every other warning.
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(INTEGER_EXECUTE_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(INTEGER_EXECUTE_BUILD)/stat.json --manifest $(INTEGER_EXECUTE_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(INTEGER_EXECUTE_BUILD)/m64k_integer_execute.v --log $(INTEGER_EXECUTE_BUILD)/yosys.log --target native_integer_execute --top $(INTEGER_EXECUTE_TOP) --output $(INTEGER_EXECUTE_BUILD)/qor.json

native-rotate-extend-lint: manifest-check
	mkdir -p $(ROTATE_EXTEND_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_rotate_extend_iterative/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(ROTATE_EXTEND_TOP) -Werror $(ROTATE_EXTEND_SOURCES); hierarchy -check -top $(ROTATE_EXTEND_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(ROTATE_EXTEND_BUILD)/slang-lint.log

native-rotate-extend-synth-check: manifest-check
	mkdir -p $(ROTATE_EXTEND_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_rotate_extend_iterative/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(ROTATE_EXTEND_TOP) -Werror $(ROTATE_EXTEND_SOURCES); hierarchy -check -top $(ROTATE_EXTEND_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(ROTATE_EXTEND_BUILD)/yosys-check.log

native-rotate-extend-synth: manifest-check
	mkdir -p $(ROTATE_EXTEND_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_rotate_extend_iterative/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(ROTATE_EXTEND_TOP) -Werror $(ROTATE_EXTEND_SOURCES); hierarchy -check -top $(ROTATE_EXTEND_TOP); synth -top $(ROTATE_EXTEND_TOP); check -assert; tee -o build/asic/native_rotate_extend_iterative/generic/stat.json stat -json; write_verilog -noattr build/asic/native_rotate_extend_iterative/generic/m64k_rotate_extend_iterative.v"'
	PYTHONWARNINGS=error python3 $(SEQUENTIAL_CHECK) $(ROTATE_EXTEND_BUILD)/stat.json --top $(ROTATE_EXTEND_TOP) --minimum-cells 200
	# ABC reports one exact informational diagnostic for the extracted combinational cone between the proven iterative state registers. The classifier rejects every other warning.
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(ROTATE_EXTEND_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(ROTATE_EXTEND_BUILD)/stat.json --manifest $(ROTATE_EXTEND_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(ROTATE_EXTEND_BUILD)/m64k_rotate_extend_iterative.v --log $(ROTATE_EXTEND_BUILD)/yosys.log --target native_rotate_extend_iterative --top $(ROTATE_EXTEND_TOP) --output $(ROTATE_EXTEND_BUILD)/qor.json

native-divider-lint: manifest-check
	mkdir -p $(SCALAR_DIVIDER_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_scalar_divider/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(SCALAR_DIVIDER_TOP) -Werror $(SCALAR_DIVIDER_SOURCES); hierarchy -check -top $(SCALAR_DIVIDER_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SCALAR_DIVIDER_BUILD)/slang-lint.log

native-divider-synth-check: manifest-check
	mkdir -p $(SCALAR_DIVIDER_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_scalar_divider/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(SCALAR_DIVIDER_TOP) -Werror $(SCALAR_DIVIDER_SOURCES); hierarchy -check -top $(SCALAR_DIVIDER_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SCALAR_DIVIDER_BUILD)/yosys-check.log

native-divider-synth: manifest-check
	mkdir -p $(SCALAR_DIVIDER_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_scalar_divider/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(SCALAR_DIVIDER_TOP) -Werror $(SCALAR_DIVIDER_SOURCES); hierarchy -check -top $(SCALAR_DIVIDER_TOP); synth -top $(SCALAR_DIVIDER_TOP); check -assert; tee -o build/asic/native_scalar_divider/generic/stat.json stat -json; write_verilog -noattr build/asic/native_scalar_divider/generic/m64k_scalar_divider.v"'
	PYTHONWARNINGS=error python3 $(SEQUENTIAL_CHECK) $(SCALAR_DIVIDER_BUILD)/stat.json --top $(SCALAR_DIVIDER_TOP) --minimum-cells 400
	# ABC emits one exact informational diagnostic for the extracted combinational cone between the proven state registers. The classifier rejects every other warning.
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SCALAR_DIVIDER_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(SCALAR_DIVIDER_BUILD)/stat.json --manifest $(SCALAR_DIVIDER_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(SCALAR_DIVIDER_BUILD)/m64k_scalar_divider.v --log $(SCALAR_DIVIDER_BUILD)/yosys.log --target native_scalar_divider --top $(SCALAR_DIVIDER_TOP) --output $(SCALAR_DIVIDER_BUILD)/qor.json

native-multiply-lint: manifest-check
	mkdir -p $(SCALAR_MULTIPLY_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_scalar_multiply/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(SCALAR_MULTIPLY_TOP) -Werror $(SCALAR_MULTIPLY_SOURCES); hierarchy -check -top $(SCALAR_MULTIPLY_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SCALAR_MULTIPLY_BUILD)/slang-lint.log

native-multiply-synth-check: manifest-check
	mkdir -p $(SCALAR_MULTIPLY_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_scalar_multiply/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(SCALAR_MULTIPLY_TOP) -Werror $(SCALAR_MULTIPLY_SOURCES); hierarchy -check -top $(SCALAR_MULTIPLY_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SCALAR_MULTIPLY_BUILD)/yosys-check.log

native-multiply-synth: manifest-check
	mkdir -p $(SCALAR_MULTIPLY_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_scalar_multiply/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(SCALAR_MULTIPLY_TOP) -Werror $(SCALAR_MULTIPLY_SOURCES); hierarchy -check -top $(SCALAR_MULTIPLY_TOP); synth -top $(SCALAR_MULTIPLY_TOP); check -assert; tee -o build/asic/native_scalar_multiply/generic/stat.json stat -json; write_verilog -noattr build/asic/native_scalar_multiply/generic/m64k_scalar_multiply.v"'
	PYTHONWARNINGS=error python3 $(SEQUENTIAL_CHECK) $(SCALAR_MULTIPLY_BUILD)/stat.json --top $(SCALAR_MULTIPLY_TOP) --minimum-cells 1000
	# ABC reports one exact informational diagnostic for the extracted combinational cone between the proven pipeline registers; the classifier rejects every other warning.
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SCALAR_MULTIPLY_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(SCALAR_MULTIPLY_BUILD)/stat.json --manifest $(SCALAR_MULTIPLY_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(SCALAR_MULTIPLY_BUILD)/m64k_scalar_multiply.v --log $(SCALAR_MULTIPLY_BUILD)/yosys.log --target native_scalar_multiply --top $(SCALAR_MULTIPLY_TOP) --output $(SCALAR_MULTIPLY_BUILD)/qor.json

native-integer-lint: manifest-check
	mkdir -p $(INTEGER_ALU_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_integer_alu/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(INTEGER_ALU_TOP) -Werror $(INTEGER_ALU_SOURCES); hierarchy -check -top $(INTEGER_ALU_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(INTEGER_ALU_BUILD)/slang-lint.log

native-integer-synth-check: manifest-check
	mkdir -p $(INTEGER_ALU_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_integer_alu/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(INTEGER_ALU_TOP) -Werror $(INTEGER_ALU_SOURCES); hierarchy -check -top $(INTEGER_ALU_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(INTEGER_ALU_BUILD)/yosys-check.log

native-integer-synth: manifest-check
	mkdir -p $(INTEGER_ALU_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_integer_alu/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(INTEGER_ALU_TOP) -Werror $(INTEGER_ALU_SOURCES); hierarchy -check -top $(INTEGER_ALU_TOP); synth -top $(INTEGER_ALU_TOP); check -assert; tee -o build/asic/native_integer_alu/generic/stat.json stat -json; write_verilog -noattr build/asic/native_integer_alu/generic/m64k_integer_alu.v"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(INTEGER_ALU_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(INTEGER_ALU_BUILD)/stat.json --manifest $(INTEGER_ALU_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(INTEGER_ALU_BUILD)/m64k_integer_alu.v --log $(INTEGER_ALU_BUILD)/yosys.log --target native_integer_alu --top $(INTEGER_ALU_TOP) --output $(INTEGER_ALU_BUILD)/qor.json

native-shift-lint: manifest-check
	mkdir -p $(SHIFT_ROTATE_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_TOP) -Werror $(SHIFT_ROTATE_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_BUILD)/slang-lint.log

native-shift-synth-check: manifest-check
	mkdir -p $(SHIFT_ROTATE_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_TOP) -Werror $(SHIFT_ROTATE_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_BUILD)/yosys-check.log

native-shift-synth: manifest-check
	mkdir -p $(SHIFT_ROTATE_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_TOP) -Werror $(SHIFT_ROTATE_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_TOP); synth -top $(SHIFT_ROTATE_TOP); check -assert; tee -o build/asic/native_shift_rotate/generic/stat.json stat -json; write_verilog -noattr build/asic/native_shift_rotate/generic/m64k_shift_rotate.v"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(SHIFT_ROTATE_BUILD)/stat.json --manifest $(SHIFT_ROTATE_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(SHIFT_ROTATE_BUILD)/m64k_shift_rotate.v --log $(SHIFT_ROTATE_BUILD)/yosys.log --target native_shift_rotate --top $(SHIFT_ROTATE_TOP) --output $(SHIFT_ROTATE_BUILD)/qor.json

native-shift-netlist-equiv: native-shift-synth
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate/generic/netlist-equiv.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_TOP) -Werror $(SHIFT_ROTATE_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_TOP); proc; opt; rename $(SHIFT_ROTATE_TOP) gold; read_verilog build/asic/native_shift_rotate/generic/m64k_shift_rotate.v; rename $(SHIFT_ROTATE_TOP) gate; equiv_make gold gate equiv; hierarchy -check -top equiv; equiv_simple; equiv_status -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_BUILD)/netlist-equiv.log

native-shift-fast-lint: manifest-check
	mkdir -p $(SHIFT_ROTATE_FAST_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_fast/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_FAST_TOP) -Werror $(SHIFT_ROTATE_FAST_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_FAST_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_FAST_BUILD)/slang-lint.log

native-shift-fast-synth-check: manifest-check
	mkdir -p $(SHIFT_ROTATE_FAST_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_fast/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_FAST_TOP) -Werror $(SHIFT_ROTATE_FAST_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_FAST_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_FAST_BUILD)/yosys-check.log

native-shift-fast-synth: manifest-check
	mkdir -p $(SHIFT_ROTATE_FAST_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_fast/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_FAST_TOP) -Werror $(SHIFT_ROTATE_FAST_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_FAST_TOP); synth -top $(SHIFT_ROTATE_FAST_TOP); check -assert; tee -o build/asic/native_shift_rotate_fast/generic/stat.json stat -json; write_verilog -noattr build/asic/native_shift_rotate_fast/generic/m64k_shift_rotate_fast.v"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_FAST_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(SHIFT_ROTATE_FAST_BUILD)/stat.json --manifest $(SHIFT_ROTATE_FAST_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(SHIFT_ROTATE_FAST_BUILD)/m64k_shift_rotate_fast.v --log $(SHIFT_ROTATE_FAST_BUILD)/yosys.log --target native_shift_rotate_fast --top $(SHIFT_ROTATE_FAST_TOP) --output $(SHIFT_ROTATE_FAST_BUILD)/qor.json

native-shift-fast-equiv: native-shift-fast-synth
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_fast/generic/reference-equiv.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_TOP) -Werror $(SHIFT_ROTATE_SOURCES); read_verilog build/asic/native_shift_rotate_fast/generic/m64k_shift_rotate_fast.v; read_verilog -sv $(SHIFT_ROTATE_FAST_MITER); hierarchy -check -top m64k_shift_rotate_fast_miter; prep -top m64k_shift_rotate_fast_miter -flatten; sat -verify -prove miter_pass 1 -set-def-inputs -show-inputs -show-outputs"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_FAST_BUILD)/reference-equiv.log
	PYTHONWARNINGS=error python3 $(EQUIV_SUMMARY) --log $(SHIFT_ROTATE_FAST_BUILD)/reference-equiv.log --reference-manifest $(SHIFT_ROTATE_MANIFEST) --candidate-manifest $(SHIFT_ROTATE_FAST_MANIFEST) --candidate-netlist $(SHIFT_ROTATE_FAST_BUILD)/m64k_shift_rotate_fast.v --miter $(REPOSITORY_ROOT)/$(SHIFT_ROTATE_FAST_MITER) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --target native_shift_rotate_fast_vs_reference --output $(SHIFT_ROTATE_FAST_BUILD)/equivalence.json

native-shift-shared-lint: manifest-check
	mkdir -p $(SHIFT_ROTATE_SHARED_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_shared/generic/slang-lint.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_SHARED_TOP) -Werror $(SHIFT_ROTATE_SHARED_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_SHARED_TOP); check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_SHARED_BUILD)/slang-lint.log

native-shift-shared-synth-check: manifest-check
	mkdir -p $(SHIFT_ROTATE_SHARED_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_shared/generic/yosys-check.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_SHARED_TOP) -Werror $(SHIFT_ROTATE_SHARED_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_SHARED_TOP); proc; opt; check -assert"'
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_SHARED_BUILD)/yosys-check.log

native-shift-shared-synth: manifest-check
	mkdir -p $(SHIFT_ROTATE_SHARED_BUILD)
	PYTHONWARNINGS=error python3 $(CONTAINER) -- bash -c 'set -eo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -ql build/asic/native_shift_rotate_shared/generic/yosys.log -p "read_slang --std 1800-2023 --single-unit --top $(SHIFT_ROTATE_SHARED_TOP) -Werror $(SHIFT_ROTATE_SHARED_SOURCES); hierarchy -check -top $(SHIFT_ROTATE_SHARED_TOP); synth -top $(SHIFT_ROTATE_SHARED_TOP); check -assert; tee -o build/asic/native_shift_rotate_shared/generic/stat.json stat -json; write_verilog -noattr build/asic/native_shift_rotate_shared/generic/m64k_shift_rotate_shared.v"'
	PYTHONWARNINGS=error python3 $(SEQUENTIAL_CHECK) $(SHIFT_ROTATE_SHARED_BUILD)/stat.json --top $(SHIFT_ROTATE_SHARED_TOP) --minimum-cells 200
	# ABC reports one exact informational diagnostic for the extracted combinational cone between the candidate's state registers. The classifier rejects every other warning.
	PYTHONWARNINGS=error python3 $(WARNING_CHECK) $(SHIFT_ROTATE_SHARED_BUILD)/yosys.log --allow-one-abc-combinational
	PYTHONWARNINGS=error python3 $(QOR_SUMMARY) --stat $(SHIFT_ROTATE_SHARED_BUILD)/stat.json --manifest $(SHIFT_ROTATE_SHARED_MANIFEST) --tool-lock $(REPOSITORY_ROOT)/containers/asic/tool-lock.json --flow $(REPOSITORY_ROOT)/asic/Makefile --netlist $(SHIFT_ROTATE_SHARED_BUILD)/m64k_shift_rotate_shared.v --log $(SHIFT_ROTATE_SHARED_BUILD)/yosys.log --target native_shift_rotate_shared --top $(SHIFT_ROTATE_SHARED_TOP) --output $(SHIFT_ROTATE_SHARED_BUILD)/qor.json

clean:
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_integer_alu
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_integer_execute
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_shift_rotate
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_shift_rotate_fast
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_shift_rotate_shared
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_rotate_extend_iterative
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_scalar_multiply
	$(RM) -r $(REPOSITORY_ROOT)/build/asic/native_scalar_divider
