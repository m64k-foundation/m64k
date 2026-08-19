CROSS ?= m68k-mackerel-elf-
CC := $(CROSS)gcc
AS := $(CROSS)as
OBJCOPY := $(CROSS)objcopy

CFLAGS := -m68000 -O2 -g -Wall -msoft-float -fomit-frame-pointer
AFLAGS := -m68000
# This toolchain has separate m68000 and softfp multilibs, but no combined
# m68000/softfp directory.  Passing both options while linking falls back to
# the default (68020) libc and leaks post-68000 opcodes into M00 firmware.
# C objects remain soft-float; select the genuine m68000 libc at link time.
LDFLAGS := -m68000 -Wl,--build-id=none -nostartfiles

ROM_LINKER := linker_rom.ld
RAM_LINKER := linker_ram.ld
VECTORS := vectors.s

COMMON_ROM := $(VECTORS) start.o newlib_init.o syscalls.o mackerel.o \
	console.o uart_16550.o term.o
COMMON_RAM := start_ram.o newlib_init.o syscalls.o mackerel.o \
	console.o uart_16550.o term.o
STORAGE := sd_spi.o spi_tiny.o fat16.o w5500.o netboot.o

BINS := bootloader.bin libctest.bin uarttest.bin irqtest.bin spitest.bin \
	sdtest.bin sdread.bin

.PHONY: all clean
.SECONDARY: %.elf %.bin

all: $(BINS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.s
	$(AS) $(AFLAGS) $< -o $@

%.bin: %.elf
	$(OBJCOPY) $< -O binary $@

# One big-endian 16-bit word per line for Verilog $readmemh.
%.hex: %.bin
	hexdump -v -e '2/1 "%02x" "\n"' $< > $@

bootloader.elf: $(COMMON_ROM) bootloader.o $(STORAGE) ymodem.o
	$(CC) $(LDFLAGS) -T $(ROM_LINKER) $^ -o $@ -lc -lgcc

libctest.elf: $(COMMON_RAM) libctest.o
	$(CC) $(LDFLAGS) -T $(RAM_LINKER) $^ -o $@ -lc -lgcc

uarttest.elf: $(COMMON_RAM) uarttest.o
	$(CC) $(LDFLAGS) -T $(RAM_LINKER) $^ -o $@ -lc -lgcc

irqtest.elf: $(COMMON_RAM) irqtest.o
	$(CC) $(LDFLAGS) -T $(RAM_LINKER) $^ -o $@ -lc -lgcc

spitest.elf: $(COMMON_RAM) spitest.o spi_tiny.o
	$(CC) $(LDFLAGS) -T $(RAM_LINKER) $^ -o $@ -lc -lgcc

sdtest.elf: $(COMMON_RAM) sdtest.o sd_spi.o spi_tiny.o
	$(CC) $(LDFLAGS) -T $(RAM_LINKER) $^ -o $@ -lc -lgcc

sdread.elf: $(COMMON_RAM) sdread.o sd_spi.o spi_tiny.o fat16.o
	$(CC) $(LDFLAGS) -T $(RAM_LINKER) $^ -o $@ -lc -lgcc

leds.elf: $(VECTORS) leds.o
	$(CC) $(LDFLAGS) -T $(ROM_LINKER) $^ -o $@ -lgcc

sdramtest.elf: $(VECTORS) sdramtest.o
	$(CC) $(LDFLAGS) -T $(ROM_LINKER) $^ -o $@ -lgcc

clean:
	$(RM) *.o *.elf *.bin *.hex
