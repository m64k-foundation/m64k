# Code index

This index assigns a purpose and change policy to every source group. Line
numbers elsewhere in the knowledge map refer to the 2026-08-18 tree.

## Root

| Path | Role |
|---|---|
| `README.md` | User entry point, build commands and physical map |
| `Makefile` | Orchestrates firmware, Verilator, unit tests and Gowin |
| `.gitignore` | Central generated-file policy |
| `LICENSE` | License for original project code |

## First-party RTL

| File | Module | Responsibility |
|---|---|---|
| `rtl/legacy/mackerel-f/mackerel_f.v` | `mackerel_f` | FPGA top, CPU wiring, decode, memory mux, IRQ and pins |
| `rtl/legacy/mackerel-f/boot_signal.v` | `boot_signal` | Ends reset-vector ROM shadow after four bus cycles |
| `rtl/legacy/mackerel-f/bus_watchdog.v` | `bus_watchdog` | Converts unterminated bus accesses into BERR |
| `rtl/legacy/mackerel-f/irq_encoder.v` | `irq_encoder` | Fixed-priority IRQ1–7 to active-low IPL encoding |
| `rtl/legacy/mackerel-f/sdram_cache.v` | `sdram_cache` | 2 KiB direct-mapped read cache, write-through |
| `rtl/legacy/mackerel-f/sdram_controller.v` | `sdram_controller` | 68000-to-byte-SDRAM adapter and refresh scheduler |
| `rtl/legacy/mackerel-f/uart.v` | `uart` | 68000 upper-byte lane to Wishbone UART bridge |
| `rtl/legacy/mackerel-f/spi.v` | `spi` | 68000 to Wishbone tiny_spi bridge |
| `rtl/legacy/mackerel-f/timer.v` | `timer` | 10/25/50/100 Hz level-sensitive tick source |
| `rtl/legacy/mackerel-f/ws2812.v` | `ws2812` | Single RGB LED serializer and holding registers |

Change policy: these are project-owned and may evolve, but CPU/interconnect
decoupling should occur before adding virtual memory or multiple masters.

## FPGA target

| File | Responsibility |
|---|---|
| `fpga/tang-nano-20k/build.tcl` | Complete Gowin source list and device selection |
| `fpga/tang-nano-20k/pll.v` | Gowin `rPLL`, 27 MHz to 75.6 MHz plus SDRAM phase |
| `fpga/tang-nano-20k/mackerel_f.cst` | Package pin constraints |
| `fpga/tang-nano-20k/mackerel_f.sdc` | Input and SoC clock constraints |

## Simulation and tests

| File | Responsibility |
|---|---|
| `sim/mackerel_f_sim.sv` | Behavioural SoC retaining the real fx68k/timer/IRQ/watchdog |
| `sim/main.cpp` | Verilator clock, terminal UART, image loading, VCD and bus trace |
| `sim/ram_test.hex` | Direct-boot 68000 smoke test image |
| `sim/tb_fx68k.sv` | Small standalone CPU bus testbench |
| `sim/timer_tb.v` | Timer register/rate/IRQ testbench |
| `sim/sdram_cache_tb.v` | Cache fill/hit/write invalidation testbench |
| `sim/Makefile` | Verilator build and main smoke-test target |
| `sim/README.md` | Simulator CLI and behavioural-model contract |

## CPU core

| File | Responsibility |
|---|---|
| `third_party/fx68k/fx68k.sv` | CPU top, datapath, exceptions, sequencer and bus |
| `third_party/fx68k/fx68kAlu.sv` | Integer ALU, shifts, BCD and CCR generation |
| `third_party/fx68k/uaddrPla.sv` | Generated opcode/effective-address entry PLA |
| `third_party/fx68k/microrom.mem` | 1024 × 17-bit microstore image |
| `third_party/fx68k/nanorom.mem` | 336 × 68-bit nanostore image |
| `third_party/fx68k/README.md`, `fx68k.txt` | Upstream interface/timing notes |
| `third_party/fx68k/LICENSE` | GPLv3-or-later license |

Change policy: treat as a frozen reference until symbolic microcode sources,
generators and broad conformance tests exist.

## Other third-party RTL

