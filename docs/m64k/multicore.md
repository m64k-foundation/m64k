# M64K multicore boot and ISA boundary

Bringing a secondary core online does not require a new instruction encoding.
It requires a discoverable system-controller contract and firmware that uses
it. Core 0 starts from the architectural reset vectors; all other cores remain
held in reset until Core 0 has prepared a trampoline and released each one.

## System-controller contract

The future controller exposes one register bank per core containing:

- presence, running, stopped and fault status;
- boot PC, initial supervisor SP and one implementation-defined boot argument;
- reset/enable control with read-back;
- IPI set, pending and acknowledge state.

Core 0 initializes shared memory and the per-core bootstrap data, performs the
required ordering operation, writes the boot registers and releases reset. A
secondary core begins at the programmed trampoline, establishes its private
stack and architectural state, then reports itself online through shared
memory or an MMIO doorbell. No memory request from a held core may escape into
the fabric.

The reset mechanism is intentionally MMIO rather than an opcode: it remains
usable by boot ROMs, operating systems and debug hardware, and it does not
couple the instruction set to one SoC topology.

## Interrupts and IPIs

Every core has an independent `m64k_irq_if`. The interrupt controller selects
a target, priority level and optional vector. Classic devices may autovector;
IPIs should normally use explicit vectors so software can distinguish their
purpose. Per-core timers and interrupt masks are separate state. A source must
hold its request and vector stable until the target acknowledges acceptance.

Level-triggered IPIs are MMIO events, not instructions. A future wait/wake
instruction may reduce idle power and latency, but it is an optional M64K-SMP
facility rather than a prerequisite for SMP boot.

## Instructions SMP actually needs

Boot can use ordinary M68k loads, stores and control flow. Correct concurrent
software additionally needs these architectural primitives:

- locked `TAS` for the M00 compatibility profile;
- `CAS` and `CAS2` when the M20 profile is implemented;
- coherent cache-line ownership for locked/atomic operations;
- architecturally specified acquire, release and full ordering points;
- scoped cache and TLB maintenance for page-table changes and shootdowns;
- a precise privilege, exception and virtualization contract for all control
  operations.

Established Motorola encodings and semantics take priority. M64K-A/M64K-SMP opcodes
are introduced only for a capability that the compatible ISA cannot express
cleanly. Every custom instruction must be represented in the machine-readable
ISA database and have assembler, disassembler, compiler-intrinsic, privilege,
exception, memory-ordering and context-switch definitions before firmware or
an OS depends on it.

## Coherence dependency

Releasing multiple cores is not a claim of working SMP. Cached cores require a
coherent fabric, atomic endpoint, invalidation/snoop protocol and a defined
memory model. Firmware bring-up may initially run secondaries with caches
disabled, but Linux SMP is an exit gate only after contention, IPI, TLB
shootdown and cache-coherence stress tests pass.
