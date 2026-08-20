.PHONY: all check native-contract-check native-backend-ready first-product-alignment-check rob-lifetime-contract-check uop-completion-contract-check model-test rtl-contract-lint rtl-execute-test native-integer-execute-test native-shift-shared-test native-rotate-extend-test native-multiply-test native-divider-test documentation-check manuals-check manuals-fetch asic-config-check asic-tools asic-native-integer-lint asic-native-integer-synth-check asic-native-integer-synth asic-native-integer-execute-lint asic-native-integer-execute-synth-check asic-native-integer-execute-synth asic-native-shift-lint asic-native-shift-synth-check asic-native-shift-synth asic-native-shift-netlist-equiv asic-native-shift-fast-lint asic-native-shift-fast-synth-check asic-native-shift-fast-synth asic-native-shift-fast-equiv asic-native-shift-shared-lint asic-native-shift-shared-synth-check asic-native-shift-shared-synth asic-native-rotate-extend-lint asic-native-rotate-extend-synth-check asic-native-rotate-extend-synth asic-native-multiply-lint asic-native-multiply-synth-check asic-native-multiply-synth asic-native-divider-lint asic-native-divider-synth-check asic-native-divider-synth asic-nangate45-native-multiply asic-nangate45-native-divider silicon-frontend-check full-build clean

PYTHON ?= python3
PYTHONWARNINGS ?= error
VERILATOR ?= verilator
VERILATOR_BUILD_JOBS ?= 4

NATIVE_RTL_CONTRACT_SOURCES := \
	rtl/packages/m64k_arch_types_pkg.sv \
	rtl/interfaces/memory/m64k_memory_types_pkg.sv \
	rtl/interfaces/translation/m64k_translation_types_pkg.sv \
	rtl/interfaces/interrupt/m64k_interrupt_types_pkg.sv \
	rtl/interfaces/memory/m64k_native_memory_if.sv \
	rtl/interfaces/translation/m64k_native_translation_if.sv \
	rtl/interfaces/interrupt/m64k_targeted_interrupt_if.sv \
	rtl/interfaces/retirement/m64k_precise_retirement_pkg.sv \
	rtl/interfaces/retirement/m64k_precise_retirement_if.sv

NATIVE_RTL_EXECUTE_SOURCES := \
	rtl/core/execute/integer/m64k_integer_alu_pkg.sv \
	rtl/core/execute/integer/m64k_integer_alu.sv

INTEGER_ALU_TEST_BINARY := build/m64k_integer_alu/Vm64k_integer_alu_tb

NATIVE_RTL_INTEGER_EXECUTE_SOURCES := \
	rtl/packages/m64k_arch_types_pkg.sv \
	rtl/core/execute/common/m64k_execute_backend_pkg.sv \
	$(NATIVE_RTL_EXECUTE_SOURCES) \
	rtl/core/execute/integer/m64k_integer_execute_pkg.sv \
	rtl/core/execute/integer/m64k_integer_execute.sv

INTEGER_EXECUTE_TEST_BINARY := build/m64k_integer_execute/Vm64k_integer_execute_tb

NATIVE_RTL_SHIFT_SOURCES := \
	rtl/core/execute/shift/m64k_shift_rotate_pkg.sv \
	rtl/core/execute/shift/m64k_shift_rotate.sv

SHIFT_ROTATE_TEST_BINARY := build/m64k_shift_rotate/Vm64k_shift_rotate_tb

NATIVE_RTL_SHIFT_FAST_SOURCES := \
	$(NATIVE_RTL_SHIFT_SOURCES) \
	rtl/core/execute/shift/m64k_shift_rotate_fast.sv

SHIFT_ROTATE_FAST_TEST_BINARY := build/m64k_shift_rotate_fast/Vm64k_shift_rotate_fast_tb

NATIVE_RTL_SHIFT_SHARED_SOURCES := \
	rtl/packages/m64k_arch_types_pkg.sv \
	rtl/core/execute/common/m64k_execute_backend_pkg.sv \
	$(NATIVE_RTL_SHIFT_FAST_SOURCES) \
	rtl/core/execute/shift/m64k_shift_rotate_shared_pkg.sv \
	rtl/core/execute/shift/m64k_shift_rotate_shared.sv

SHIFT_ROTATE_SHARED_TEST_BINARY := build/m64k_shift_rotate_shared/Vm64k_shift_rotate_shared_tb

