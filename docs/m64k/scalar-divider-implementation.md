# M64K scalar divider implementation note

| Field | Value |
|---|---|
| Status | Implemented RTL tranche; not an ISA freeze or product signoff claim |
| Version | 0.1-development |
| Scope | Native scalar integer divide execution unit |
| Compatibility | Implements the encoding-independent M64K v1 scalar multiply/divide semantic contract; provides no M68K binary, ABI, exception-frame, or assembly-source compatibility |

## Architectural boundary

The normative behavior remains defined by `docs/m64k/base-isa.md`, `docs/m64k/exceptions.md`, and `isa/native/semantics/scalar-multiply-divide-v1.json`. This note records a microarchitectural implementation and its verification boundary; radix, latency, handshake staging, and backend tags are not architectural properties.

The unit accepts typed B, W, L, and Q requests for signed or unsigned same-width quotient, remainder, or fused quotient-remainder operations and for signed or unsigned fused `2W/W` operations. It does not decode opcodes. The current ISA encoding remains deliberately unallocated, so this implementation does not create an undocumented instruction encoding.

## Datapath

The production RTL uses an iterative radix-4 restoring recurrence and contains no combinational divide or remainder operator. Each iteration consumes two dividend-magnitude bits with two cascaded 65-bit compare/subtract steps. The active magnitude is aligned once during request capture, allowing one datapath to execute all operand sizes. The maximum arithmetic iteration counts are 4, 8, 16, and 32 cycles for same-width B, W, L, and Q operations and 8, 16, 32, and 64 cycles for the corresponding double-width-dividend operations. Request capture and response publication add control cycles around the recurrence.

Signed inputs are truncated to their architectural widths before interpretation. The dividend is sign-extended into 129 bits before magnitude conversion, which represents the signed 128-bit minimum without host-language or signed-absolute-value overflow. Quotient and remainder signs are restored only after unsigned magnitude division. This implements quotient truncation toward zero and gives every nonzero signed remainder the dividend's sign.

The iterative state consists of the aligned 128-bit dividend/quotient register, a 64-bit partial remainder, a 64-bit divisor magnitude, the operand masks and signs, a bounded iteration counter, and captured request metadata. Two compare/subtract stages are the intentional arithmetic critical path. A future radix-8 candidate needs measured technology-mapped timing, area, and power evidence before replacing this radix-4 baseline because a third cascaded stage may reduce cycle count while reducing achievable frequency.

## Precise execution protocol

Requests and responses use independent ready/valid handshakes. A response remains bit-stable while valid and backpressured. Once published, a response is never retracted by squash; the backend may sink a stale completion, and the ROB performs authoritative tag validation.

Every request, response, and squash carries the private execution tag defined by `m64k_execute_backend_pkg`. The tag includes execution context, ROB index, ROB generation, allocation sequence, and micro-operation index. An exact matching squash cancels only an in-progress recurrence. The allocator contract prohibits reuse of a complete tag until every accepting unit has either completed or acknowledged cancellation.

Successful results are published atomically with explicit `QUOTIENT` and `REMAINDER` roles. Divide by zero is detected before iteration and has priority over quotient overflow. Quotient overflow is checked only when the selected result form requests a quotient. Either fault publishes zero results and no condition-state update. Successful `.F` operations publish `N` and `Z` from the selected quotient or remainder and clear `V` and `C`; operations without `.F` publish no flag update.

## Verification and silicon gates

The focused warning-fatal RTL test exhaustively checks all 256 byte dividend patterns against all 256 byte divisor patterns for signed and unsigned quotient, remainder, and fused forms. Its double-width byte partition crosses every divisor encoding with signed and unsigned quotient limits, the values immediately inside and outside those limits, zero remainder, and maximum-magnitude legal remainders, while separately covering zero-divisor dividend extrema. Directed W/L/Q cases cover `2W` minima and maxima, quotient limits and their adjacent values, signed minimum divided by minus one selector outcomes, 128-by-64 operation, divide-by-zero priority, quotient overflow, flag selection, response backpressure, exact and nonmatching squash, stale-response consumption, and core/thread tag isolation.

Embedded RTL assertions require held-response stability and non-retraction, effect-free fault responses, bounded and monotonically progressing iteration counts, terminal response publication, and compact role/count consistency for single and fused results.

The synthesis manifest keeps architecture types, private backend types, divider types, and divider RTL in a reproducible order. Frontend lint, post-process structural checks, generic synthesis, warning-log validation, and QoR summary generation are part of the divider silicon gate. Generic synthesis evidence is comparative only and does not constitute place-and-route timing, power, or manufacturing signoff.
