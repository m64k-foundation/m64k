# Mackerel 68000 SoC Verilator simulation

This simulation keeps the `fx68k` RTL and the Mackerel-F CPU-visible memory map.
The physical SDRAM, FPGA PLL and UART wire timing are replaced with behavioural
models so a Linux boot does not spend time simulating electrical interfaces.

Build from the repository root with `make sim`. To run a real boot ROM:

```sh
make sim-run ROM=rom.hex
```

The UART appears directly on the terminal. Input is nonblocking and is forwarded
to the emulated 16550 receive register. With a Linux `image.bin`, the fastest path
is a direct reset-equivalent boot: the image is loaded at the board's real load
address (`0x400`), SSP is set to the top of the 8 MB RAM, and execution begins at
`0x400` while still using the `fx68k` RTL:

```sh
./build/verilator/Vmackerel_f_sim /path/to/image.bin
```

Because no SD card is modelled, the stock rootfs waits about 130 logical seconds
for `/dev/mmcblk0`. Add `--skip-sd-wait` to patch only those sleeps in the loaded
RAM copy of its init script; the `image.bin` file itself is not modified.

Useful options are `--max-cycles N`, `--bus-trace`, `--trace[=file.vcd]`,
`--rom FILE`, `--direct`, and `--no-stdin`. VCD tracing is compiled in but disabled
unless requested.

The simulation timer defaults to the hardware rate (`TIMER_CLK_HZ=75600000`).
It can be overridden at build time, but large accelerations can spend more host
time servicing tick interrupts than they save. `--skip-sd-wait` is the preferred
way to avoid missing-hardware timeouts.

`rom.hex` is one big-endian 16-bit word per line, as produced by
`make bootloader.hex` in `firmware/`.

`make test` runs 68000 code which writes a word, overwrites its upper and lower
bytes independently, reads the word back, and prints `PASS` through the UART.
