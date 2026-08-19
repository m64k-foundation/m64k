# M64K exceptions, traps and interrupts

This document defines the implementation discipline for one of the most
sensitive compatibility areas. The NXP/Freescale programmer's reference and
MC68040 user manual remain authoritative for profile-specific encodings and
frames. No generic “M68k frame” is assumed.

## Terminology

- **fault**: detected while attempting an instruction or memory operation;
- **trap**: architecturally requested by the executed instruction;
- **trace**: post-instruction debug exception;
- **interrupt**: asynchronous request accepted at a legal boundary;
- **exception**: the common control transfer and frame mechanism;
- **restart/checkpoint**: documented point from which execution can continue.

## Exception record

All producer stages report the typed `m64k_exception_t` record from
`rtl/m68k/m00/core/m64k_arch_pkg.sv`. It preserves both instruction-start and
next PC, logical and physical address, opcode, access attributes, stage,
rerun capability and a profile-specific status field. Producers do not write
stack frames themselves.

The commit/exception unit performs four distinct jobs:

1. choose the oldest eligible event according to profile precedence;
2. freeze/squash only effects younger than the architectural fault point;
3. perform the privilege/stack transition and generate the exact frame;
4. fetch the handler through VBR rules and redirect the frontend.

## State that must be captured

At minimum, exception entry must reason about:

- pre-exception SR, PC and active USP/ISP/MSP;
- T1/T0 trace state, S/M stack selection and interrupt mask;
- instruction-start versus post-instruction stacked PC;
- function code/access space, read/write and operand size;
- logical/effective address and, when available, translated physical address;
- instruction and pipeline/internal continuation state required by the frame;
- ATC/MMU status, writeback status and transfer modifier;
- FPU pending exception, FPSR/FPIAR and unimplemented-operation state.

Entry snapshots the old state before changing S/M, trace bits or interrupt
mask. Reset is a separate state machine, not a normal stacked exception.

## Vector contract

The shared vector constants live in `m64k_arch_pkg.sv`: reset vectors 0/1,
access fault 2, address error 3, illegal 4, divide-by-zero 5, CHK/CHK2 6,
TRAPcc/TRAPV 7, privilege 8, trace 9, line A/F 10/11, format error 14,
uninitialized interrupt 15, spurious 24, autovectors 25–31, TRAP #n 32–47,
floating-point 48–54 and MMU configuration 56.

The constants do not imply identical availability or semantics in every
profile. M00 uses a fixed vector base; M10 and later use VBR. Reserved vectors
remain reserved unless a named M64K extension assigns them.

## Priority and recognition

Priority is evaluated at explicit boundaries, never by whichever RTL signal
appears first in an `if` statement:

- reset dominates all activity and aborts normal sequencing;
- synchronous events are ordered by the oldest architectural operation and
  the profile's documented exception class;
- trace is generated from the successfully retired instruction and retains
  the PC semantics of that trace mode;
- maskable interrupts are accepted only at legal boundaries when their level
  exceeds the SR mask;
- level 7 has edge/transition semantics that require a dedicated synchronized
  latch rather than the ordinary level comparison;
- an access fault while building a fault frame follows the documented
  double-fault/halt path; it must not recursively corrupt the stack.

The exact precedence table will be machine-readable and independently tested
for each compatibility profile before that profile is claimed.

## Frame and RTE discipline

Frames are emitted by profile-specific encoders and parsed by matching RTE
decoders. Format IDs, reserved fields, stack alignment and internal words are
transcribed from the authoritative manuals and checked against independent
software tests. RTE validates privilege and format before restoring state;
invalid later-generation formats generate the format-error vector.

The current M00 execution slice implements the normal six-byte frame used by
illegal-instruction, privilege, divide-by-zero, CHK, TRAP and TRAPV paths. It
stacks the pre-exception SR followed by the architecturally selected PC, enters
supervisor mode with trace cleared, fetches the fixed-base vector and supports
an exact RTE round-trip. Fault-like illegal and privilege exceptions retain the
instruction PC; instruction traps such as divide-by-zero, CHK and TRAP retain
the following PC. CHK.W performs signed bounds checks, reports a negative
operand through SR.N and preserves completed effective-address side effects.

M00 T1 trace is sampled at instruction start and delivered after successful
completion with the following/control-transfer PC. A synchronous instruction
trap is entered before its pending trace, while a pending trace is entered
before an asynchronous interrupt. Directed nested-frame tests lock down the
`trap -> trace -> interrupt` ordering. Later T0 branch-trace modes remain tied
to the profiles that define them.

Maskable levels 1–6 are accepted at the same precise boundary only when their
level exceeds SR.I; the accepted level becomes the new SR.I value. They use
autovectors 25–30 unless the routed source supplies an explicit vector. Level
7 is transition-latched, bypasses an SR.I value of seven, uses autovector 31 by
default and wakes STOP. RTE restores the stacked PC and SR for all of these
normal frames.

M00 bus and address errors use their distinct seven-word group-0 frame. From
the final SSP upward it contains the special status word, 32-bit access
address, instruction register, saved SR and saved PC. The SSW records read or
write, instruction or non-instruction, and the original user/supervisor
program/data function code. Odd word/long data accesses are rejected before a
fabric request. As on the MC68000, RTE does not parse this special frame: a
recovering handler must discard its first eight diagnostic bytes so A7 points
at the saved SR before executing ordinary RTE.

The current sequencer conservatively takes the non-rerunnable halt path for a
bus/address fault while writing *any* exception frame or acquiring its vector.
This is stricter than MC68000UM 6.3.9: the hardware must halt when a second bus
error occurs while processing reset, bus error or address error, but a first
bus error encountered while processing a group-1/2 exception must itself enter
the group-0 bus-error path.  Nested group tracking and that first-fault
transition remain an explicitly recorded M00 conformance gap; they must not be
described as completed double-fault semantics.

Legal M00 long accesses at a 16-byte-line offset of 14 are decomposed into two
ordered word requests. The first response never retires the instruction or
updates registers; reads are reassembled in big-endian order and the second
response performs the single architectural commit. External writes from a
successful first beat remain visible if the second beat faults, matching the
general partial-completion rule. In that case the group-0 access address names
the failing second beat rather than the original long's base address.

The implemented M00 frame path and future M10 restart frames, M20 fault frames
and M40 access-error/writeback frames use shared field helpers but retain
profile-specific sequencers and parsers.

## Memory and restart semantics

Address alignment is checked before a fabric request wherever the profile
requires an address error. M20/M40 unaligned accesses are split only according
to their architectural rules. Translation, protection, cache push and bus
faults retain enough context to distinguish instruction, table-search and data
cycles.

Register effects normally wait for commit. Multi-access memory instructions
use explicit checkpoints because prior external writes cannot be rolled back.
Exception frames and restart logic reproduce the selected generation's visible
partial-completion behaviour. Atomic operations use the fabric lock/atomic
protocol and have separate failure semantics.

## Verification gates

Each profile needs directed and generated tests for:

- every synchronous vector and every legal instruction source;
- all CCR/SR bits, reserved-bit masking and privilege violations;
- instruction-start/post-instruction PC selection;
- USP/ISP/MSP switching and nested exceptions;
- all interrupt levels, masks, level-7 transitions and vector responses;
- trace modes around branches, traps, STOP and RTE;
- faults at every memory micro-op/checkpoint, including frame writes;
- legal/illegal RTE frame formats and double faults;
- MMU table-search, cache/writeback and FPU exception interaction;
- back-to-back and simultaneous event priority.

A profile is not complete when its ALU passes. It is complete only when its
exception matrix and frame round trips pass differential and RTL tests.
