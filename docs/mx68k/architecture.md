# MX68K architecture

## Goals and non-goals

Goals:

- run existing big-endian M68000 software from the earliest usable core;
- reach software-visible MC68040 integer, exception, cache, MMU and FPU
  compatibility;
- close timing at 150 MHz or better on the eventual primary FPGA, with a
  200–250 MHz stretch target;
- support up to the 4 GiB physical limit of a 32-bit architecture;
- make precise exceptions, formal verification and differential testing
  structural properties rather than late additions;
- leave clean extension points for MXV, MXLE, MXA and MXMP.

Non-goals for the base project:

- pin- or cycle-exact replication of the MC68040 package;
- preserving the legacy 68000 external bus inside the new core;
- exceeding 32-bit virtual/physical addressing before M40 is complete;
- implementing custom opcodes under the standard M40 feature profile.

## Compatibility profiles

Profiles are cumulative architectural contracts:

| Profile | Contract |
|---|---|
| M00 | MC68000 integer ISA, classic EA, SR, exceptions and 24-bit-visible compatibility |
| M10 | VBR/control state and restartable 68010 exception model |
| M20 | 32-bit addressing, full extension EAs, later integer ISA and control state |
| M40 | 68040 IU, precise frames, split cache/MMU model and FPU programming model |

The implementation may expose 32 physical address bits while executing M00;
profile compatibility describes software behaviour, not board wiring.

## Architectural state

The M40 target state includes:

- D0–D7 and A0–A7, all 32-bit;
- PC and full generation-appropriate SR;
- USP, ISP and MSP selection/state;
- VBR, SFC, DFC and generation control registers;
- cache-control state;
- URP, SRP, TCR, ITT0/1, DTT0/1 and MMUSR;
- eight 80-bit FP registers plus FPCR, FPSR and FPIAR;
- implementation identity, profile and extension feature registers.

MXV will add a separate vector register file. It must not alias the FP register
file. MXLE will add endian execution state only after its exception, debug and
ABI rules are fully specified.

## Endian model

Version 1 boots and executes entirely big-endian. Internally, memories and
caches are arrays of physical bytes: lane zero is the lowest physical address.
The load/store and instruction-alignment units assemble those bytes according
to architectural endian state.

The design reserves a future full MXLE mode covering instruction fetch, data,
stack, vectors, exception frames, page tables, FPU and MXV lane interpretation.
Reset remains big-endian; a privileged, serializing transition may enter
little-endian mode after flushing fetch/cache state. No current RTL may assume
that byte reordering belongs in the external DDR controller.

## Execution organization

The first new core is in-order and single-issue. A conceptual six-stage path is:

```text
F0 address/translation
F1 cache/fetch/alignment
D  decode, extension words and micro-op expansion
E  integer/EA execution
M  load/store, cache and fault completion
C  architectural commit/exception/interrupt
```

Complex CISC instructions expand into explicit internal micro-operations with
symbolic source, generated encoding and tests. There will be no opaque binary
microstore without a reproducible assembler/disassembler.

Common simple instructions may issue directly; complex instructions enter the
same typed micro-op path through a symbolic sequencer. Profile-specific
multi-access instructions carry restart checkpoints. Precise state means the
documented generation-specific fault point, not an invented guarantee that all
earlier external writes can be rolled back. See [micro-ops.md](micro-ops.md).

Instructions may execute over multiple cycles, but all architectural writes
pass through a commit contract. Younger operations cannot become visible before
an older operation that may fault.

## Integer units

The planned integer backend contains:

- 32-bit add/subtract/logic and CCR generation;
- barrel shifter/rotator;
- effective-address AGU;
- pipelined or iterative multiply/divide selected by implementation;
- bitfield, BCD and generation-specific helper units;
- branch condition/target unit;
- micro-op sequencer for MOVEM and other multi-access instructions.

Correct flags and exception state have priority over single-cycle latency.
The current M00 implementation uses a bounded barrel shifter and a 32-cycle
restoring DIVU/DIVS unit; neither relies on a variable-length combinational loop
or combinational division. Ordered two-operand memory operations enter typed
sequence/checkpoint state, initially exercised by CMPM.

## Precise exceptions and interrupts

Every in-flight instruction carries its PC, profile, privilege and pending
effects. Fetch, decode, execute, MMU, cache, fabric and FPU report a structured
fault record. Commit selects the architecturally oldest event, constructs the
profile-specific stack frame, suppresses younger writes and redirects fetch.

Memory operations are tagged until response. A bus response can report access,
page, alignment, timeout, ECC or generic bus error. M00 address-error behaviour
and later-generation unaligned splitting are implemented above the fabric.

Interrupts are synchronized and recognized at legal commit boundaries. The
future interrupt controller supplies a vector, target core and priority; a
compatibility adapter may still produce classic autovectors.

Exception sources, frame generation, RTE parsing, level-7 transition semantics
and verification gates are specified in [exceptions.md](exceptions.md).

## Memory hierarchy

Logical and physical addresses are 32-bit. M40 mode targets separate
instruction/data MMUs, separate 64-entry ATCs and four transparent-translation
registers. Page sizes and table-walk rules follow the M40 specification.

Initial M40 cache targets are separate 4 KiB, four-way I/D caches with 16-byte
lines. Capacity may be parameterized upward, but architecturally visible
maintenance, copyback/write-through, physical tagging and page attributes must
remain compatible. The D side includes a write buffer.

The cache line is the atomic unit of the internal 128-bit fabric. Scalar and
unaligned accesses use byte strobes and, when required, multiple line requests.

## FPU

The FPU is a separately pipelined execution unit sharing precise commit. It
implements the 68040 hardware subset, IEEE formats/rounding/status and the
documented unimplemented-operation path for software support. Extended 80-bit
state is represented explicitly; host `long double` is never the specification.

## MXV

The first vector profile is expected to use sixteen 128-bit registers with
8/16/32/64-bit integer and 32/64-bit floating lanes. The ISA width is fixed
while implementations may use fewer physical lanes and multiple cycles.
Memory order, lane numbering, predication, exceptions and context state are
defined independently of external DDR width.

## Atomics and ordering

M00 TAS and the later M20 CAS/CAS2 operations require indivisible updates as
seen by all masters.
The single-core fabric begins with one outstanding bridge request, but its
protocol carries source/transaction identity and reserves atomic operations.
MXMP will define the coherence protocol and memory model before multiple cached
cores are enabled.

## SMP structure

Future MXMP consists of private cores/L1 caches, coherent endpoints, shared
fabric/last-level resources, per-core reset and ID, routed interrupts/IPIs and
per-core timers. TLB shootdown and cache maintenance are architectural software
contracts. The fx68k bus arbiter is not reused as an SMP fabric.

## Debug and observability

The core will expose a simulation retirement trace and hardware performance
counters. Debug must observe D/A/PC/SR, control/MMU/FPU/MXV state and memory
faults without relying on hierarchical simulator names. A later JTAG/debug
module will use the same architectural debug port.
