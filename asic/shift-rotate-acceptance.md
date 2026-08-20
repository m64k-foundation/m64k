# Shift/rotate production acceptance plan

## Purpose and current status

The combinational `m64k_shift_rotate` unit is the executable RTL reference for the M64K v1 scalar shift and rotate contract. It is not the production organization. Its generic Yosys baseline contains 4,882 primitive cells, including 1,857 multiplexers, while the scalar integer ALU baseline contains 1,687 primitive cells after fail-closed illegal-operation handling. These counts are reproducible structural evidence, not standard-cell area, timing, power, or physical-design evidence.

The reference computes separate 64-bit left-shift, right-shift, ordinary-rotate, and ASL-overflow mask networks. It also computes the 9-, 17-, 33-, and 65-bit rotate-through-X rings in parallel before selecting one operand width. This organization is useful for independent semantic verification but has an avoidable replication risk in a four-wide out-of-order core.

The first ordinary-operation candidate, `m64k_shift_rotate_fast`, has now been synthesized and formally compared with the reference. Under the same generic Yosys recipe it contains 2,151 primitive cells, 476 multiplexers, and 2,503 wire bits. Relative to the complete reference this is a 55.9 percent cell reduction, a 74.4 percent multiplexer reduction, and a 54.5 percent wire-bit reduction. The SAT miter imports the generated candidate netlist, not merely its pre-synthesis RTL.

These reductions are encouraging but are not a like-for-like complete shift/rotate result. The 2,255-cell candidate implements only `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, and `ROR`; it excludes `ROXL`, `ROXR`, the persistent-X interface, iterative state, tags, pipeline registers, response arbitration, and flush control. The complete selected organization cannot be compared with the 4,882-cell reference until one ROX path and its integration logic are included. Generic primitive counts also remain neither standard-cell area nor timing evidence.

The initial production study must compare at least these organizations:

1. One throughput-one 64-bit fast path for `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, and `ROR`, plus one tagged iterative rotate-through-X unit.
2. The same 64-bit fast path plus one fixed-latency, operand-width-configurable 65-bit rotate-through-X network.
3. The existing combinational reference as the semantic and PPA baseline, never as an automatically selected winner.

Four-wide decode and retirement do not require four shift pipes. The initial core budget is one fully pipelined ordinary shift/rotate pipe and one shared rotate-through-X resource per core. A second ordinary pipe requires workload evidence showing that the first pipe causes a material IPC loss.

## Equivalence obligations

Correctness gates are mandatory and cannot be traded for PPA.

### Reference RTL to generated netlist

`make asic-native-shift-netlist-equiv` regenerates the generic netlist and proves exact combinational equivalence with Yosys `equiv_make`, `equiv_simple`, and `equiv_status -assert`. The proof covers every value of `source`, the low-six-bit count, all four operand sizes, all eight operations, `extend_in`, and `update_flags`. It compares every output bit, including outputs whose validity signal is clear, because synthesis must preserve the complete RTL interface.

This proof is available now in the immutable ASIC container and uses the Yosys internal SAT engine. It is a synthesis-integrity gate; it does not prove that the reference itself implements the architectural contract.

### Combinational candidate to reference

A fixed-latency combinational candidate must be compared directly with the reference before it can replace the reference module. The formal harness must constrain operation and size only if a candidate intentionally exposes a narrower sub-unit interface. It must otherwise cover the complete input space.

Architectural comparison is validity-aware:

- `result_valid` must match, and `result` must match whenever it is asserted;
- `flags_valid` must match, and `negative`, `zero`, `overflow`, and `carry` must match whenever it is asserted;
- `extend_valid` must match, and `extend_out` must match whenever it is asserted;
- a drop-in implementation retaining the current module interface must additionally pass exact output equivalence so that no undocumented don't-care behavior is introduced.

The candidate proof must fail closed on an unproven cell, timeout, unsupported construct, warning, or vacuous constraint. Proof logs and the source, harness, tool-image, and command hashes are result inputs.

`make asic-native-shift-fast-equiv` implements the first candidate gate. It regenerates `m64k_shift_rotate_fast`, imports that synthesized netlist alongside the complete reference RTL, flattens a dedicated combinational miter, and asks the Yosys MiniSAT engine to prove `miter_pass=1` for every defined primary-input combination. The miter defines the supported set independently as operation values zero through five and proves the candidate's `operation_supported` output agrees with that set for all eight operation values. For the supported set it proves exact equality of result, result validity, flag validity, and all `N`, `Z`, `V`, and `C` values. Flag values are compared even when flag validity is clear, making the proof stronger than a validity-masked architectural comparison. For `ROXL` and `ROXR`, it proves that support, result-valid, and flags-valid are clear and that result and every flag output are zero; unsupported requests therefore cannot expose a stale or data-dependent value.

