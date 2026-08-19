VERILATOR ?= verilator
# Fedora's compiler launcher may point ccache outside the writable workspace.
export CCACHE_DISABLE := 1
FX68K := ../third_party/fx68k
RTL := ../rtl/legacy/mackerel-f
OBJDIR := ../build/verilator
TARGET := $(OBJDIR)/Vmackerel_f_sim
TIMER_CLK_HZ ?= 75600000

SOURCES := mackerel_f_sim.sv $(RTL)/timer.v $(RTL)/irq_encoder.v \
	$(RTL)/bus_watchdog.v $(RTL)/boot_signal.v \
	$(FX68K)/fx68k.sv $(FX68K)/fx68kAlu.sv \
	$(FX68K)/uaddrPla.sv main.cpp

VERILATOR_FLAGS := --cc --exe --build --timing --trace --top-module mackerel_f_sim \
	-Mdir $(OBJDIR) -I$(FX68K) -CFLAGS "-O3" \
	-GTIMER_CLK_HZ=$(TIMER_CLK_HZ) \
	-Wno-fatal -Wno-BLKANDNBLK --no-assert-case \
	-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	-Wno-VARHIDDEN -Wno-UNUSEDSIGNAL

.PHONY: all run test clean

all: $(TARGET)

../microrom.mem: $(FX68K)/microrom.mem
	cp $< $@

../nanorom.mem: $(FX68K)/nanorom.mem
	cp $< $@

$(TARGET): $(SOURCES) ../microrom.mem ../nanorom.mem
	mkdir -p $(OBJDIR)
	$(VERILATOR) $(VERILATOR_FLAGS) $(SOURCES)

run: $(TARGET)
	cd .. && build/verilator/Vmackerel_f_sim $(if $(ROM),--rom $(ROM),) $(if $(IMAGE),$(IMAGE),) $(SIM_ARGS)

test: $(TARGET)
	cd .. && build/verilator/Vmackerel_f_sim --no-stdin --max-cycles 2000 --expect PASS --hex-image sim/ram_test.hex

clean:
	$(RM) -r $(OBJDIR) ../mackerel-f.vcd
