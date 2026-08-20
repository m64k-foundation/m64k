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
| Integer arithmetic | add, `ADCX`, subtract, `SBCX`, compare, `NEG`, `NEGX` | `.F` forms alone update `NZCV`; `ADCX`, `SBCX`, and `NEGX` explicitly consume and produce persistent `X` |
| Logical | and, or, xor, not, bit test/set/clear/change | Bit numbering starts at the least-significant bit of the scalar value |
| Shift/rotate | logical, arithmetic, rotate, rotate-through-extend | Register counts use the low six bits for quad operations |
| Multiply/divide | signed and unsigned narrow and widening multiply; quotient, remainder, fused quotient-remainder, and double-width-dividend divide | Divide by zero and requested-quotient overflow are precise synchronous faults before any destination write |
| Address generation | base plus signed displacement, indexed base, PC-relative address | Address results are 64 bits and canonicality is checked when consumed |
| Memory | byte/word/long/quad load and store | Base operations are naturally aligned and precisely faulting |
| Control flow | conditional branch, direct/indirect call, return, conditional select | A taken target is validated before retirement |
| Floating point | FP32/FP64 move, conversion, arithmetic, compare, square root, and fused multiply-add | IEEE-754 behavior and context are mandatory; FP80 and packed floating formats are rejected |
| System | trap, exception return, control-register access, wait, fence, instruction sync | Privileged forms are defined by [privilege.md](privilege.md) |

M64K v1 requires atomic compare-and-exchange, exchange, and fetch-and-op operations in byte, word, long, and quad sizes where supported by the cacheability contract. The MC68060 double-compare operation receives a separately specified native analogue rather than silently inheriting arbitrary two-address bus-lock behavior. Order semantics are defined by [memory-model.md](memory-model.md).

## Condition state

Ordinary arithmetic and logical instructions preserve `NZCV`. Their explicit `.F` forms update all four flags according to the instruction contract. Compare is flag-producing without a destination. `ADCX`, `SBCX`, `NEGX`, and rotate-through-X read and write the persistent per-thread `X` bit; every other base operation preserves `X`. `X` is independently renameable from `NZCV`. Address generation and data movement preserve all condition state.

Whenever `NZCV` is transferred as a packed four-bit value, bits 3 through 0 are `N`, `Z`, `C`, and `V`, respectively. Named state fields remain preferred inside RTL so carry and overflow cannot be exchanged accidentally.

For operand width `W`, `N` is result bit `W-1`, `Z` is one exactly when the masked result is zero, `V` reports signed overflow, and `C` reports unsigned carry or borrow as specified by the operation. Base `.F` operations compute a fresh, non-sticky `Z`; cumulative or sticky zero behavior exists only if an instruction contract explicitly requests it. The machine-readable contract contains the exact Boolean rule for every arithmetic operation.

## Core scalar ALU semantics

`ADD`, `SUB`, `ADCX`, `SBCX`, `AND`, `OR`, `XOR`, `NOT`, `NEG`, and `NEGX` operate on B, W, L, and Q values and zero-extend every destination GPR write to 64 bits. Binary operations evaluate `left operation right`; subtraction and comparison therefore compute `left - right`. `NEG` computes `0 - source`, while `NEGX` computes `0 - source - X`. `ADCX`, `SBCX`, and `NEGX` consume the persistent input `X` and publish unsigned carry or borrow as the new `X` at retirement. Other operations preserve `X`.

The ordinary destination-producing forms preserve `NZCV`. Their `.F` forms update all four bits freshly. Addition sets `C` on unsigned carry and `V` when the signed mathematical sum is outside the selected width. Subtraction sets `C` on unsigned borrow and `V` on signed overflow. Logical `.F` forms compute `N` and `Z` from the result and clear `V` and `C`. `ADCX.F`, `SBCX.F`, and `NEGX.F` use the same fresh flag rules with the input `X` included in the arithmetic; their `Z` result is not sticky across an instruction sequence.

`CMP` computes the same flags as `SUB.F` but publishes no GPR destination and preserves `X`. `TST` publishes no GPR destination, computes fresh `N` and `Z` from its source, clears `V` and `C`, and preserves `X`. None of these register operations accesses memory, depends on privilege, or raises a synchronous arithmetic exception. All their architectural writes occur at one precise retirement boundary.