The fast candidate intentionally has no extend input or output, so the miter does not invent or compare candidate X signals. Instead, for every supported operation and arbitrary `extend_in`, it separately proves that the complete reference returns `extend_out=extend_in` with `extend_valid=0`. The current proof completed with no counterexample after importing 3,042 flattened cells into 164,034 SAT variables and 446,520 clauses. The generated `equivalence.json` records the proven result and hashes the immutable tool image, flow recipe, reference and candidate manifests, every source, generated candidate netlist, miter, and proof log. This is reproducible formal evidence for the six-operation generic netlist and its explicit rejection behavior, not evidence for ROX execution, physical timing, or the final combined organization.

### Iterative rotate-through-X candidate

Latency-changing logic requires transaction-trace equivalence, not a combinational miter. The harness must capture the reference result when a request is accepted and prove that the iterative unit returns the same result, flags, and X value under its documented latency and backpressure contract. It must also prove:

- exactly one response for each accepted, non-squashed request and no unsolicited response;
- stable response data while backpressured;
- bounded forward progress under an explicit fairness assumption for response acceptance;
- atomic publication of the GPR result and persistent X result;
- no intermediate X update and no state leak after squash, reset, or tag reuse;
- isolation by core, hardware-thread, and transaction tag;
- count-zero behavior and exact modulo-9, modulo-17, modulo-33, and modulo-65 boundaries;
- correct behavior for consecutive dependent ROX operations and independent interleaved threads.

The pinned container currently provides SymbiYosys 0.67 and the Yosys internal SAT engine, but no external SMT solver is present. Bounded single-clock properties can be automated with `sat -seq` now. An unbounded or induction-based sequential closure claim requires a separately pinned solver or a reviewed ABC/Yosys proof engine, explicit reset assumptions, proof-depth justification, and cover evidence that requests reach every execution stage. The absence of a solver must never be converted into a skipped-success result.

## Functional verification matrix

Every candidate must retain the existing model and RTL tests and add candidate-specific differential tests. Required coverage includes:

- exhaustive byte operands, counts 0 through 63, all operations, both X inputs, and both flag-update states;
- directed word, long, and quad values around zero, one, all ones, minimum signed, maximum signed, and alternating bits; all-input formal equivalence must cover every single-bit position without expanding those cases into separately generated Verilator code;
- counts zero, one, `W-1`, `W`, `W+1`, 32, 33, 63, and every rotate-through-X modulus boundary;
- ASL overflow cases covering all leading-sign-run lengths;
- result, carry, overflow, negative, zero, X, and every validity signal;
- randomized differential traces with reproducible seeds;
- negative tests demonstrating that a deliberately mutated result, carry, X, flag-valid, or flush behavior fails the corresponding proof.

## PPA comparison protocol

All compared organizations must use the same RTL revision, tool-image digest, source policy, synthesis recipe, standard-cell library, PVT corner, operating voltage, wire model, constraints, clock uncertainty, input/output delays, maximum transition, maximum capacitance, fan-out limits, physical utilization target, floorplan assumptions, macro set, activity source, and placement seed. Reports must hash those inputs.

Generic Yosys results are early structural triage. Record total cells, cell classes, mux count, wire bits, and topological depth, but do not assign physical units or derive Fmax from them. The production comparison requires technology mapping and STA. Once a sequential execution partition exists, it also requires placed-and-routed area, buffer/inverter count, congestion, routed wire length, worst and total negative slack, critical-path ownership, leakage, and activity-based dynamic power.

Evaluate both the isolated unit and the intended one-pipe-per-core integration. Include issue selection, operand muxing, bypass, pipeline registers, iterative state, result arbitration, tag storage, clock load, and flush wiring. Removing datapath cells while increasing global wakeup, bypass, or control cost is not a demonstrated core-level improvement.

## Acceptance gates

The following gates select the production organization:

1. All architectural, differential, formal, warning, and RTL-to-netlist checks pass with no waiver affecting width, signedness, latches, bounds, clocks, reset, or protocol behavior.
2. The ordinary fast path accepts one request per cycle. Its latency and bypass contract are fixed before backend integration.
3. Rotate-through-X has a documented finite worst-case latency and cannot block unrelated ordinary shifts indefinitely. The initial staged-iterative target is at most six execution stages after acceptance, excluding externally imposed response backpressure.
4. As an early sanity threshold, the complete selected shift/rotate organization should reduce generic cells by at least 20 percent relative to the 4,882-cell reference. Missing this threshold does not prove failure, but requires technology-mapped evidence explaining why the candidate remains preferable.
5. Under one identical exploratory library and SDC, the selected organization must reduce total mapped area by at least 15 percent without worsening the ordinary fast-path setup slack or throughput. A smaller area gain requires a measured dynamic-power or representative-workload performance benefit large enough to justify the added control and verification cost.
6. At core level, representative traces must show no more than a one-percent IPC loss relative to a two-shift-pipe sensitivity configuration before the design commits to one ordinary pipe. This is a later performance gate, not a claim about the current RTL.
7. Final acceptance requires the selected foundry libraries and multi-corner sign-off flow. Nangate45, Sky130, and the public ORFS image remain comparative exploration evidence only.

No single metric wins automatically. Equivalence is absolute; timing must meet the core contract; area and power improvements must survive integration; and workload performance determines whether a rarer operation merits a dedicated direct datapath.
