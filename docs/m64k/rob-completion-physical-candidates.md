# ROB lifetime and completion physical-organization candidates

| Field | Value |
|---|---|
| Status | Decision study; no RTL, PPA closure, or production-selection claim |
| Version | 0.1-development |
| Scope | Per-core ROB-192 lifetime validation and outstanding-uop completion organization for the first product |
| Normative inputs | [rob-allocation-lifetime.md](rob-allocation-lifetime.md), [outstanding-uop-completion.md](outstanding-uop-completion.md), and [first-product-target.md](first-product-target.md) |

## Purpose and fixed behavior

This study narrows the physical design space before RTL is committed. It does not change either normative contract. Every candidate must implement one per-core structure shared by two hardware threads, four allocations, four exact releases, six registrations, six terminal completions, four membership seals, four retirement observations, and a single-cycle 192-bit recovery invalidation. A completion is never architectural retirement.

All candidates compare the complete lifetime identity. The ROB index selects storage, while the stored identity is the two-bit hardware-thread identifier, eight-bit generation, and 64-bit allocation sequence. The request's six-bit core identifier is also compared against the local core identifier. Neither a bank selector nor a hash proves equality. `uop_index` is validated separately against registered and completed membership for the exactly matched lifetime.

Release and recovery dominate every same-cycle match and update. A same-cycle allocation is not visible to validation. An accepted response must pass lifetime, membership, duplicate, manifest, and squash checks before it can update a completed bit, record a fault, or authorize typed speculative publication. Pipeline registers may delay that decision, but they may not redefine it.

## Storage lower bounds

These counts describe logical state, not a cell-area estimate. Clock enables, ECC, parity, protocol reporting, fault payloads, destination mappings, ROB instruction payloads, and implementation padding are excluded.

| State | Logical bits per core | Derivation |
|---|---:|---|
| Lifetime identity | 14,208 | 192 entries x (2 thread + 8 generation + 64 sequence) |
| Lifetime live state | 192 | One bit per ROB entry |
| Registered-uop bitmap | 3,072 | 192 x 16 |
| Completed-uop bitmap | 3,072 | 192 x 16 |
| Membership seal | 192 | One bit per ROB entry |
| Base manifest, excluding allowed-fault set | 18,432 | 192 x 16 x (4 roles + `NZCV` + `X`) |
| Allowed-fault-class set | `3,072F` | `F` bits per uop for the versioned fault-class universe |

The lifetime table therefore has a 14,400-bit logical minimum. The tracker adds at least `24,768 + 3,072F` bits, before fault records and protocol state. The combined lower bound is `39,168 + 3,072F` bits. The allowed-fault-class width must be frozen by its versioned contract before an SRAM aspect ratio or final area can be claimed.

Six complete copies of the 14,400-bit lifetime image would contain 86,400 bits. A separate authoritative copy plus six read replicas would contain 100,800 bits. Replication also broadcasts up to four allocations, four releases, and 192 recovery decisions to every copy, so its cost is not captured by bit count alone.

## Candidate comparison

| Candidate | Lifetime validation | Completion state | Principal benefit | Principal risk |
|---|---|---|---|---|
| A. Monolithic flop arrays | Six asynchronous indexed reads from one 192-entry image | Flop bitmaps and dense flop manifests | Direct reference implementation with no physical bank conflicts | Six wide 192-entry read cones, six read/modify/write completion paths, and global recovery/update routing |
| B. Replicated read identity | One complete identity image per validation lane; one authoritative update view | Shared flop or banked completion state | Six conflict-free identity reads | 86,400 to 100,800 lifetime bits and high allocation/release/recovery write fan-out |
| C. Banked flop lifetime and collector | Requests steer to indexed banks; local row read and exact compare; explicit conflict admission | Per-bank registered/completed bitmaps with local merge | Local wiring, no identity replication, and recovery naturally partitions by ROB index | Bank arbitration, response queues, and cross-bank routing become correctness- and timing-critical |
| D. Banked flop control plus SRAM manifests | Flop lifetime/live/registered/completed/seal state; immutable manifests in banked SRAM | Completion collector reads a manifest only after exact lifetime and membership checks | Avoids resetting payload storage and targets the largest dense array at SRAM | Commodity macros cannot provide six arbitrary reads and six writes; banking and replicas remain necessary |

### Candidate A: monolithic flop arrays

A literal implementation is valuable as a formal and synthesis reference, but it is not the presumed production topology. Each of six validation lanes selects 74 stored identity bits from 192 rows, performs an 80-bit exact ownership comparison when the local-core comparison is included, and applies range, live, release, and recovery qualification. Decomposing each 192:1 selection into binary two-input muxes gives 191 one-bit mux nodes per selected bit, or 84,804 nodes across 74 bits and six lanes before synthesis sharing and optimization. This number is a topology indicator, not a standard-cell count.

The same problem recurs in the 16-bit membership and completion maps. Six completions can target six different rows, or six different uops in one row. A correct reference must merge all accepted updates without fixed lane priority and must reject every lane in an exact duplicate pair. A behavioral array with multiple nonblocking assignments is not evidence that this merge will synthesize correctly or efficiently.

