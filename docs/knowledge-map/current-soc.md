# Current SoC architecture

## Synthesizable hierarchy

```text
mackerel_f
├── pll (Gowin rPLL)
├── fx68k
├── boot_signal
├── uart -> OpenCores uart_top/registers/RX/TX/FIFOs
├── timer
├── ws2812
├── spi x2 -> OpenCores tiny_spi
├── irq_encoder
├── sdram_cache
├── sdram_controller -> Tang Nano SDRAM core
└── bus_watchdog
```

The top is `rtl/legacy/mackerel-f/mackerel_f.v`. There is no internal
interconnect abstraction:
the CPU's live pins directly drive decode, memory and peripherals.

## Clock and reset

- `clk_27` enters a Gowin PLL.
- The PLL generates a 75.6 MHz logic clock and a phase-related SDRAM clock.
- Alternating `enPhi1` and `enPhi2` pulses make the fx68k nominally 37.8 MHz.
- CPU reset is held for 8,388,608 SoC clocks, approximately 111 ms.
- SDRAM/cache leave reset at PLL lock, before the CPU/peripherals.
- SDRAM `init_done` is produced but ignored.
- The CPU's `oRESETn`, `oHALTEDn` and bus grant are discarded. `HALTn`, `BRn`
  and `BGACKn` are tied inactive.
- GPIO and the one-byte interrupt mask rely on FPGA initial values rather than
  the CPU reset path.

The timing constraints only declare the input and SoC clocks. They do not
capture the generated-clock relationship to the SDRAM phase, fx68k multicycle
microcode paths, asynchronous inputs or I/O delays.

## CPU bus contract

| Property | Current value |
|---|---|
| Address | `ADDR_BUS[23:1]`, 24-bit byte address after appending zero |
| Data | 16-bit, big-endian |
| Termination | DTACK, VPA or watchdog-generated BERR |
| Address spaces | FC is only decoded for CPU-space/IACK |
| Arbitration | fx68k logic exists, but top-level disables external masters |

For a byte at an even address, UDS selects data bits `[15:8]`. For the next
odd byte, LDS selects `[7:0]`. Eight-bit peripherals live only on the upper
lane and should be accessed as bytes at even offsets.

ROM, BSRAM, GPIO and the interrupt-mask register get combinational zero-wait
DTACK. ROM/BSRAM data are nevertheless registered. Correctness therefore
depends on shared-clock timing and the fx68k bus waveform; it is not a generic
asynchronous slave contract.

The watchdog waits 4096 SoC clocks, about 54 microseconds, before BERR. It has
no fault address/status register and no recovery policy for double faults.

## Boot shadow

While `BOOT=0`, ROM responds to every CPU address and all other chip selects
are suppressed. `boot_signal` counts four rising edges of AS, corresponding to
the four completed word reads for SSP and PC. Then low memory becomes SDRAM
and ROM remains visible only at `0xFF0000`.

The detector does not validate address, read/write or function code. A future
prefetcher, retry, wider fetch or different reset sequence must replace this
implicit four-transaction rule with an explicit reset-vector mechanism.

## Physical memory map

| Range | Function |
|---|---|
| `000000-7FFFFF` | 8 MiB SDRAM |
| `800000-FEFFFF` | Unmapped, eventually BERR |
| `FF0000-FFBFFF` | 48 KiB ROM |
| `FFC000-FFF7FF` | 14 KiB BSRAM |
| `FFF800-FFF8FF` | GPIO |
| `FFF900-FFF9FF` | UART |
| `FFFA00-FFFAFF` | Timer |
| `FFFB00-FFFBFF` | SD SPI |
| `FFFC00-FFFCFF` | NIC SPI |
| `FFFD00-FFFDFF` | One-byte NIC interrupt mask |
| `FFFE00-FFFEFF` | WS2812 |
| `FFFF00-FFFFFF` | Reserved/unmapped |

The current 24-bit decoder is the first hard boundary that must go for a
32-bit processor. A future physical map must reserve part of the 4 GiB space
for boot ROM, MMIO, interrupt controllers and firmware; 4 GiB is the complete
68040 physical address space, not an amount of usable DRAM in addition to MMIO.

## Cache and SDRAM

The current SDRAM cache is:

- unified;
- direct mapped;
- 512 lines of four bytes, 2 KiB total;
- read-allocate;
- write-through/no-write-allocate;
- invalidate-on-write;
- without dirty bits, control registers, snooping, parity or ECC.

Its coherence argument explicitly assumes one writer and no DMA. This cache
cannot be reused as an M68040 I/D cache or an SMP cache.

The physical controller is byte-addressable, non-bursting and auto-precharges
every operation. A 68000 word write becomes two SDRAM byte writes. Refresh is
requested approximately every 4.5 microseconds, but only one pending refresh
is remembered.

Critical timing issue: the adapter instantiates the upstream controller at
75.6 MHz while that controller documents its default `T_RP`, `T_RCD` and
related parameters for at most 66.7 MHz. This target must either run slower,
use recomputed timing parameters validated against the memory datasheet, or
replace the controller.

## Peripherals and interrupts

- GPIO bits 0–5 drive active-low LEDs; bits 6–7 are SD/NIC chip selects.
- UART is a full 16550 behind a 68000-to-Wishbone FSM. A global preprocessor
  define selects its 8-bit build, making source compilation order significant.
- Timer offers 10/25/50/100 Hz, level-sensitive IRQ and explicit ACK.
- Two tiny_spi instances use four-byte register stride. Their IRQ outputs are
  unused, and word writes have ambiguous lane selection; use even byte writes.
- WS2812 transmits GRB after writing blue. A trigger while busy is dropped.
- `INTC` is only one mask bit for NIC, not an interrupt controller.

IRQ levels are fixed:

| Source | Level | Vector |
|---|---:|---:|
| Timer | 6 | autovector 30 |
| UART | 5 | autovector 29 |
| NIC | 4 | autovector 28 |

All CPU-space cycles are treated as IACK and terminated with VPA, so all
interrupts are autovectored. The asynchronous NIC interrupt is not synchronized.

## Simulation contract

The Verilator model keeps the real fx68k, boot shadow, timer, IRQ encoder and
watchdog. It substitutes byte-array RAM/BSRAM, a minimal register-level UART,
immediate memory DTACK and idle SPI stubs. It does not instantiate the FPGA
top, PLL, real 16550, cache or SDRAM controller.

Useful harness features are direct boot at `0x400`, interactive UART, bus
trace, cycle limit, expected-output assertion and optional VCD. The
`--skip-sd-wait` mode edits guest bytes in RAM and must never count as faithful
hardware behaviour.

Existing automated evidence covers a short 68000 program and byte lanes,
timer behaviour and basic cache fill/hit/invalidation. It does not cover the
integrated FPGA top, real boot ROM, watchdog/BERR, IACK, real UART/SPI, SDRAM
PHY, reset/relock or bus arbitration.

## Why this topology blocks M68040 and SMP

1. Logical and physical addresses are the same 24-bit wires.
2. There is no request/response boundary at which an MMU can stall, walk and
   restart an access.
3. Instruction fetches and data accesses share one port and one cache.
4. Faults do not carry the information needed for precise restart.
5. The decoder and mux accept exactly one live master.
6. Cache coherence is based on the absence of another writer.
7. There is no IPI, CPU ID, per-core timer, boot mailbox or interrupt affinity.

The first structural SoC project should therefore be a typed internal memory
protocol plus an arbiter/interconnect. One adapter can keep fx68k working while
a new core, caches, MMU and multiple masters are developed independently.
