# M64K native base ISA

| Field | Value |
|---|---|
| Status | Normative draft; numeric opcode allocation is not frozen |
| Version | 0.2-development |
| Scope | M64K v1 scalar integer, control-flow, FP32/FP64, TSO fence, and atomic instructions |
| Compatibility | Native M64K operand forms and encodings; no M68K source or binary compatibility |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Contract boundary

This document fixes instruction classes and semantics, not final numeric opcode values. The machine-readable contracts are authoritative for allocated fields once ISA version 1.0 is frozen.

Every allocated instruction MUST have one machine-readable contract containing its word layout, total length, operand sizes, register reads and writes, pseudocode, condition results, privilege, memory-order class, alignment, synchronous exceptions, restart point, and reserved-field behavior. Unallocated or malformed encodings raise `IllegalInstruction` without architectural side effects.

## Encoding rules

- A base instruction is exactly one 32-bit word and begins at a 4-byte-aligned address.
- The first word identifies either a complete base instruction or an extension envelope of 64, 96, or 128 total bits.
- An unaligned `PC` raises `InstructionAddress` before fetch.
- Extension fields not defined by the selected ISA version MUST be zero; otherwise the instruction is illegal.
- Five-bit register fields name writable `r0-r31`; there are no data/address banks and no hardwired-zero register.
- PC-relative displacement is measured from the address immediately following the complete instruction.

## MC68060 semantic floor

The official MC68060 computational instruction inventory, including integer operations supplied through the processor's documented software-emulation facility, defines the minimum operation vocabulary considered by M64K v1. Every family in that closed inventory MUST have one native architectural instruction or one one-to-one alias to an architecturally identical instruction. The assembler MUST NOT expand one instruction statement into multiple architectural instructions to satisfy this requirement.

M64K instructions use unified `r0-r31` registers, explicit load/store operand forms, native widths, and M64K exception and memory-order rules. Motorola effective-address encodings and their predecrement, postincrement, address-register, and partial-completion behavior are not inherited. Legacy system instructions are represented by M64K CSR, trap-return, translation, cache-maintenance, wait, and platform-control facilities rather than by recreating SR, USP, vector tables, or hardware stack frames.

Common operations decode directly to typed micro-operations. Multi-step, iterative, restart-sensitive, or uncommon operations remain single architectural instructions but MAY be implemented by the internal microcode sequencer. Internal lowering does not change instruction count, retirement, exception, or restart behavior.

## Required v1 classes

| Class | Required operations | Architectural notes |
|---|---|---|
| Data movement | sized register move, immediate materialization, sign/zero extension | Ordinary B/W/L results zero-extend; sign extension is explicit |
| Integer arithmetic | add, `ADCX`, subtract, `SBCX`, compare, negate | `.F` forms alone update `NZCV`; `ADCX`/`SBCX` explicitly consume and produce persistent `X` |
| Logical | and, or, xor, not, bit test/set/clear/change | Bit numbering starts at the least-significant bit of the scalar value |
| Shift/rotate | logical, arithmetic, rotate, rotate-through-extend | Register counts use the low six bits for quad operations |
| Multiply/divide | signed and unsigned widening multiply; quotient/remainder divide | Divide by zero traps; quotient overflow is reported before destination write |
| Address generation | base plus signed displacement, indexed base, PC-relative address | Address results are 64 bits and canonicality is checked when consumed |
| Memory | byte/word/long/quad load and store | Base operations are naturally aligned and precisely faulting |
| Control flow | conditional branch, direct/indirect call, return, conditional select | A taken target is validated before retirement |
| Floating point | FP32/FP64 move, conversion, arithmetic, compare, square root, and fused multiply-add | IEEE-754 behavior and context are mandatory; FP80 and packed floating formats are rejected |
| System | trap, exception return, control-register access, wait, fence, instruction sync | Privileged forms are defined by [privilege.md](privilege.md) |

M64K v1 requires atomic compare-and-exchange, exchange, and fetch-and-op operations in byte, word, long, and quad sizes where supported by the cacheability contract. The MC68060 double-compare operation receives a separately specified native analogue rather than silently inheriting arbitrary two-address bus-lock behavior. Order semantics are defined by [memory-model.md](memory-model.md).

## Condition state

Ordinary arithmetic and logical instructions preserve `NZCV`. Their explicit `.F` forms update all four flags according to the instruction contract. Compare is flag-producing without a destination. `ADCX`, `SBCX`, and rotate-through-X read and write the persistent per-thread `X` bit; every other base operation preserves `X`. `X` is independently renameable from `NZCV`. Address generation and data movement preserve all condition state.

For operand width `W`, `N` is result bit `W-1`, `Z` is one exactly when the masked result is zero, `V` reports signed overflow, and `C` reports unsigned carry or borrow as specified by the operation. Base `.F` operations compute a fresh, non-sticky `Z`; cumulative or sticky zero behavior exists only if an instruction contract explicitly requests it. The machine-readable contract contains the exact Boolean rule for every arithmetic operation.

## Memory and exception behavior

Loads publish a destination only after translation, permission, alignment, and memory response succeed. Stores become architecturally committed only at retirement, although an M64K v1 implementation may retain them in a store buffer afterward under TSO. A failed memory operation reports its effective address, access size, read/write/execute class, privilege, and restart `PC`.

Control-register accesses check encoding legality before privilege and privilege before state mutation. Trap return validates the complete saved trap CSR state before changing privilege, address space, or `PC`; hardware does not consume a memory frame.

## Not in v1

Scalable vector, matrix, transactional-memory, binary-compatibility, Motorola FP80, and packed floating-point formats are not part of M64K v1. Integer packed-decimal operation families required by the MC68060 semantic floor remain architectural operations and are expected to use microcode unless synthesis evidence justifies a dedicated unit.
