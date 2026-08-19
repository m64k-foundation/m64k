TOP := mackerel_f
CORE := third_party/fx68k
UART := third_party/uart16550/rtl/verilog
SDRAM := third_party/sdram-tang-nano-20k/src
SPI := third_party/tiny_spi/rtl/verilog
FPGA_DIR := fpga/tang-nano-20k
LEGACY_RTL_DIR := rtl/legacy/mackerel-f

GW ?= QT_QPA_PLATFORM=offscreen LD_LIBRARY_PATH=$(HOME)/Gowin_EDA/IDE/lib $(HOME)/Gowin_EDA/IDE/bin/gw_sh
LOADER ?= $(HOME)/oss-cad-suite/bin/openFPGALoader
IVERILOG ?= iverilog
VVP ?= vvp
BIT := impl/pnr/$(TOP).fs

RTL := $(LEGACY_RTL_DIR)/mackerel_f.v $(LEGACY_RTL_DIR)/boot_signal.v \
	$(LEGACY_RTL_DIR)/bus_watchdog.v $(LEGACY_RTL_DIR)/irq_encoder.v \
	$(LEGACY_RTL_DIR)/sdram_cache.v $(LEGACY_RTL_DIR)/sdram_controller.v \
	$(LEGACY_RTL_DIR)/spi.v $(LEGACY_RTL_DIR)/timer.v \
	$(LEGACY_RTL_DIR)/uart.v $(LEGACY_RTL_DIR)/ws2812.v
FX68K := $(CORE)/fx68k.sv $(CORE)/fx68kAlu.sv $(CORE)/uaddrPla.sv
UART_RTL := $(wildcard $(UART)/*.v)
INPUTS := $(RTL) $(FX68K) $(UART_RTL) $(SDRAM)/sdram.v \
	$(SPI)/tiny_spi.v $(FPGA_DIR)/pll.v $(FPGA_DIR)/mackerel_f.cst \
	$(FPGA_DIR)/mackerel_f.sdc $(FPGA_DIR)/build.tcl \
	microrom.mem nanorom.mem rom.hex
FIRMWARE_SOURCES := $(wildcard firmware/*.c firmware/*.h firmware/*.s firmware/*.ld) \
	firmware/Makefile
LOCAL_M68K_CROSS := $(abspath tools/toolchains/m68k-mackerel-elf/bin/m68k-mackerel-elf-)
M68K_CROSS ?= $(if $(wildcard $(LOCAL_M68K_CROSS)gcc),$(LOCAL_M68K_CROSS),m68k-mackerel-elf-)
MX_FIRMWARE_BYTE_HEX := build/mx68k_bootloader.byte.hex

.PHONY: all fpga firmware sim sim-run sim-test timer-test cache-test mx-test \
	mx-firmware-probe mx-sim mx-run mx-sim-smoke mx-linux-smoke prog flash clean

all: sim-test mx-test

fpga: $(BIT)

$(BIT): $(INPUTS)
	$(GW) $(FPGA_DIR)/build.tcl

firmware: rom.hex

firmware/bootloader.hex: $(FIRMWARE_SOURCES)
	$(MAKE) -C firmware bootloader.hex

rom.hex: firmware/bootloader.hex
	cp $< $@

microrom.mem: $(CORE)/microrom.mem
	cp $< $@

nanorom.mem: $(CORE)/nanorom.mem
	cp $< $@

sim: microrom.mem nanorom.mem
	$(MAKE) -C sim

sim-run: sim
	$(MAKE) -C sim run ROM="$(ROM)" IMAGE="$(IMAGE)" SIM_ARGS="$(SIM_ARGS)"

sim-test: sim
	$(MAKE) -C sim test

timer-test:
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -o build/timer_tb.vvp $(LEGACY_RTL_DIR)/timer.v sim/timer_tb.v
	$(VVP) build/timer_tb.vvp

cache-test:
	mkdir -p build
	$(IVERILOG) -g2012 -o build/sdram_cache_tb.vvp $(LEGACY_RTL_DIR)/sdram_cache.v sim/sdram_cache_tb.v
	$(VVP) build/sdram_cache_tb.vvp

mx-test:
	$(MAKE) -C sim/mx68k test

firmware/bootloader.bin: $(FIRMWARE_SOURCES)
	$(MAKE) -C firmware CROSS=$(M68K_CROSS) bootloader.bin

$(MX_FIRMWARE_BYTE_HEX): firmware/bootloader.bin scripts/bin_to_byte_hex.py
	mkdir -p build
	python3 scripts/bin_to_byte_hex.py $< $@

mx-firmware-probe: $(MX_FIRMWARE_BYTE_HEX)
	$(MAKE) -C sim/mx68k firmware-probe FIRMWARE_HEX=$(abspath $(MX_FIRMWARE_BYTE_HEX))

mx-sim:
	$(MAKE) -C sim/mx68k firmware-sim

mx-run: $(MX_FIRMWARE_BYTE_HEX)
	$(MAKE) -C sim/mx68k firmware-run \
		FIRMWARE_HEX=$(abspath $(MX_FIRMWARE_BYTE_HEX)) \
		SD_IMAGE="$(if $(SD_IMAGE),$(abspath $(SD_IMAGE)))" \
		SD_WRITABLE="$(SD_WRITABLE)" \
		SIM_ARGS="$(if $(IMAGE),--image $(abspath $(IMAGE))) $(MX_SIM_ARGS)"

mx-sim-smoke: $(MX_FIRMWARE_BYTE_HEX)
	$(MAKE) -C sim/mx68k firmware-smoke \
		FIRMWARE_HEX=$(abspath $(MX_FIRMWARE_BYTE_HEX))

mx-linux-smoke: $(MX_FIRMWARE_BYTE_HEX)
	test -n "$(IMAGE)"
	$(MAKE) -C sim/mx68k firmware-linux-smoke \
		FIRMWARE_HEX=$(abspath $(MX_FIRMWARE_BYTE_HEX)) \
		IMAGE=$(abspath $(IMAGE)) \
		PLATFORM="$(if $(PLATFORM),$(PLATFORM),mackerel-f)" \
		TIME_SCALE="$(if $(TIME_SCALE),$(TIME_SCALE),1)" \
		MAX_CYCLES="$(if $(MAX_CYCLES),$(MAX_CYCLES),100000000)" \
		SD_IMAGE="$(if $(SD_IMAGE),$(abspath $(SD_IMAGE)))" \
		SD_WRITABLE="$(SD_WRITABLE)" \
		ROM="$(if $(ROM),$(abspath $(ROM)))" \
		EXPECT="$(EXPECT)"

prog: $(BIT)
	$(LOADER) -b tangnano20k $(BIT)

flash: $(BIT)
	$(LOADER) -b tangnano20k -f $(BIT)

clean:
	$(MAKE) -C sim clean
	$(MAKE) -C sim/mx68k clean
	$(MAKE) -C firmware clean
	$(RM) -r build impl microrom.mem nanorom.mem rom.hex timer.vcd
