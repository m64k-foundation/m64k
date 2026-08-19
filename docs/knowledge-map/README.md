# Mackerel 68000 knowledge map

This directory is the technical index for evolving the current MC68000 SoC into
a new, architecturally compatible M68040-class processor and, later, a
multiprocessor SoC. It describes the code as it exists on 2026-08-18. Statements
labelled **fact** come directly from the repository or Motorola/NXP manuals;
statements labelled **assessment** are engineering conclusions.

## Read this first

1. [code-index.md](code-index.md) maps every source group and its ownership.
2. [fx68k-core.md](fx68k-core.md) explains the current CPU down to its
   microcode, datapath, ALU, exceptions and bus.
3. [current-soc.md](current-soc.md) maps the FPGA top, memory, peripherals,
   interrupts and simulation.
4. [software-stack.md](software-stack.md) maps reset, firmware, loaders,
   toolchains and the current NOMMU assumptions.
5. [m68040-roadmap.md](m68040-roadmap.md) defines the architectural gap,
   recommended target profiles and implementation order.
6. [isa-extensions.md](isa-extensions.md) maps custom opcodes, binutils, GCC,
   ABI and operating-system work.
7. [verification.md](verification.md) defines the evidence required before a
   feature can be called implemented.

## Current system in one diagram

```text
27 MHz input
    |
    v
Gowin PLL -> 75.6 MHz SoC clock -> alternating enables -> 37.8 MHz fx68k
                                      |
                                      v
                              MC68000 bus, 24/16 bit
                                      |
        +-----------+-----------------+-------------------------+
        |           |                 |                         |
   boot ROM      BSRAM          read cache -> SDRAM       8-bit MMIO
   48 KiB        14 KiB          2 KiB, 4-byte lines       upper lane
                                                            |
                                     +------+------+--------+----+
                                     |      |      |        |
                                   UART   timer   SPI x2   GPIO/INTC/LED
```

The simulation keeps the real `fx68k`, timer, interrupt encoder, boot-shadow
logic and watchdog. It replaces the physical SDRAM, PLL, serial waveform and
most peripherals with behavioural models.

## Baseline facts

- The only CPU RTL in the repository is `fx68k`, a microcoded MC68000 core.
- It exposes a 24-bit address space, a 16-bit big-endian data bus and classic
  asynchronous 68000 bus control.
- It is not a partial ALU exercise: the core structurally covers the classic
  MC68000 instruction set, addressing modes, exceptions and bus protocol.
- No 68010/020/030/040 CPU, MMU, FPU, symbolic microcode, cache-coherence
  protocol or SMP fabric exists in the tree.
- The current system is single-core and single-master in normal operation.
- Firmware and Linux toolchain profiles target `-m68000`, soft-float and NOMMU.
- The current Linux image convention is a flat image loaded at physical
  address `0x000400`.

## Scale

The cleaned tree contains roughly 19,500 text lines. The largest blocks are
external IP: `fx68k`, the generated opcode PLA and the OpenCores UART. The SoC's
own RTL is comparatively small. This means the hard part of an M68040 target is
not wiring more peripherals; it is designing and verifying a new processor
memory/execution architecture.

## Architectural boundary

There are two materially different goals:

1. **M68040 architectural compatibility**: software-visible registers,
   instructions, faults, MMU, caches and FPU behave as required, while the FPGA
   pin-level memory bus may use a project-specific adapter.
2. **MC68040 pin/cycle compatibility**: external synchronous bus cycles, burst
   rules, snooping and timing also reproduce the physical Motorola part.

The recommended project goal is (1). It is already a new processor project;
goal (2) adds a large, mostly unnecessary verification burden for this SoC.

## Recommended preservation rule

Keep `third_party/fx68k` frozen as the known MC68000 reference. Do not evolve
the opaque `.mem` files by hand. A new modular core can reuse verified ideas
and compare its 68000 mode against fx68k without turning the working baseline
into an unreviewable mixture of CPU generations.

## Primary architecture references

- Motorola/Freescale, *M68040 User's Manual*, revision 1:
  <https://www.nxp.com/docs/en/reference-manual/MC68040UM.pdf>
- Motorola/Freescale, *M68000 Family Programmer's Reference Manual*:
  <https://www.nxp.com/docs/en/reference-manual/M68000PRM.pdf>

These manuals are specifications, not test suites. The verification plan must
turn their software-visible requirements into executable checks.
