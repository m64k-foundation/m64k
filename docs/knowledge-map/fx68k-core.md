# fx68k core map

## Executive result

The core is a substantial, microcoded MC68000 implementation, not an incomplete
ALU. Its datapath is internally 16-bit with 32-bit architectural registers split
into halves, a 32-bit address unit and a classic 24/16-bit external bus. The
upstream claim is cycle-exact MC68000 behaviour except for bus retry; local tests
are far too small to prove that claim exhaustively.

Extending this design to MC68010 is conceivable. MC68020 and later require such
wide changes that a new modular core is safer than progressively mutating the
known 68000 reference.

## Files and generated state

| File | Content |
|---|---|
| `fx68k.sv` | CPU top, decode, datapath, sequencer, exceptions and bus |
| `fx68kAlu.sv` | Integer ALU, shifts, BCD and CCR logic |
| `uaddrPla.sv` | Large generated opcode/effective-address PLA |
| `microrom.mem` | 1024 × 17-bit microstore; 518 nonzero words |
| `nanorom.mem` | 336 × 68-bit nanostore |

The control stores total about 4.9 KiB. The repository contains no symbolic
microcode source, labels, assembler or generator for the PLA. Editing the
`.mem` images directly is not an acceptable evolution path.

## Module hierarchy

```text
fx68k
├── uRom / nanoRom / microToNanoAddr
├── uaddrDecode -> pla_lined
├── sequencer
├── nDecoder3
├── irdDecode
├── excUnit
│   ├── register file and datapath
│   ├── dataIo
│   └── fx68kAlu
│       ├── rowDecoder
│       ├── aluGetOp
│       ├── ccrTable
│       ├── aluShifter
│       └── aluCorf
├── busControl
└── busArbiter
```

## External interface

Inputs include master clock, `enPhi1/enPhi2`, synchronous power/reset,
DTACK/VPA/BERR, HALT, bus request/acknowledge and IPL. Outputs include
`eab[23:1]`, 16-bit data, UDS/LDS/AS/RW, FC, E/VMA, bus grant and processor
reset/halt state.

There are no 68020-style dynamic bus sizing signals, burst protocol, distinct
logical/physical addresses, cache/snoop ports or FPU/coprocessor interface.
Upstream also warns that output enables for physical chip replacement are
incomplete.

## Control flow

```text
IR/opcode ──> opcode/EA PLA ──> micro-entry candidates A1/A2/A3
    |                                      |
    +──> instruction-dependent decode      v
                                      sequencer/NMA
                                            |
                            1024×17 microstore
                                            |
                             micro-to-nano mapping
                                            |
                             336×68 nanostore
                                            |
                               datapath/ALU/bus enables
```

The microstore controls sequencing and conditions. The nanostore controls
transfers, ALU/address operations, bus starts and architectural updates.
`microToNanoAddr` shares datapath sequences among micro-routines.

Internal phases T1–T4 select sources, move values, write destinations and
advance control. T0 is used around reset/waits/faults. Micro/nanostore access
and some CCR paths are multicycle timing paths according to upstream notes.

## Architectural state and datapath

The register file is two arrays of 18 16-bit halves:

- indices 0–7: D0–D7;
- indices 8–15: address registers/A7/USP selection;
- index 16: SSP;
- index 17: temporary DT.

PC, address/data temporaries and internal buses are also split into high/low
halves. The 32-bit address unit performs effective-address arithmetic, PC
updates, increments/decrements and counters for iterative operations.

The programmer-visible status is MC68000-style `T/S/I2:I0/XNZVC`. There is no
VBR, SFC/DFC, MSP/ISP, T0/T1 split, CACR/CAAR, MMU state or floating-point
state.

## Integer ALU

The ALU implements the operations required by the MC68000:

