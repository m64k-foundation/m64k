# Outstanding micro-operation and completion contract

| Field | Value |
|---|---|
| Status | Normative first-product implementation contract; no RTL implementation claim |
| Version | 0.1-development |
| Scope | Per-core micro-operation membership, completion acceptance, and typed speculative-publication authorization |
| Compatibility | Microarchitectural and software-invisible; implements the M64K v1 first-product target without defining ISA behavior |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Boundary and ownership

This contract governs the outstanding micro-operations belonging to each live ROB allocation. It answers three questions: whether a returned `uop_index` was registered as a member of the allocation, whether that member is still awaiting its one terminal completion, and which typed result roles or condition-state fields that completion may publish into speculative backend state.

ROB lifetime validation remains an independent prerequisite defined by [rob-allocation-lifetime.md](rob-allocation-lifetime.md). A `rob_lifetime_match` proves only that core, hardware thread, ROB index, generation, and allocation sequence still identify the current slot occupant. It does not prove micro-operation membership. Conversely, membership never extends a ROB lifetime and cannot make a stale response valid.

Completion acceptance is not retirement authorization. This tracker MAY authorize a successfully completed result role to enter its preallocated speculative physical destination, but it MUST NOT select the oldest instruction, publish architectural state, commit stores, choose exception priority, release a ROB entry, or retire an instruction. The in-order per-thread ROB retirement machinery performs those operations only after independently checking completion, faults, memory ordering, and every other retirement condition.

The tracker is private to one core and shared by that core's two hardware threads. The first product has four cores, two hardware threads per core, 192 ROB entries per core, up to six uops registered or completed per cycle, up to four membership seals per cycle, and up to four instructions retired per cycle. Core and hardware-thread identities remain explicit even in a 1C1T verification projection. Nothing in this contract depends on an operating system, ABI, firmware, or workload.

## Identity and capacity

Every membership and completion operation carries the complete execution tag:

| Field | Width | Requirement |
|---|---:|---|
| `core_id` | 6 bits | MUST equal the instance's `local_core_id`; first-product values 0 through 3 are legal |
| `hardware_thread_id` | 2 bits | First-product values 0 and 1 are legal |
| `rob_index` | 8 bits | Values 0 through 191 address implemented entries; 192 through 255 are always rejected |
| `rob_generation` | 8 bits | MUST equal the current lifetime record |
| `allocation_sequence` | 64 bits | MUST equal the current lifetime record and obey the lifetime drain-before-rollover rule |
| `uop_index` | 4 bits | Selects one of at most 16 completion-bearing members within one ROB allocation |

The complete lifetime identity is `{core_id, hardware_thread_id, rob_index, rob_generation, allocation_sequence}`. The complete uop identity appends `uop_index`. No comparison may truncate, hash, or omit any of these fields. A hash may select a bank but can never establish equality.

Six registration lanes and six completion lanes are unordered sets. Two valid lanes in either set MUST NOT name the same complete uop identity. A conflict is a protocol violation, and every lane naming the conflict is rejected without changing that uop's state. Fixed lane priority is forbidden.

## Membership registration and sealing

A uop becomes a member only when a registration handshake is accepted after its ROB allocation is live and `rob_lifetime_match` is true. Registration records an immutable expected-completion manifest containing:

- a four-bit data-role mask for `LOW`, `HIGH`, `QUOTIENT`, and `REMAINDER`;
- whether the terminal success completion publishes `NZCV`;
- whether it publishes persistent `X`; and
- the exact set of versioned synchronous-fault classes that it is permitted to report instead of success.

The role mask contains no duplicate by construction. A uop that has neither a data result nor condition state is legal when it represents a control, ordering, or side-effect operation whose terminal completion is still required. A success response MUST exactly match the registered manifest; it may not omit an expected field or invent an unregistered one.

Membership for one ROB allocation is initially open. The lowering or dispatch owner MUST issue one successful `membership_seal` after every completion-bearing member has been registered. A seal carries the complete lifetime identity and may be accepted atomically with the allocation's final registrations. The combined pre-edge and accepted same-cycle membership must be nonempty, every registration conflict must be resolved before sealing, and `all_uops_complete` cannot observe the new seal until after the edge. Registration after sealing or duplicate sealing is a protocol violation. Cancellation and recovery may clear an unsealed allocation; an unsealed allocation can never report completion readiness for retirement.

`all_uops_complete` is true only when the lifetime matches, membership is sealed, at least one member exists, and every registered member has accepted exactly one terminal completion. It is completion evidence supplied to the ROB, not retirement authorization.

## Completion acceptance

Completion validation observes registered state at the beginning of the cycle. A same-cycle registration cannot accept a completion. A completion lane is accepted only when all of the following are true:

1. `rob_lifetime_match` is true for its complete lifetime identity;
2. the complete uop identity is a registered member of that lifetime;
3. the member is outstanding and has not already completed;
4. no other completion lane names the same uop in this cycle;
5. the allocation is not released or recovery-squashed in this cycle; and
6. its terminal payload is structurally and semantically valid against the registered manifest.

A successful completion carries each selected data role exactly once, carries `NZCV` exactly when registered, carries `X` exactly when registered, and carries no fault. The tracker emits speculative-publication authorization independently for every registered data role and condition-state field, atomically with completion acceptance. The destination mapping comes from trusted rename/ROB state indexed by the accepted uop identity and role; a response-supplied destination identifier can never redirect publication. A destination value remains transport data from the execution response; this tracker never synthesizes or substitutes a value.