NATIVE_RTL_ROTATE_EXTEND_SOURCES := \
	rtl/packages/m64k_arch_types_pkg.sv \
	rtl/core/execute/common/m64k_execute_backend_pkg.sv \
	rtl/core/execute/shift/m64k_shift_rotate_pkg.sv \
	rtl/core/execute/shift/m64k_rotate_extend_iterative_pkg.sv \
	rtl/core/execute/shift/m64k_rotate_extend_iterative.sv

ROTATE_EXTEND_TEST_BINARY := build/m64k_rotate_extend_iterative/Vm64k_rotate_extend_iterative_tb

NATIVE_RTL_MULTIPLY_SOURCES := \
	rtl/packages/m64k_arch_types_pkg.sv \
	rtl/core/execute/common/m64k_execute_backend_pkg.sv \
	rtl/core/execute/multiply/m64k_scalar_multiply_pkg.sv \
	rtl/core/execute/multiply/m64k_scalar_multiply.sv

SCALAR_MULTIPLY_TEST_BINARY := build/m64k_scalar_multiply/Vm64k_scalar_multiply_tb

NATIVE_RTL_DIVIDER_SOURCES := \
	rtl/packages/m64k_arch_types_pkg.sv \
	rtl/core/execute/common/m64k_execute_backend_pkg.sv \
	rtl/core/execute/divide/m64k_scalar_divider_pkg.sv \
	rtl/core/execute/divide/m64k_scalar_divider.sv

SCALAR_DIVIDER_TEST_BINARY := build/m64k_scalar_divider/Vm64k_scalar_divider_tb

all: check

check: native-contract-check first-product-alignment-check rob-lifetime-contract-check uop-completion-contract-check model-test rtl-contract-lint rtl-execute-test documentation-check manuals-check asic-config-check

native-contract-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/test_mc68060_semantic_inventory.py
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_m64k_native_contracts.py
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_m64k_native_contracts

native-backend-ready:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_m64k_native_contracts.py --require-backend-ready

first-product-alignment-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_first_product_alignment
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_first_product_alignment.py

rob-lifetime-contract-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_rob_lifetime_contract
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_rob_lifetime_contract.py

uop-completion-contract-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_uop_completion_contract
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_uop_completion_contract.py

model-test:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest verification.model.test_scalar verification.model.test_multiply_divide

rtl-contract-lint:
	$(VERILATOR) --lint-only --Wall --timing $(NATIVE_RTL_CONTRACT_SOURCES)

rtl-execute-test: $(INTEGER_ALU_TEST_BINARY) $(INTEGER_EXECUTE_TEST_BINARY) $(SHIFT_ROTATE_TEST_BINARY) $(SHIFT_ROTATE_FAST_TEST_BINARY) $(SHIFT_ROTATE_SHARED_TEST_BINARY) $(ROTATE_EXTEND_TEST_BINARY) $(SCALAR_MULTIPLY_TEST_BINARY) $(SCALAR_DIVIDER_TEST_BINARY)
	$(INTEGER_ALU_TEST_BINARY)
	$(INTEGER_EXECUTE_TEST_BINARY)
	$(SHIFT_ROTATE_TEST_BINARY)
	$(SHIFT_ROTATE_FAST_TEST_BINARY)
	$(SHIFT_ROTATE_SHARED_TEST_BINARY)
	$(ROTATE_EXTEND_TEST_BINARY)
	$(SCALAR_MULTIPLY_TEST_BINARY)
	$(SCALAR_DIVIDER_TEST_BINARY)

native-integer-execute-test: $(INTEGER_EXECUTE_TEST_BINARY)
	$(INTEGER_EXECUTE_TEST_BINARY)

native-shift-shared-test: $(SHIFT_ROTATE_SHARED_TEST_BINARY)
	$(SHIFT_ROTATE_SHARED_TEST_BINARY)

native-rotate-extend-test: $(ROTATE_EXTEND_TEST_BINARY)
	$(ROTATE_EXTEND_TEST_BINARY)

native-multiply-test: $(SCALAR_MULTIPLY_TEST_BINARY)
	$(SCALAR_MULTIPLY_TEST_BINARY)

native-divider-test: $(SCALAR_DIVIDER_TEST_BINARY)
	$(SCALAR_DIVIDER_TEST_BINARY)

$(INTEGER_ALU_TEST_BINARY): $(NATIVE_RTL_EXECUTE_SOURCES) verification/rtl/m64k_integer_alu_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --Mdir build/m64k_integer_alu -o Vm64k_integer_alu_tb.pending $(NATIVE_RTL_EXECUTE_SOURCES) verification/rtl/m64k_integer_alu_tb.sv --top-module m64k_integer_alu_tb

