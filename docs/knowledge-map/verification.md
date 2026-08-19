# Verification strategy

## Definition of implemented

A feature is implemented only when all applicable layers agree:

1. written architectural requirement;
2. executable reference semantics;
3. directed corner-case tests;
4. randomized/differential tests;
5. RTL assertions and coverage;
6. synthesis/timing results on a selected FPGA;
7. bare-metal architectural test;
8. operating-system test where relevant.

Compiling RTL, printing one UART string or booting once is evidence for a narrow
path, not processor conformance.

## Preserve two levels of tests

### Architectural tests

These ignore cycle count and compare retired state:

- PC, D/A registers and SR;
- memory writes and ordering;
- exception vector and complete stack frame;
- control/MMU/FPU registers;
- floating-point result/status;
- cache/TLB maintenance effects.

### Microarchitectural tests

These validate implementation details:

- pipeline stalls, bypasses and flushes;
- outstanding memory requests;
- cache replacement/writeback;
- ATC refill/table walks;
- DDR and CDC protocols;
- FPU latency/rounding pipeline;
- coherence and arbitration.

Architectural correctness must not depend on a particular pipeline timing.

## MC68000 baseline campaign

Before a new core is trusted, expand far beyond `ram_test.hex`:

- every legal opcode/form/addressing mode;
- byte/word/long at boundary addresses;
- X/N/Z/V/C truth tables and cumulative Z;
- MUL/DIV overflow, divide-by-zero and iteration cases;
- BCD and extend chains;
- MOVEM ordering, predecrement and masks;
- MOVEP byte lanes;
- privilege, STOP/RESET/trace and interrupt masking;
- all exception vectors and stack frames;
- bus/address error at every operand/fetch/write phase;
- IACK autovector/external/spurious;
- TAS atomic bus cycle, BR/BG/BGACK and wait states.

Add a retirement trace to fx68k and use it as one differential oracle for the
shared 68000 subset. The Motorola specification remains authoritative where an
implementation disagrees.

## Precise-exception campaign

Inject faults at every pipeline and memory stage. Check that:

- no younger instruction commits;
- partial architectural writes match the selected CPU generation;
- the stacked PC/status/frame are exact;
- restart repeats the correct access once;
- write buffers and cache fills do not leak invalid state;
- faults during exception processing follow halt/double-fault rules.

Build this before MMU and FPU, because both multiply the number of fault points.

## MMU campaign

- all page sizes, table levels and descriptor types;
- user/supervisor and read/write permissions;
- instruction versus data translation;
- transparent translations and function-code effects;
- accessed/modified/global/cache-mode attributes;
- ATC hit, miss, replacement and selective/global flush;
- table-walk bus errors and malformed descriptors;
- self-modifying page tables and required synchronization;
- task switches, ASID-equivalent policy if extended, and TLB shootdown;
- page fault followed by handler repair and exact restart.

## Cache campaign

- every byte/word/long alignment within and across 16-byte lines;
- all ways/sets and deterministic replacement checks;
- write-through/copyback, allocate modes and dirty eviction;
- instruction/data alias and self-modifying code;
- cache-control line/page/all operations;
- DMA or other-master snoops;
- simultaneous I/D miss and write-buffer pressure;
- MMU attribute changes and physical aliases;
- reset, invalidate and parity/ECC policy.

## FPU campaign

- all supported source/destination formats;
- normal, zero, subnormal, infinity, quiet/signalling NaN;
- four rounding modes and precision controls;
- invalid, divide-zero, overflow, underflow and inexact status/traps;
- signed zero and NaN propagation policy;
- conversion boundaries;
- FSAVE/FRESTORE and context-switch state;
- hardware subset versus software-emulated operations;
- random comparison against a carefully selected IEEE reference with explicit
  80-bit extended semantics.

Host `long double` must not be assumed to exactly model the target on every
platform.

## Formal properties

Good initial formal boundaries are small protocols, not the whole CPU:

- request accepted exactly once;
- each accepted request gets one response/fault;
- byte-enable/endian transformations;
- arbiter ownership and no two active drivers;
- FIFO/CDC safety;
- cache tag/data coherence;
- atomic sequence exclusion;
- interrupt priority encoding;
- boot mapping state transition.

Later, use bounded proofs for reorder/commit invariants and cache coherence.

## Compiler and ISA-extension campaign

Follow `isa-extensions.md`: exact encode/decode, semantic-model differential,
GCC selection and non-selection, ABI mixing, optimization-level runtime tests
and illegal-instruction fallback.

## SMP campaign

- cache-coherence state transitions and ownership invariants;
- TAS/CAS/CAS2 atomicity under adversarial interleavings;
- acquire/release/full barriers and litmus tests;
- IPI delivery, interrupt affinity and per-core timer;
- secondary reset/boot and hot-reset policy;
- TLB shootdown with concurrent page-table updates;
- forward progress under cache misses, writebacks and interrupts;
- long parallel stress with randomized memory latency.

## Continuous build matrix

At minimum:

| Layer | Jobs |
|---|---|
| Lint | Verilator plus project-owned warnings as errors |
| Unit RTL | ALU, decode, bus, timer, cache, MMU, FPU primitives |
| CPU architectural | 68000 baseline and each enabled generation |
| SoC simulation | boot ROM, firmware, Linux NOMMU/MMU profiles |
| Toolchain | binutils/GCC build and testsuites |
| FPGA | synthesis, timing, utilization and reproducibility per board |

Known upstream fx68k warnings should remain narrowly waived. New project RTL
should not inherit blanket suppressions.

## Performance evidence

For each selected FPGA and milestone, archive:

- tool/version/seed and constraints;
- post-route Fmax and worst paths;
- LUT/FF/BRAM/DSP utilization;
- power estimate if available;
- CoreMark/Dhrystone only as secondary indicators;
- cycles per representative m68k instruction mix;
- cache/TLB hit rates and DDR bandwidth/latency;
- Linux boot time and application workloads.

Clock frequency without IPC and memory behaviour is not a meaningful measure
of the new processor.
