.PHONY: all check native-contract-check native-backend-ready model-test rtl-contract-lint documentation-check manuals-check manuals-fetch full-build clean

PYTHON ?= python3
VERILATOR ?= verilator

NATIVE_RTL_CONTRACT_SOURCES := \
	rtl/interfaces/m64k_native_contract_pkg.sv \
	rtl/interfaces/m64k_native_translation_if.sv \
	rtl/interfaces/m64k_native_memory_if.sv \
	rtl/interfaces/m64k_targeted_interrupt_if.sv \
	rtl/core/contracts/m64k_precise_retirement_pkg.sv \
	rtl/core/contracts/m64k_precise_retirement_if.sv

all: check

check: native-contract-check model-test rtl-contract-lint documentation-check manuals-check

native-contract-check:
	$(PYTHON) scripts/test_mc68060_semantic_inventory.py
	$(PYTHON) scripts/check_m64k_native_contracts.py
	$(PYTHON) -m unittest scripts.test_m64k_native_contracts

native-backend-ready:
	$(PYTHON) scripts/check_m64k_native_contracts.py --require-backend-ready

model-test:
	$(PYTHON) -m unittest verification.model.test_scalar

rtl-contract-lint:
	$(VERILATOR) --lint-only --Wall --timing $(NATIVE_RTL_CONTRACT_SOURCES)

documentation-check:
	$(PYTHON) scripts/check_documentation.py

manuals-check:
	$(PYTHON) -m unittest scripts.test_fetch_reference_manuals
	$(PYTHON) scripts/fetch_reference_manuals.py --check

manuals-fetch:
	$(PYTHON) scripts/fetch_reference_manuals.py

# This gate intentionally remains closed until M64K v1 encoding, ELF, ABI, and
# backend contracts are frozen. It must never report a successful full native
# build by silently substituting an M68K toolchain or payload.
full-build: check native-backend-ready

clean:
	$(RM) -r build
	$(RM) -r model/m64k/__pycache__ verification/model/__pycache__ scripts/__pycache__