$(INTEGER_EXECUTE_TEST_BINARY): $(NATIVE_RTL_INTEGER_EXECUTE_SOURCES) verification/rtl/m64k_integer_execute_properties.sv verification/rtl/m64k_integer_execute_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --assert --Mdir build/m64k_integer_execute -o Vm64k_integer_execute_tb.pending $(NATIVE_RTL_INTEGER_EXECUTE_SOURCES) verification/rtl/m64k_integer_execute_properties.sv verification/rtl/m64k_integer_execute_tb.sv --top-module m64k_integer_execute_tb

$(SHIFT_ROTATE_TEST_BINARY): $(NATIVE_RTL_SHIFT_SOURCES) verification/rtl/m64k_shift_rotate_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --Mdir build/m64k_shift_rotate -o Vm64k_shift_rotate_tb.pending $(NATIVE_RTL_SHIFT_SOURCES) verification/rtl/m64k_shift_rotate_tb.sv --top-module m64k_shift_rotate_tb

$(SHIFT_ROTATE_FAST_TEST_BINARY): $(NATIVE_RTL_SHIFT_FAST_SOURCES) verification/rtl/m64k_shift_rotate_fast_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --Mdir build/m64k_shift_rotate_fast -o Vm64k_shift_rotate_fast_tb.pending $(NATIVE_RTL_SHIFT_FAST_SOURCES) verification/rtl/m64k_shift_rotate_fast_tb.sv --top-module m64k_shift_rotate_fast_tb

$(SHIFT_ROTATE_SHARED_TEST_BINARY): $(NATIVE_RTL_SHIFT_SHARED_SOURCES) verification/rtl/m64k_shift_rotate_shared_checker.sv verification/rtl/m64k_shift_rotate_shared_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --assert --Mdir build/m64k_shift_rotate_shared -o Vm64k_shift_rotate_shared_tb.pending $(NATIVE_RTL_SHIFT_SHARED_SOURCES) verification/rtl/m64k_shift_rotate_shared_checker.sv verification/rtl/m64k_shift_rotate_shared_tb.sv --top-module m64k_shift_rotate_shared_tb

$(ROTATE_EXTEND_TEST_BINARY): $(NATIVE_RTL_ROTATE_EXTEND_SOURCES) verification/rtl/m64k_rotate_extend_iterative_checker.sv verification/rtl/m64k_rotate_extend_iterative_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --assert --Mdir build/m64k_rotate_extend_iterative -o Vm64k_rotate_extend_iterative_tb.pending $(NATIVE_RTL_ROTATE_EXTEND_SOURCES) verification/rtl/m64k_rotate_extend_iterative_checker.sv verification/rtl/m64k_rotate_extend_iterative_tb.sv --top-module m64k_rotate_extend_iterative_tb

$(SCALAR_MULTIPLY_TEST_BINARY): $(NATIVE_RTL_MULTIPLY_SOURCES) verification/rtl/m64k_scalar_multiply_properties.sv verification/rtl/m64k_scalar_multiply_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --assert --Mdir build/m64k_scalar_multiply -o Vm64k_scalar_multiply_tb.pending $(NATIVE_RTL_MULTIPLY_SOURCES) verification/rtl/m64k_scalar_multiply_properties.sv verification/rtl/m64k_scalar_multiply_tb.sv --top-module m64k_scalar_multiply_tb

$(SCALAR_DIVIDER_TEST_BINARY): $(NATIVE_RTL_DIVIDER_SOURCES) verification/rtl/m64k_scalar_divider_properties.sv verification/rtl/m64k_scalar_divider_tb.sv
	CCACHE_DISABLE=1 $(PYTHON) scripts/run_verilator_build.py --output $@ -- $(VERILATOR) --binary --build-jobs $(VERILATOR_BUILD_JOBS) --Wall --timing --assert --Mdir build/m64k_scalar_divider -o Vm64k_scalar_divider_tb.pending $(NATIVE_RTL_DIVIDER_SOURCES) verification/rtl/m64k_scalar_divider_properties.sv verification/rtl/m64k_scalar_divider_tb.sv --top-module m64k_scalar_divider_tb

documentation-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_documentation.py

manuals-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_fetch_reference_manuals
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/fetch_reference_manuals.py --check

manuals-fetch:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/fetch_reference_manuals.py