### Candidate B: replicated read identity

Replication removes identity read-port contention, but every allocation must write all replicas and every release or recovery must make stale identity unmatchable in every lane. Replicating only identity while keeping one authoritative live bitmap avoids clearing replicated payload on recovery, but then each lane still needs an exact view of authoritative live, release, and recovery state. Replicating live state makes validation local at the cost of 1,152 live bits and six copies of the recovery clear network.

This candidate is retained for measured comparison because 74-bit equality is regular and local after replication. It is not the recommended first candidate: the bit multiplication is known before synthesis, and update/recovery fan-out grows in precisely the structures that must close under four-wide turnover and single-cycle recovery.

### Candidate C: banked flop lifetime and completion collector

Use a power-of-two bank count selected by low ROB-index bits and a row selected by the remaining in-range index bits. Eight banks contain 24 implemented entries each; sixteen banks contain 12. Indices 192 through 255 are rejected before bank storage is enabled. Four- and eight-bank variants remain useful comparison points, but eight and sixteen banks are the principal experiments because they can accept six completions in one cycle when those completions select distinct banks.

Each bank owns its lifetime live bits, 74-bit identities, registered/completed maps, seal bits, and local recovery slice. The 192-bit recovery mask is physically partitioned: each bit directly controls only the state of its own entry. Clearing registered and completed maps gives one recovery bit at least 32 local state-bit loads; manifests and other payload arrays remain untouched because their validity disappeared. Recovery must not be broadcast through an unbounded global combinational decoder.

The collector first performs range and bank routing, then local row selection, then the full sequence, generation, and thread comparison. The 64-bit sequence comparator belongs beside the selected bank row, not before the 192-entry selection and not in a global broadcast cone. Core equality is common to all lanes and may be computed once, but the result must remain a correctness input to every lane.

Distinct completion lanes targeting the same bank require an explicit policy:

- completions for different uops of the same exact ROB allocation may be merged into one 16-bit completed-map update after duplicate rejection and manifest validation;
- exact duplicate uop identities reject every duplicate lane;
- completions for different rows in one single-update bank are admitted through a fair, lane-order-independent arbiter and lossless input queues; and
- a non-admitted response is backpressured before execution-unit response handoff, never accepted and then discarded.

The bank conflict policy is microarchitectural and may change after measurement. It must sustain all six completions when they select six distinct banks. Persistent conflict requires a proved bounded-fair service rule; fixed lane priority is forbidden. Registration uses the same rules, except that a registration can never complete in its acceptance cycle. Four retirement observations may use dedicated narrow bitmap reads, replicated seal/readiness summaries, or queued bank access; no candidate may silently reduce the four-retire target.

### Candidate D: SRAM-backed immutable manifests

The manifest address is `{rob_index, uop_index}` and the base payload is `6 + F` bits. A dense organization contains 3,072 words. It is a plausible SRAM target because a manifest is written once during open membership and is don't-care after enclosing-lifetime invalidation. Recovery therefore clears only flop validity bitmaps and does not perform 16 manifest writes per recovered ROB entry.

It is not plausible as one conventional macro: the contract permits six registrations and six completions per cycle, while commonly available synthesizable SRAM contracts provide one or two ports. A candidate must bank manifests, replicate read-only data after registration, add lossless request queues, or combine these methods. Same-bank registration and completion to different addresses cannot be assumed to work. A same-cycle registration cannot satisfy a completion even if a macro is configured write-first.

SRAM feasibility is conditional on an actual macro catalog. Required experiments must report macro count, aspect ratio, unused words, banking conflicts, read latency, write mask, read-during-write mode, BIST ports, repair/ECC policy, and routing around the macros. Until those data exist, inferred memories are an exploration mechanism rather than production evidence.

## Exact comparison and pipeline placement

Two timing classes must be measured separately.

In the combinational class, an execution response remains upstream until range, bank admission, lifetime equality, membership, completed state, duplicate status, manifest exactness, and release/recovery dominance are known. This minimizes latency but places the sequence comparator and publication authorization in the response-ready path.

In the registered-validation class, lossless per-bank ingress queues capture the complete immutable response. Capture is transport acceptance only; it is not terminal-completion acceptance and cannot authorize publication. During a later validation stage, the queued tag reads the current authoritative lifetime and completion state. A release, recovery, or turnover occurring before that stage therefore causes a miss or dominates the operation. The response is marked terminally accepted only after the complete check, and publication plus completed/fault state changes atomically at that boundary.

Registering only the low index while discarding or recomputing the full identity is forbidden. Speculatively writing a destination before validation and attempting to undo it is also forbidden. If validation and publication are separated by another register, the intervening token must retain the exact lifetime and reserve the affected completion state so that a duplicate cannot pass concurrently.

Registered validation is the preferred timing hypothesis because it removes the execution-unit response path from the 64-bit sequence comparison and bank update decision. It is not selected by assertion: both timing classes require identical physical experiments, and the registered class must prove that queueing, recovery, and turnover preserve the normative cycle semantics.

