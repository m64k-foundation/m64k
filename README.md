# MX68K

MX68K is a new board-neutral M68k architecture, CPU and system-on-chip RTL
implementation, evolving through M00/M10/M20 toward an M68040-compatible base.
The inherited cycle-accurate `fx68k` Motorola 68000 SoC remains isolated as a
simulation/differential reference. The new FPGA platform will be selected from
measured timing, capacity and external-memory results.

## Layout

```text
rtl/mx68k/              new board-neutral MX68K RTL
rtl/legacy/mackerel-f/  inherited Tang SoC RTL kept for regression
fpga/tang-nano-20k/     PLL, constraints and Gowin build script
sim/                    Verilator model, terminal harness and RTL tests
firmware/               68000 boot ROM and bare-metal diagnostics
third_party/            vendored FPGA IP, including fx68k
toolchain/              crosstool-NG configurations and local patches
scripts/                helper utilities
docs/knowledge-map/     CPU, SoC, software and M68040 evolution map
docs/mx68k/             normative MX68K architecture and implementation plan
```

The [knowledge map](docs/knowledge-map/README.md) is the engineering source of
truth for the current design, M68040 roadmap, future ISA extensions and
verification requirements.

The normative [MX68K specification](docs/mx68k/README.md) defines the new
architecture. The inherited Mackerel-F/fx68k system remains a compatibility and
differential-testing baseline while MX68K is implemented separately.

## Simulate

Verilator 5 or newer is required.

```sh
make sim-test
make mx-test
make sim-run ROM=rom.hex
make sim-run IMAGE=/path/to/image.bin SIM_ARGS="--skip-sd-wait"
```

`sim-test` executes real 68000 instructions on the fx68k RTL and checks word and
independent upper/lower byte accesses to behavioural RAM.

`mx-test` verifies the new 32-bit/128-bit MX68K fabric, request/response
backpressure, big-endian legacy bridge, architectural flags/SR/vector helpers,
generated opcode-table freshness, variable-length fetch/decode and precise
fault propagation. It also executes the fx68k through the new fabric and tests
the native M00 core's reset, stack, control-flow and precise-commit paths. The
directed interrupt tests cover SR masking, autovectors, the level-7 transition,
STOP wake-up, exception stacking/RTE and the simulated UART/timer sources.
Additional architectural tests cover CHK.W signed bounds and effective-address
effects, T1 instruction trace, exact stacked PCs, trap/trace/IRQ precedence and
the seven-word M00 bus/address-error frame for data and instruction accesses.
It also checks two-beat big-endian long accesses crossing the internal 16-byte
line, including RMW, JSR/RTS and a fault on the second beat. NEGX coverage
checks byte/word/long results, X-as-borrow and cumulative Z for multiprecision
arithmetic.
`MOVE <ea>,SR` coverage includes immediate and memory sources, full-word SR
replacement, M00 sanitization and the precise privilege exception after a
supervisor-to-user transition.
Static and register-indexed `BTST/BCHG/BCLR/BSET` now cover the distinct
register-long/modulo-32 and memory-byte/modulo-8 rules, preserve X/N/V/C and
derive Z from the original bit before any read-modify-write.

## Firmware

The ROM is built with the `m68k-mackerel-elf-` bare-metal toolchain:

```sh
make firmware
```

This produces `firmware/bootloader.hex` and copies it to `rom.hex`, ready for
simulation or FPGA synthesis.

The native M00 firmware probe builds the ROM, executes it through the MX68K
core, waits for the interactive `> ` prompt, injects `help` through the
simulated 16550 RX path, checks the complete response and requires a second
line-start prompt:

```sh
make mx-firmware-probe M68K_CROSS=/path/to/m68k-mackerel-elf-
```

The probe uses an 8 MiB populated-RAM board profile inside the architectural
32-bit address space and a fast no-card SPI model. UART TX is printed directly
to the terminal and scripted RX exercises the real bootloader parser and
newlib output paths. The fabric itself remains 4-GiB capable; populated DDR
capacity is a platform parameter, not an M00 ISA limit.

### Interactive terminal

Build the native M00 Verilator executable once, then compile and run the real
firmware with its UART connected to the current terminal:

```sh
make mx-sim
make mx-run
make mx-run IMAGE=/path/to/image.bin
make mx-run IMAGE=/path/to/image.bin SD_IMAGE=/path/to/sd-card.img
make mx-run SD_IMAGE=/path/to/sd-card.img SD_WRITABLE=1
```