asic-config-check:
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_run_verilator_build
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_check_yosys_sequential
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest scripts.test_asic_tools
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) -m unittest asic.physical.test_check_logs
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_integer_alu.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_integer_execute.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_shift_rotate.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_shift_rotate_fast.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_shift_rotate_shared.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_rotate_extend_iterative.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_scalar_multiply.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/check_asic_manifest.py asic/manifests/native_scalar_divider.f
	PYTHONWARNINGS=$(PYTHONWARNINGS) $(PYTHON) scripts/run_asic_container.py --print-image

asic-tools:
	$(MAKE) -C asic tools

asic-native-integer-lint:
	$(MAKE) -C asic native-integer-lint

asic-native-integer-synth-check:
	$(MAKE) -C asic native-integer-synth-check

asic-native-integer-synth:
	$(MAKE) -C asic native-integer-synth

asic-native-integer-execute-lint:
	$(MAKE) -C asic native-integer-execute-lint

asic-native-integer-execute-synth-check:
	$(MAKE) -C asic native-integer-execute-synth-check

asic-native-integer-execute-synth:
	$(MAKE) -C asic native-integer-execute-synth

asic-native-shift-lint:
	$(MAKE) -C asic native-shift-lint

asic-native-shift-synth-check:
	$(MAKE) -C asic native-shift-synth-check

asic-native-shift-synth:
	$(MAKE) -C asic native-shift-synth

asic-native-shift-netlist-equiv:
	$(MAKE) -C asic native-shift-netlist-equiv

asic-native-shift-fast-lint:
	$(MAKE) -C asic native-shift-fast-lint

asic-native-shift-fast-synth-check:
	$(MAKE) -C asic native-shift-fast-synth-check

asic-native-shift-fast-synth:
	$(MAKE) -C asic native-shift-fast-synth

asic-native-shift-fast-equiv:
	$(MAKE) -C asic native-shift-fast-equiv

asic-native-shift-shared-lint:
	$(MAKE) -C asic native-shift-shared-lint

asic-native-shift-shared-synth-check:
	$(MAKE) -C asic native-shift-shared-synth-check

asic-native-shift-shared-synth:
	$(MAKE) -C asic native-shift-shared-synth

asic-native-rotate-extend-lint:
	$(MAKE) -C asic native-rotate-extend-lint

asic-native-rotate-extend-synth-check:
	$(MAKE) -C asic native-rotate-extend-synth-check

asic-native-rotate-extend-synth:
	$(MAKE) -C asic native-rotate-extend-synth

asic-native-multiply-lint:
	$(MAKE) -C asic native-multiply-lint

asic-native-multiply-synth-check:
	$(MAKE) -C asic native-multiply-synth-check

asic-native-multiply-synth:
	$(MAKE) -C asic native-multiply-synth

asic-native-divider-lint:
	$(MAKE) -C asic native-divider-lint

asic-native-divider-synth-check:
	$(MAKE) -C asic native-divider-synth-check

asic-native-divider-synth:
	$(MAKE) -C asic native-divider-synth

# These physical acceptance targets intentionally fail while any OpenROAD-flow
# diagnostic remains unresolved. Raw investigation-only targets are documented
# in asic/physical/README.md and are never part of a success gate.
asic-nangate45-native-multiply:
	$(MAKE) -f asic/physical/Makefile nangate45-native-multiply

asic-nangate45-native-divider:
	$(MAKE) -f asic/physical/Makefile nangate45-native-divider

silicon-frontend-check: asic-native-integer-lint asic-native-integer-synth-check asic-native-integer-synth asic-native-integer-execute-lint asic-native-integer-execute-synth-check asic-native-integer-execute-synth asic-native-shift-lint asic-native-shift-synth-check asic-native-shift-netlist-equiv asic-native-shift-fast-lint asic-native-shift-fast-synth-check asic-native-shift-fast-equiv asic-native-shift-shared-lint asic-native-shift-shared-synth-check asic-native-shift-shared-synth asic-native-rotate-extend-lint asic-native-rotate-extend-synth-check asic-native-rotate-extend-synth asic-native-multiply-lint asic-native-multiply-synth-check asic-native-multiply-synth asic-native-divider-lint asic-native-divider-synth-check asic-native-divider-synth

# This gate intentionally remains closed until M64K v1 encoding, ELF, ABI, and
# backend contracts are frozen. It must never report a successful full native
# build by silently substituting an M68K toolchain or payload.
full-build: check native-backend-ready

clean:
	$(RM) -r build
	$(RM) -r model/m64k/__pycache__ verification/model/__pycache__ scripts/__pycache__
