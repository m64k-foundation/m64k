# Shared Shift/Rotate Execution Candidate

Status: functionally verified candidate, rejected by the current structural PPA selection gate
Document version: 1.0
Architecture scope: `M64K-v1.scalar-shift-rotate`
Compatibility statement: native M64K execution implementation; no M68K binary, ABI, exception-frame, effective-address, or bus compatibility is provided

## Architectural contract

The normative behavior remains `isa/native/semantics/scalar-shift-rotate-v1.json` and the scalar shift/rotate section of `docs/m64k/base-isa.md`. This document describes a microarchitectural experiment and does not define new ISA behavior.

The historical rationale remains the official manuals and exact sections recorded by the normative contract and `docs/m64k/rotate-extend-iterative-implementation.md`. No observed operating-system, firmware, simulator, benchmark, or test behavior defines this implementation.

## Organization

`m64k_shift_rotate_shared` integrates all eight scalar operations behind one typed request and response contract. `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, and `ROR` execute through the already-proved throughput-one logarithmic datapath. `ROXL` and `ROXR` reuse that same physical datapath for two complementary shifts rather than instantiating a second variable-distance ring network.

For a `W`-bit operand and reduced nonzero rotate-through-X count `k`, the `W+1`-bit ring identity is:

- `ROXL`: `(source << k) | (source >> (W + 1 - k)) | (X << (k - 1))`
- `ROXR`: `(source >> k) | (source << (W + 1 - k)) | (X << (W - k))`

The first shift absorbs the X insertion without a dynamic one-hot generator. For `ROXL`, `{source[W-2:0], X}` is shifted left by `k-1`; for `ROXR`, `{X, source[W-1:1]}` is shifted right by `k-1`. The first shift's carry output is also the outgoing X for `k>1`; the `k=1` boundary selects the architecturally adjacent source bit directly. The second pass supplies the wrapped source fragment. Count zero preserves source and X. The `W=64`, complementary-count-64 case contributes zero and does not truncate 64 into the six-bit shift count.

Ordinary requests have one-cycle registered response latency and accept one request every cycle while responses are consumed. A ROX request uses one internal second-pass cycle and then publishes one atomic GPR, flags, and X response. It temporarily reserves the one shared shift resource; this is a bounded two-pass policy, not an indefinite block. Published responses are irrevocable and stable under backpressure. Exact full-tag squash cancels only an unpublished ROX operation. Tags include core, hardware thread, ROB index and generation, 64-bit allocation sequence, and micro-operation index.

Storage without architecturally valid state is intentionally not reset. The valid state machine is synchronously reset, and every retained payload field is written before it can be published. This follows the project rule against resetting bulk datapath storage merely for simulation convenience.

## Verification evidence

The warning-fatal Verilator test uses the complete executable reference for ordinary operations and a separate repeated-one-bit `W+1` ring oracle for ROX. The ROX oracle does not reuse the candidate's complementary-shift identities. Coverage includes:

- every byte source, all eight operations, counts 0 through 63, both X inputs, and both flag-update policies;
- word, long, and quad boundary values, discarded narrow-source bits, alternating patterns, and width/modulus boundaries;
- 8,192 reproducible random cases spanning all widths and operations;
- exact ordinary and ROX latencies;
- sixteen consecutive ordinary requests accepted without bubbles;
- atomic result/X publication, complete 64-bit allocation identity, stable backpressured response, published-response irrevocability, accept-time squash, second-pass squash, and wrong-thread squash isolation.

`m64k_shift_rotate_shared_checker.sv` binds seven external protocol properties in warning-fatal simulation. Production RTL contains no assertion switch, and synthesis excludes the checker rather than ignoring its properties.

## Structural result and rejection

All figures below were regenerated after `m64k_execute_tag_t.allocation_sequence` became 64 bits. Older 16-bit-tag figures are not comparable protocol baselines.

| Organization | Generic cells | Wire bits | Sequential cells | Interpretation |
|---|---:|---:|---:|---|
| Complete combinational semantic reference | 4,882 | 5,498 | 0 | Acceptance-plan reference |
| Ordinary fast path | 2,151 | 2,503 | 0 | Six ordinary operations only |
| Existing iterative ROX with current 64-bit tag | 3,035 | 3,359 | not used for selection | Separate-resource comparison |
| Separate fast plus iterative sum | 5,186 | 5,862 | not used as a monolithic netlist claim | Arithmetic sum under the same generic recipe |
| Unified shared candidate | 4,482 | 5,196 | 242 | Complete tagged candidate |

The shared candidate's arithmetic cell count is 704 (13.6 percent) below the current-tag sum of the separately synthesized fast and iterative blocks. That diagnostic is not a like-for-like integrated-area comparison: the ordinary fast block has no backend tag, response storage, or arbitration wrapper, while the shared candidate includes those structures. It therefore cannot establish an integrated area saving. The candidate reduces generic cells by only 400 (8.2 percent) relative to the conservative 4,882-cell acceptance reference. The documented early selection gate requires at least 20 percent reduction relative to that reference unless technology-mapped evidence justifies an exception. No such evidence exists, and the candidate also serializes ROX with ordinary shifts. Therefore this candidate is **not selected** and must not be described as the production organization.

The result remains useful negative design evidence: algebraic barrel reuse is functionally valid, but the present data does not prove an integrated area improvement, and its input steering, response storage, count reduction, and protocol control leave it short of the conservative selection gate. Any successor must retain this candidate's complete semantics and protocol verification while providing a measured improvement under identical synthesis and physical constraints.
