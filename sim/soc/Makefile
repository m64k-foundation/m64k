VERILATOR ?= verilator
ROOT := ../..
PERIPHERAL_BUILD_DIR := $(ROOT)/build/m64k_peripherals
PERIPHERAL_TOP := m64k_peripherals_tb
ROM_BUILD_DIR := $(ROOT)/build/m64k_boot_rom
ROM_TOP := m64k_boot_rom_tb

COMMON_SOURCES := \
	$(ROOT)/rtl/interconnect/interfaces/m64k_pkg.sv \
	$(ROOT)/rtl/interconnect/interfaces/m64k_mem_if.sv

PERIPHERAL_SOURCES := $(COMMON_SOURCES) \
	$(ROOT)/rtl/soc/peripherals/m64k_error_slave.sv \
	$(ROOT)/rtl/soc/peripherals/m64k_uart.sv \
	$(ROOT)/rtl/soc/peripherals/m64k_timer.sv \
	$(ROOT)/rtl/soc/peripherals/m64k_sysinfo.sv \
	m64k_peripherals_tb.sv

ROM_SOURCES := $(COMMON_SOURCES) \
	$(ROOT)/sim/models/memory/m64k_dual_port_ram.sv \
	m64k_boot_rom_tb.sv

.PHONY: all test lint clean

all: test

$(PERIPHERAL_BUILD_DIR)/V$(PERIPHERAL_TOP): $(PERIPHERAL_SOURCES)
	mkdir -p $(PERIPHERAL_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(PERIPHERAL_TOP) -Mdir $(PERIPHERAL_BUILD_DIR) $(PERIPHERAL_SOURCES)

$(ROM_BUILD_DIR)/V$(ROM_TOP): $(ROM_SOURCES) m64k_boot_rom.hex
	mkdir -p $(ROM_BUILD_DIR)
	CCACHE_DISABLE=1 $(VERILATOR) --binary --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(ROM_TOP) -Mdir $(ROM_BUILD_DIR) $(ROM_SOURCES)

test: $(PERIPHERAL_BUILD_DIR)/V$(PERIPHERAL_TOP) $(ROM_BUILD_DIR)/V$(ROM_TOP)
	$(PERIPHERAL_BUILD_DIR)/V$(PERIPHERAL_TOP)
	$(ROM_BUILD_DIR)/V$(ROM_TOP)

lint:
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(PERIPHERAL_TOP) $(PERIPHERAL_SOURCES)
	$(VERILATOR) --lint-only --timing --assert --timescale 1ns/1ps \
		-Wall -Wno-fatal --top-module $(ROM_TOP) $(ROM_SOURCES)

clean:
	$(RM) -r $(PERIPHERAL_BUILD_DIR) $(ROM_BUILD_DIR)