The lineage review uses *M68000 Family Programmer's Reference Manual*, 1992 edition: `ADD` pp. 4-3 through 4-5, `ADDX` pp. 4-12 through 4-14, `AND` pp. 4-14 through 4-16, `CMP` pp. 4-74 through 4-76, `EOR` pp. 4-99 through 4-101, `NEG/NEGX` pp. 4-142 through 4-146, `NOT/OR` pp. 4-147 through 4-151, `SUB` pp. 4-173 through 4-175, `SUBX` pp. 4-182 through 4-184, and `TST` pp. 4-191 through 4-192. Their MC68060 cut-line presence is recorded in *M68060 User's Manual*, Revision 1, Section 1.9, Table 1-3, pp. 1-16 through 1-20. M64K modifies those contracts by adding Q width, unifying registers, eliminating implicit memory operands, zero-extending narrow results, making ordinary flag writes explicit through `.F`, separating `X` from `C`, and replacing cumulative `ADDX/SUBX/NEGX` zero behavior with fresh per-instruction `Z`.

## Scalar shift and rotate semantics

`ASL`, `ASR`, `LSL`, `LSR`, `ROL`, `ROR`, `ROXL`, and `ROXR` operate on B, W, L, and Q scalar values. The source value is truncated to the selected width before the operation, and the result is zero-extended to 64 bits when written to a GPR. The architectural count is the low six bits of the count operand and is therefore in the range 0 through 63 for every width. These instructions have no memory-destination form; software uses an explicit load, register operation, and store.

Logical and arithmetic shifts do not reduce the count modulo the operand width. `LSL` and `ASL` produce zero when the count is greater than or equal to the width. `LSR` produces zero under the same condition. `ASR` replicates the original sign bit and therefore produces either zero or the width-sized all-ones value when the count is greater than or equal to the width. `ASL` has the same result bits as `LSL`.

`ROL` and `ROR` rotate within a ring of exactly `W` bits and use `count modulo W` as the effective rotation. `ROXL` and `ROXR` rotate the operand and persistent `X` state as one `W+1`-bit ring and use `count modulo (W+1)`. A zero count leaves the operand and `X` unchanged. `ROXL` and `ROXR` write `X` even without `.F`; all other shift and rotate instructions preserve `X`.

Without `.F`, the instructions preserve `NZCV`. With `.F`, `N` and `Z` are computed freshly from the width-sized result. `V` is cleared except for `ASL`, where it is set exactly when the mathematical signed value multiplied by `2^count` cannot be represented in `W` signed bits. For a zero count, `C` is cleared for shifts and rotates without extend; `ROXL.F` and `ROXR.F` copy the preserved input `X` to `C`. For a nonzero shift count, `C` is the last bit shifted out; it is zero after a logical shift beyond the width and equals the original sign after an arithmetic right shift beyond the width. For a nonzero rotate count, `C` is the last bit rotated out. In rotate-through-X operations this is also the resulting `X` value.

These rules deliberately modify the M68000-family behavior described by the *M68000 Family Programmer's Reference Manual*, 1992 edition, `ASL/ASR` pp. 4-21 through 4-24, `LSL/LSR` pp. 4-113 through 4-115, `ROL/ROR` pp. 4-160 through 4-162, and `ROXL/ROXR` pp. 4-163 through 4-165. M64K retains the low-six-bit register-count principle and last-bit carry interpretation, adds Q width, removes implicit memory operands, makes flag updates explicit, zero-extends narrow GPR results, and prevents ordinary shifts from modifying `X`. The MC68060 cut-line presence is recorded by *M68060 User's Manual*, Revision 1, Section 1.9, Table 1-3, pp. 1-16, 1-18, and 1-19.

## Scalar multiply and divide semantics

For this section, `W` is 8, 16, 32, or 64 bits. Every input is truncated to `W` before signed two's-complement or unsigned interpretation. Register-only multiply and divide operations are legal at every privilege level, access no memory, and preserve `X`.