| Group | Files and role |
|---|---|
| `third_party/uart16550/rtl/verilog/` | `uart_top`, Wishbone adapter, register bank, TX/RX, FIFOs, synchronizers, inferred RAM, defines and timescale |
| `third_party/tiny_spi/rtl/verilog/tiny_spi.v` | Small Wishbone SPI master |
| `third_party/sdram-tang-nano-20k/src/sdram.v` | Physical Tang Nano 20K SDRAM command engine |
| `third_party/README.md` | Pinned upstream revisions and licenses |

## Firmware startup and runtime

| File | Responsibility |
|---|---|
| `firmware/vectors.s` | Initial SSP and reset PC in the ROM vector image |
| `firmware/start.c` | ROM startup, exception table, data copy and C runtime |
| `firmware/start_ram.c` | Minimal startup for images already loaded in SDRAM |
| `firmware/linker_rom.ld` | ROM/BSRAM layout and bootloader symbols |
| `firmware/linker_ram.ld` | `0x400` SDRAM program layout |
| `firmware/newlib_init.c/.h` | BSS, reentrancy object, constructors and stdout |
| `firmware/syscalls.c` | Minimal newlib write/read/heap/file stubs |
| `firmware/mackerel.c/.h` | SoC constants, SR interrupt mask, vectors and utilities |
| `firmware/mem.h` | Volatile 8/16/32-bit MMIO accessors |
| `firmware/console.c/.h`, `uart.h` | Generic blocking console surface |
| `firmware/uart_16550.c/.h` | 16550 init, polling RX/TX and register map |
| `firmware/term.c/.h` | ANSI terminal helpers |

## Firmware loaders and devices

| File | Responsibility |
|---|---|
| `firmware/bootloader.c` | Monitor, autoboot, memory tools and image handoff |
| `firmware/ymodem.c/.h` | UART YMODEM receiver |
| `firmware/spi_tiny.c/.h` | tiny_spi programming and byte transfer |
| `firmware/sd_spi.c/.h` | Read-only SD SPI protocol |
| `firmware/fat16.c/.h` | MBR/FAT16 discovery and read-only file loading |
| `firmware/w5500.c/.h` | W5500 socket-0 TCP transport |
| `firmware/netboot.c/.h` | Length-prefixed `IMAGE.BIN` network loader |
| `firmware/ws2812.h` | RGB MMIO helper |

## Firmware diagnostics

| File | Coverage |
|---|---|
| `irqtest.c` | Timer/UART levels, autovectors and priority |
| `uarttest.c` | 16550, libc, allocation, sort/search and TX stress |
| `spitest.c` | tiny_spi status, transfer and GPIO CS |
| `sdtest.c` | SD initialization and card metadata |
| `sdread.c` | MBR, FAT16, image read and timer-assisted SPI sweep |
| `sdramtest.c` | Word patterns, address aliases and byte lanes |
| `leds.c` | Minimal UART and GPIO interaction |
| `libctest.c` | newlib and heap smoke test |

`firmware/Makefile` builds the bootloader and most diagnostics with
`-m68000 -msoft-float`. `leds` and `sdramtest` have explicit rules but are not
members of its default `BINS` list.

## Toolchain and scripts

| File | Responsibility |
|---|---|
| `toolchain/baremetal.defconfig` | crosstool-NG bare-metal/newlib profile |
| `toolchain/uclinux.config` | m68k 68000 NOMMU GCC/binutils/kernel-header profile |
| `toolchain/uclibc.config` | uClibc bFLT, no-MMU, no-threads profile |
| `toolchain/patches/gcc/...` | Strict-alignment correction for 68000 Linux target |
| `toolchain/patches/uClibc-ng/...` | Empty auxv for binfmt_flat startup |
| `scripts/fetch-cores.sh` | Fetches the recorded third-party revisions |
| `scripts/netboot_server.py` | Sends a length-prefixed image over TCP |

## Generated files that are not source

The root Makefile may produce `rom.hex`, `microrom.mem`, `nanorom.mem`,
`build/` and `impl/`. Firmware builds produce `.o`, `.elf`, `.bin` and `.hex`.
Simulation may produce VCD. These are deliberately ignored and must not become
the source of truth.