The build automatically uses
`tools/toolchains/m68k-mackerel-elf/bin/m68k-mackerel-elf-` when installed
there, then falls back to `m68k-mackerel-elf-` from `PATH`. An explicit
`M68K_CROSS=/path/to/prefix-` still overrides both choices.

Input is forwarded character by character to the simulated 16550. Commands
such as `help` and `info` execute on the RTL CPU; press Ctrl-C to stop. The
simulator restores the terminal mode on normal exit and on Ctrl-C/SIGTERM.
Passing `IMAGE` preloads a flat Linux/bare-metal image into coherent simulated
RAM at `0x400`; the harness then issues the bootloader's real `run` command.
Passing `SD_IMAGE` attaches a raw, sector-aligned disk image as an SDHC card on
the Mackerel-F SPI0 slot.  Without it the bus behaves like an empty socket.  It
is read-only by default; `SD_WRITABLE=1` explicitly enables CMD24/CMD25 and
allows the guest to modify the file.  Use a disposable copy for writable runs.
The transaction-level model retains the SD command/response, data-token and CRC
contract while omitting physical SCLK edges for simulation speed.
Instruction fetches and data accesses share the same bytes through independent
ports, so copied or patched code remains coherent in this functional model.
`MX_SIM_ARGS` passes diagnostic options to the executable:

```sh
make mx-run MX_SIM_ARGS="--bus-trace --max-cycles 5000000"
```

For a noninteractive end-to-end check, the smoke target waits for the first
prompt, injects `info` through UART RX, requires the `DRAM:` response and waits
for the next prompt:

```sh
make mx-sim-smoke
```

Run `build/mx68k_firmware_sim/Vmx68k_firmware_sim_top --help` for the direct
executable interface, including scripted commands and retirement tracing.

### Linux Mackerel-F

Flat Mackerel-F kernel images are preloaded at `0x400` and entered through the
real bootloader command.  Mackerel-F is the default platform; the historical
Mackerel-08 XR68C681 overlay must be requested explicitly.

#### Booting the official SD image