A fault completion is legal only when its versioned fault class belongs to the member's registered allowed-fault-class set. It carries one typed synchronous-fault record and no data-role, `NZCV`, or `X` publication. Acceptance atomically marks that uop complete and records the fault indication for the ROB. Fault selection, exception priority, trap construction, restart state, and architectural delivery remain ROB and retirement responsibilities.

Any membership miss, already-completed member, lifetime miss presented as a completion, unexpected or duplicate role, missing expected role, condition-state mismatch, success-plus-fault payload, or unauthorized fault is rejected and reported as a protocol violation. Rejection cannot mark the uop complete and cannot authorize speculative publication. In particular, a second response for an already-completed uop is a duplicate completion even if every returned bit equals the first response.

## Release, recovery, and atomicity

An exact ordinary ROB release or a recovery invalidation clears every membership, completion, manifest, and seal-valid bit belonging to the selected allocation. Bulk identity or destination storage is don't-care while its corresponding valid bit is clear and MUST NOT be reset merely for simulation convenience.

Release and recovery dominate registration, sealing, completion, `all_uops_complete`, and every publication authorization in the same cycle. A squashed or released response is drained without any tracker state change or speculative publication. A fault completion and a squash can therefore never partially update different parts of the tracker.

Reset clears membership-valid, completion-valid, seal-valid, fault-valid, and protocol-status state. It does not require resetting identity, manifest, destination, or fault payload arrays whose validity has been cleared.

The tracker MUST NOT release or reuse a uop slot independently. A `uop_index` remains registered, whether outstanding or completed, until the enclosing ROB lifetime is released or recovered. This rule makes duplicate completion detectable for the entire allocation lifetime.

## Required protocol reporting

Warning-fatal simulation and formal verification MUST reject at least:

- a registration, seal, completion, or release context outside the instantiated core/thread topology;
- a ROB index from 192 through 255;
- registration, sealing, or completion without exact ROB lifetime match;
- duplicate registration or completion lanes in one cycle;
- registration of an already registered `uop_index` in the same lifetime;
- registration after sealing, duplicate sealing, or sealing an empty allocation;
- completion of an unregistered or already-completed uop;
- an unexpected, duplicate, or missing data role;
- unexpected or missing `NZCV` or `X` publication;
- a fault combined with any success publication, or a fault class outside the member's registered allowed set; and
- any state mutation or publication from an operation dominated by release or recovery.

These are implementation-integrity failures, not M64K architectural traps.

## Formal acceptance properties

A production implementation requires proofs for all of the following property classes:

- **Lifetime prerequisite:** no membership, completion, seal, or publication is accepted without exact ROB lifetime match.
- **Exact membership:** acceptance implies equality of every complete-uop-identity field and a registered member bit.
- **No duplicate completion:** one uop accepts at most one terminal completion during one ROB lifetime, including identical repeated responses and same-cycle duplicate lanes.
- **Manifest exactness:** every accepted success publishes exactly its registered role and condition-state set; every accepted fault publishes none of them.
- **Seal closure:** `all_uops_complete` is impossible before a nonempty membership set is sealed, and registration is impossible after sealing.
- **Atomic terminal event:** success publication or fault recording and the completed bit change together; no subset is visible alone.
- **Squash atomicity:** release or recovery suppresses every same-cycle acceptance, readiness indication, fault record, and publication, then clears the selected membership at the edge.
- **Sibling and core isolation:** changing only core or hardware-thread identity changes acceptance to rejection.
- **Unused-index rejection:** ROB indices 192 through 255 never access implemented storage or generate readiness/publication.
- **Noninterference:** activity for one complete uop identity cannot change another except when the enclosing allocation is explicitly released or recovered.
- **Reset hygiene:** reset exposes no member, completion, seal, fault, readiness, or publication without requiring payload-array reset values.
- **Retirement separation:** no tracker output alone can cause architectural publication, store commitment, exception delivery, or ROB release.

Mutation tests MUST demonstrate that removing the lifetime prerequisite, `uop_index` membership comparison, duplicate-completion state, manifest exactness, sealing requirement, fault/publication exclusion, or squash dominance breaks verification.

## Silicon and PPA hazards

A literal organization with 192 allocations times 16 uops, six registration ports, four seal ports, six completion read/modify/write ports, four retirement observation ports, and per-uop manifest storage can create excessive flop count, multiported mux depth, write fan-out, and routing congestion. It is not an accepted production organization merely because it simulates correctly.

Implementation candidates SHOULD evaluate a per-allocation 16-bit registered/completed bitmap with banked manifest storage, distributed completion collection close to execution clusters, and a single authoritative merge point. Banking may introduce explicit backpressure before acceptance, but the first product must sustain up to six accepted independent completions per cycle when they do not contend for a documented physical bank. A bank conflict cannot silently drop, prioritize, or merge responses.

The 64-bit allocation sequence is compared as correctness identity, not stored redundantly in every uop record when one authoritative per-allocation lifetime record can be referenced without creating a race. Likewise, data values SHOULD travel directly to the designated speculative destination rather than be copied into this tracker. Such sharing is valid only if formal equivalence proves that release, recovery, turnover, and response acceptance use one atomic lifetime view.

Production acceptance requires technology-mapped reports for sequential bits, comparator and mux cells, completion-to-publication timing, registration and recovery fan-out, clock power, congestion, and bank-conflict behavior. Formal proofs MUST cover all cycle semantics above with arbitrary backpressure and all six completion lanes active. Place-and-route diagnostics for setup, hold, slew, capacitance, antenna, congestion, and integrity remain fatal; no warning classification can replace correction of a physical defect.