## Identical synthesis and STA experiments

Every implementation candidate must expose the same complete transaction interface and implement the same accepted-operation trace. Candidate comparison uses the following controlled matrix:

1. Build monolithic, six-replica, 4-bank, 8-bank, and 16-bank flop organizations with identical tag widths, ROB/uop capacities, protocol outputs, input/output register boundaries, reset policy, and fault-class parameter. Compare combinational and registered-validation classes separately; do not compare unequal pipeline boundaries as though they were the same experiment.
2. Elaborate and lint every candidate warning-fatal with the project's pinned SystemVerilog frontend. Run identical generic synthesis scripts and the same technology mapping, hierarchy flattening policy, optimization effort, and clock-gating policy.
3. Run the same PDK, standard-cell libraries and corners, clock-period sweep, input/output delays, clock uncertainty, transition and load constraints, floorplan utilization, PDN, placement seed set, routing layers, and extraction setup. Constraint or tool changes invalidate cross-candidate comparisons.
4. Apply identical worst-case traffic constraints: all six completion lanes active, four allocations, four releases, four seals, four retirement observations, arbitrary bank conflicts, a dense recovery mask, and simultaneous sibling-thread activity. Report steady-state throughput and conflict latency from measured traces, not a uniform-random estimate alone.
5. Report logical and mapped sequential bits, clock-gating cells, combinational area by function, mux and comparator cells, maximum fan-out, recovery and allocation net loads, worst setup and hold paths, Fmax, dynamic and leakage power, congestion, wirelength, buffer count, slew/capacitance violations, and per-bank queue occupancy. Every enabled diagnostic remains fatal.
6. For the SRAM hybrid, hold external constraints constant and report both an inferred-memory run and a macro-bound run. The macro-bound result must include macro leakage, clock/interface power, blockage and halo policy, repair/BIST impact, and all timing arcs.

Power activity must include idle, sustained six-completion, four-allocation/four-retire, recovery-heavy, and adversarial same-bank cases. The same deterministic traces and toggle annotation are used for every candidate. Area or Fmax without these workload classes is insufficient for selection.

## Formal and verification gates

Before PPA can select a candidate, each organization must pass the following gates against one executable abstract contract model whose algorithm and storage topology are independent of every candidate:

- cycle-by-cycle accepted-operation and protocol-violation trace equivalence, including all lane permutations;
- exact lifetime and uop equality with no hash or truncated sequence comparison;
- release/recovery dominance, same-cycle turnover, stale response, unused index, and sibling/core isolation properties;
- atomic completion, publication, and fault recording, with no state change for rejected or backpressured lanes;
- exact duplicate rejection for all duplicate-lane subsets and no false conflict between distinct complete identities;
- registration/seal closure, same-cycle final registration plus seal, no same-cycle registration/completion, and duplicate-completion persistence until enclosing release;
- six-lane noninterference and covers for six accepted distinct-bank completions, six distinct-uop completions merged into one allocation, and four simultaneous retire observations;
- losslessness, bounded occupancy, and bounded fairness for every bank queue and arbiter under legal backpressure;
- recovery of every subset of the 192 entries, including all entries, without clearing payload storage as a functional requirement;
- sequence-rollover drain interlock and mutation tests that remove sequence bits, release suppression, recovery dominance, membership, completed state, manifest fields, or duplicate detection; and
- reset hygiene without reset assumptions on identity or manifest payload arrays.

Formal proofs must include the full widths and 192-entry bounds for identity and range safety. Reduced-capacity proofs may accelerate iteration but cannot replace the product-parameter proof. Any abstraction of the 64-bit sequence comparator requires a separate equivalence proof to the full-width equality used in RTL.

## First RTL recommendation

The justified first RTL candidate is an **eight-bank flop-based lifetime and completion-control structure with registered, lossless per-bank validation queues, local exact 64-bit sequence comparison, merge of distinct uops targeting the same exact allocation, and immutable manifest storage behind an explicit wrapper**. For the first implementation, the wrapper may bind manifests to flops so the complete behavior can be linted, simulated, formally proved, and synthesized without assuming a foundry macro. It must implement every conflict, recovery, fault, and retirement-observation rule; it is not a stub.

This recommendation is narrower than a production selection. Eight banks preserve six-per-cycle throughput for six distinct banks, make four adjacent ROB indices naturally select four distinct banks, partition the recovery network, and avoid the known 6x lifetime-storage penalty. Registered validation isolates the wide identity comparison from execution response timing and provides an explicit place for fair conflict handling. These are structural reasons sufficient to choose the first candidate for RTL and measurement, but they are not PPA closure.

The 16-bank variant, monolithic reference, and six-replica identity variant remain mandatory comparison points. SRAM-backed manifests become eligible only after `F` and the manifest encoding are frozen and a real macro contract is available. The production topology is selected only if formal trace equivalence passes and identical post-route experiments show acceptable timing, area, power, congestion, recovery fan-out, and sustained/adversarial completion behavior with no waived physical diagnostic.