- AND, OR and EOR;
- add/subtract variants with carry/extend;
- arithmetic/logical shifts and rotations, including extend;
- extension and internal helper operations;
- ABCD/SBCD correction and half-carry;
- full X/N/Z/V/C update masks, including cumulative Z semantics;
- iterative multiply and divide using the shifter, address unit and microcode.

Consequently, “complete the ALU” for M68040 means designing a new integer
execution unit and supporting decode/retirement machinery. It does not mean
filling a few missing operators in the existing `case` statement.

## Bus engine

`busControl` models SRESET, idle and S0/S2/S4/S6 phases. It supports byte/word
read and write, waits, BERR, VPA/VMA, E clock, TAS read-modify-write, function
codes, interrupt acknowledge and BR/BG/BGACK arbitration.

Bus retry is deliberately disabled in the RTL. HALT can affect availability,
but BERR+HALT cannot restart an aborted transfer. This is already a gap for a
fully robust MC68010-style fault model.

## Exceptions and interrupts

The core structurally implements bus/address error, illegal instruction,
divide by zero, CHK, TRAPV, privilege, trace, Line A/F, spurious, autovector,
externally vectored interrupts and TRAP #n. It distinguishes group-zero and
group-one processing and halts on a nested critical fault.

IPL is synchronized; level 7 is edge-sensitive NMI. During IACK, VPA requests
an autovector, DTACK supplies an external vector and BERR selects spurious.
The SoC integration always chooses VPA/autovector.

Line F currently goes directly to vector 11. There is no operand/result path
to an FPU and no floating-point architectural state.

## MC68000 ISA coverage found structurally

The decoders and microcode entry logic cover classic data movement, integer
arithmetic/logical, bit, shift/rotate, multiply/divide, BCD, branch/DBcc/Scc,
control flow, MOVEM/MOVEP, stack/frame, traps, privileged and status-register
instructions. Effective addresses cover the classic 68000 register,
indirect, pre/post, displacement, brief indexed, absolute, PC-relative and
immediate forms.

This is structural evidence, not exhaustive behavioural proof. Existing local
automation only executes a few moves, comparisons, branches and byte lanes.

## Generation-by-generation missing work

### MC68010

- VBR, SFC/DFC and MOVEC;
- BKPT/RTD and revised privileged behaviour;
- new exception stack frames and restartable bus faults;
- loop mode and proper bus retry.

### MC68020

- 32-bit logical/external addressing and configurable bus sizing;
- full extension words, scaled index and memory indirect modes;
- 32-bit branches and long multiply/divide;
- bitfields, CAS/CAS2, CHK2/CMP2, TRAPcc, PACK/UNPK and other ISA additions;
- MSP/ISP and additional control registers;
- coprocessor protocol, new exception frames, instruction cache and deeper
  execution overlap.

The current PLA's classic EA categories do not naturally accommodate 68020
full-extension parsing.

### MC68030

- all 68020 work;
- integrated PMMU, translations, ATC/TLB and table walker;
- root/translation/status registers and PMMU instructions;
- MMU-specific faults, restart and cache interactions.

### MC68040

- independent instruction/data MMUs and ATCs;
- independent physical I/D caches and cache-control instructions;
- six-stage integer pipeline with precise retirement;
- write buffers, burst-capable 32-bit memory interface and access attributes;
- integrated floating-point register file, pipeline, IEEE rounding/status and
  exception model;
- MOVE16 and generation-specific integer/system instructions;
- 68040 stack frames, access-error status and software-emulation hooks.

An MMU interposed outside fx68k or an MMIO FPU can be a useful experiment, but
neither creates an architecturally compatible MC68030/MC68040.

## Safe change policy

Before any microcode modification, build a symbolic description, disassembler,
assembler and round-trip test that reproduces both ROM images bit-for-bit.
Before any CPU-generation extension, build instruction, CCR, exception and bus
conformance tests. Until then, preserve fx68k as `m68000_compat` and use it as a
differential reference for a new core's 68000 mode.