Signed and unsigned narrow multiply produce the low `W` bits of the exact `2W`-bit product and zero-extend that result to 64 bits. Signed and unsigned widening multiply produce the complete `2W`-bit product. A widening B, W, or L input writes one GPR containing the 16-, 32-, or 64-bit product; results narrower than 64 bits are zero-extended. A widening Q input writes the high and low 64-bit halves to two distinct destinations. All source values are captured before destination writes, so sources may alias destinations. Two-output destinations must be distinct; a future encoding that names one destination twice is illegal and has no architectural effect.

The native division family provides same-width quotient-only, remainder-only, and fused quotient-remainder results, plus a fused double-width-dividend form. The same-width forms divide a `W`-bit dividend by a `W`-bit divisor. The double-width form concatenates high-`W` and low-`W` source values before interpreting one `2W`-bit dividend, then produces a `W`-bit quotient and `W`-bit remainder in distinct destinations. The two source operands may name the same register because both values are captured before execution; only the two output destinations must be distinct. A signed quotient is truncated toward zero. The remainder satisfies `dividend = quotient * divisor + remainder`, its magnitude is less than the divisor magnitude, and a nonzero signed remainder has the dividend's sign.

A zero divisor raises `IntegerDivideByZero`. When a quotient is requested, a mathematical quotient outside the signed or unsigned `W`-bit range raises `IntegerDivideOverflow`; this includes signed minimum divided by minus one. A remainder-only signed minimum divided by minus one succeeds with remainder zero because it does not request the unrepresentable quotient. Divide by zero has priority over quotient overflow. Both faults save the faulting instruction in `tpc`, write zero to `tval`, and publish no destination or condition-state change.

Without `.F`, all multiply and divide operations preserve `NZCV`. Narrow signed multiply `.F` sets `V` when the exact product is not the sign extension of its low `W` bits; narrow unsigned multiply `.F` sets `V` when any upper product bit is nonzero. Their `N` and `Z` describe the retained low product and `C` is zero. Widening multiply `.F` computes `N` and `Z` over the complete `2W`-bit product and clears `V` and `C`. Successful quotient and fused divide `.F` compute `N` and `Z` from the quotient; successful remainder-only `.F` computes them from the remainder; both clear `V` and `C`. Faults preserve `NZCV` and `X` through precise retirement.

Multiplication lowers directly to a pipelined full-product execution operation. Division lowers directly to a dedicated iterative divider operation; arithmetic iteration is not an architectural instruction sequence and does not require control-store microcode. Latency, early completion, radix, pipeline depth, and unit sharing are not architectural. All selected results and optional condition state publish atomically at one retirement boundary.

The lineage review uses *M68000 Family Programmer's Reference Manual*, 1992 edition: `DIVS/DIVSL` pp. 4-92 through 4-95, `DIVU/DIVUL` pp. 4-96 through 4-99, `MULS` pp. 4-135 through 4-137, and `MULU` pp. 4-138 through 4-140. The MC68060 cut-line and implementation history are recorded by *M68060 User's Manual*, Revision 1: Section 1.9 Table 1-3 pp. 1-16 through 1-20; Sections 8.2.3 and 8.2.4 pp. 8-7 through 8-8; Section 10.6 Table 10-9 p. 10-16; and Appendix C Sections C.2 and C.2.3 pp. C-4 through C-5 and C-9 through C-11. *68K Programmer's Reference Manual Errata*, Revision 1, p. 2 contains no multiply or divide correction. M64K deliberately replaces Motorola's V-only quotient-overflow result and vector-frame trap behavior with native precise faults and CSR trap state.

## Memory and exception behavior

Loads publish a destination only after translation, permission, alignment, and memory response succeed. Stores become architecturally committed only at retirement, although an M64K v1 implementation may retain them in a store buffer afterward under TSO. A failed memory operation reports its effective address, access size, read/write/execute class, privilege, and restart `PC`.

Control-register accesses check encoding legality before privilege and privilege before state mutation. Trap return validates the complete saved trap CSR state before changing privilege, address space, or `PC`; hardware does not consume a memory frame.

## Not in v1

Scalable vector, matrix, transactional-memory, binary-compatibility, Motorola FP80, and packed floating-point formats are not part of M64K v1. Integer packed-decimal operation families required by the MC68060 semantic floor remain architectural operations and are expected to use microcode unless synthesis evidence justifies a dedicated unit.