The recommended end-to-end input is the Mackerel-F SD image from the official
[mackerel-linux v7.1.0 release](https://github.com/crmaykish/mackerel-linux/releases/tag/mackerel-linux-v7.1.0-2026-07-12).
Download and unpack it outside this repository:

```sh
curl -LO https://github.com/crmaykish/mackerel-linux/releases/download/mackerel-linux-v7.1.0-2026-07-12/mackerel-f-sd-v7.1.0-2026-07-12.img.gz
printf '%s  %s\n' \
  5c1a2717cb884623eb0f29ea5ca531ef856f0d82eed5f04d8ef5e856eb36c44f \
  mackerel-f-sd-v7.1.0-2026-07-12.img.gz | sha256sum -c -
gzip -dk mackerel-f-sd-v7.1.0-2026-07-12.img.gz
```

For a safe read-only run, attach the unpacked image directly:

```sh
make mx-run \
  SD_IMAGE=/path/to/mackerel-f-sd-v7.1.0-2026-07-12.img
```

This exercises the real boot path: the firmware initializes the simulated
SDHC card, reads `IMAGE.BIN` from its FAT partition into RAM at `0x400`, and
jumps to Linux.  The Linux MMC driver then sees the same card and its
partitions.  The simulator never modifies the image unless explicitly asked.

Linux needs a writable block device to mount and update the ext4 root
filesystem.  Always make a disposable copy before enabling writes:

```sh
cp /path/to/mackerel-f-sd-v7.1.0-2026-07-12.img /tmp/mx68k-sd.img

make mx-run \
  SD_IMAGE=/tmp/mx68k-sd.img \
  SD_WRITABLE=1 \
  MX_SIM_ARGS="--time-scale 10"
```

`SD_WRITABLE=1` enables SD CMD24/CMD25 and modifies the file named by
`SD_IMAGE`; it must not be used on the only copy of an image.  The
`--time-scale 10` option accelerates guest time only after the kernel reaches
its SD-card wait, leaving CPU/timer calibration at the normal rate.  Values
substantially above 10 can create an unrealistic timer-interrupt load and make
the M00 appear slower rather than faster.

Useful diagnostics can be added without changing the Makefile:

```sh
make mx-run \
  SD_IMAGE=/tmp/mx68k-sd.img \
  SD_WRITABLE=1 \
  MX_SIM_ARGS="--time-scale 10 --sd-trace --max-cycles 1000000000"
```

Press Ctrl-C to stop the simulator safely.  A healthy boot should include the
firmware finding `IMAGE.BIN`, loading it, jumping to `0x400`, the Linux version
banner, and MMC messages ending in `mmcblk0: p1 p2`.  RTL simulation is much
slower than wall-clock hardware, so filesystem checks and the first writable
ext4 mount may remain quiet for a significant time after partition discovery.

#### Kernel preload and smoke tests

For CPU/platform development, a flat kernel can instead be preloaded directly
without reproducing its transfer from the SD card:

##### uClinux 4.4 Mackerel-08 regression

The current M00 CPU regression uses the historical serial-load image named
`mackerel-08-uclinux-v4.4-serial.bin`.  This image contains its root filesystem
as ROMFS, so it reaches BusyBox without attaching or mounting an SD card.  Use
the Mackerel-08 platform explicitly because its XR68C681 UART/timer map differs
from Mackerel-F.

The image is published in the upstream Mackerel-08 v1.1 artifacts. Keep it
outside this repository (for example in `/tmp` or an external image cache):

```sh
curl -fL \
  https://raw.githubusercontent.com/crmaykish/mackerel-68k/master/releases/mackerel-08/v1.1/mackerel-08-uclinux-v4.4-serial.bin \
  -o /tmp/mackerel-08-uclinux-v4.4-serial.bin
echo '156dabfd6f9014a0179f43fe83dd1cd7d46d9cb0fb85a43ab7e9caac7d7e3cad  /tmp/mackerel-08-uclinux-v4.4-serial.bin' | sha256sum -c -
```

Run the automated boot-to-shell check with:

```sh
make mx-linux-smoke \
  IMAGE=/path/to/mackerel-08-uclinux-v4.4-serial.bin \
  PLATFORM=mackerel-08 \
  EXPECT='uClinux mackerel-08' \
  MAX_CYCLES=300000000
```

The runner preloads the image at `0x400`, lets the real bootloader issue
`run 400`, waits for the BusyBox `# ` prompt, sends `uname -a` through the
simulated XR68C681 receive FIFO and requires the expected response.  A passing
run currently ends like this:

```text
# uname -a
uClinux mackerel-08 4.4.0-uc0 ... m68k GNU/Linux
#
[mx68k-sim] 41955425 cycles ... (shell command completed)
```

For an interactive terminal instead:

```sh
make mx-run \
  IMAGE=/path/to/mackerel-08-uclinux-v4.4-serial.bin \
  MX_SIM_ARGS='--platform mackerel-08 --max-cycles 300000000'
```

Wait for `# ` and type commands normally, for example `uname -a`, `free` or
`cat /proc/cpuinfo`. Press Ctrl-C to terminate the simulator. No `SD_IMAGE` is
needed for this Linux 4.4 image.

##### Other flat kernels

```sh
make mx-linux-smoke \
  IMAGE=/path/to/mackerel-f-kernel.bin \
  SD_IMAGE=/path/to/sd-card.img \
  EXPECT='Linux version 7.1.0' \
  TIME_SCALE=10 \
  MAX_CYCLES=1000000000

make mx-run IMAGE=/path/to/mackerel-f-kernel.bin
make mx-run IMAGE=/path/to/mackerel-08-kernel.bin \
  MX_SIM_ARGS='--platform mackerel-08'
```

`TIME_SCALE` is an optional smoke-test acceleration equivalent to the
interactive `--time-scale` argument.  Normal interactive execution uses scale
1.  This option is a simulation convenience, not evidence of cycle-accurate
timer conformance.

## FPGA

The hardware build requires Gowin EDA. With the third-party RTL already present:

```sh
make fpga
make prog       # volatile SRAM configuration
make flash      # persistent SPI-flash configuration
```

## Memory map

| Range | Function |
|---|---|
| `0x000000-0x7FFFFF` | 8 MiB SDRAM |
| `0xFF0000-0xFFBFFF` | 48 KiB boot ROM |
| `0xFFC000-0xFFF7FF` | 14 KiB block RAM |
| `0xFFF800-0xFFFFFF` | Eight 256-byte peripheral slots |

The peripheral slots contain GPIO, 16550 UART, timer, two SPI controllers,
interrupt mask and WS2812 controller.

## Licensing

Original Mackerel code is MIT licensed. The vendored fx68k core is GPLv3; each
third-party component retains its own copyright and license notices.
