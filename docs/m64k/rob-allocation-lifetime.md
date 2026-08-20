# ROB allocation-lifetime validation contract

| Field | Value |
|---|---|
| Status | Normative first-product implementation contract; no ROB implementation claim |
| Version | 0.1-development |
| Scope | Per-core ROB-slot lifetime ownership and stale-completion rejection |
| Compatibility | Microarchitectural and software-invisible; implements the M64K v1 first-product target without defining ISA behavior |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Boundary and non-claims

The allocation-lifetime table establishes whether an execution response still refers to the current occupant of one of the 192 ROB indices owned by a core. It is not a ROB payload array and does not implement instruction ordering, branch checkpoints, exception priority, destination readiness, physical-register writeback, duplicate-completion detection, store visibility, or retirement. A successful lifetime match is necessary but insufficient authorization for any state update.

The table is shared by the two hardware threads of one core. Its externally supplied `local_core_id` identifies that core. A live entry stores hardware-thread identity, ROB generation, and allocation sequence. The ROB index addresses the entry and is not stored. Core identity MUST compare equal to `local_core_id` on allocation, release, recovery, and validation; an out-of-range index from 192 through 255 never denotes storage.

`uop_index` is deliberately outside this primitive's stored identity. All micro-operations belonging to one ROB allocation share its ROB lifetime, while a separate outstanding-uop/completion tracker MUST validate micro-operation membership, reject duplicate responses, and authorize destination-role writeback. Calling the output `tag_valid` would therefore be misleading; the output is `rob_lifetime_match`.

## Capacity and ports

One instance contains exactly 192 live bits and 192 stored lifetime identities. It accepts at most four allocations and four ordinary releases per cycle and evaluates six independent combinational validation requests per cycle. A 192-bit recovery invalidation mask is a required input because four ordinary release ports cannot provide bounded single-cycle speculative-tail recovery. The component MUST NOT be presented as production-ready if recovery is implemented by walking the table over as many as 48 cycles.

Allocation and ordinary release lanes are unordered sets. Two valid allocation lanes MUST NOT name the same index. Two valid release lanes MUST NOT name the same index. A malformed set raises a protocol violation and MUST NOT modify the conflicting index. Fixed lane priority is forbidden because it can hide an allocator defect and make behavior depend on lane placement.

## Stored lifetime identity

The first-product stored identity is:

| Field | Width | Purpose |
|---|---:|---|
| `hardware_thread_id` | Architectural context width | Prevents one sibling thread from claiming another sibling's shared ROB slot |
| `rob_generation` | 8 bits | Diagnoses and distinguishes local slot reuse |
| `allocation_sequence` | 64 bits | Distinguishes allocation lifetimes across the core |

The allocation sequence MUST NOT be reused while any request, queue entry, pipeline stage, response, replay record, squash record, or verification-visible copy containing the older value can exist. Sequence rollover requires an allocation stop followed by a proved drain of every tagged structure in the core before zero is issued again. Natural modulo rollover without this quiescence protocol is forbidden.

The existing 16-bit allocation-sequence type is consequently not sufficient for a production implementation. At a four-allocation-per-cycle peak it would require a disruptive whole-core drain every 16,384 cycles. Widening the field reduces rollover frequency but does not remove the required correctness protocol. The rollover rule remains mandatory even with 64 bits.

Generation MUST advance modulo 256 whenever an index is reallocated after release. Correctness does not rely on generation alone: allocation sequence and thread identity participate in every match. An allocation that recreates the complete released lifetime identity is rejected.

## Cycle semantics

Validation is combinational over current registered state. A validation lane reports `rob_lifetime_match` only when all of the following are true:

1. its core identity equals `local_core_id`;
2. its ROB index is less than 192;
3. the addressed entry is live;
4. stored thread, generation, and allocation sequence equal the response fields;
5. the index is not named by a successful ordinary release in this cycle; and
6. the corresponding recovery-invalidation-mask bit is clear.

Same-cycle allocation never creates a combinational match. A unit cannot produce a response for work that has not yet crossed the allocation clock edge. Suppressing release- and recovery-invalidated matches prevents a late or duplicate completion from causing a wakeup during the cycle that destroys its ownership.

An ordinary release succeeds only for an in-range, live entry whose complete stored lifetime identity matches the release request. A stale or cross-thread release raises a protocol violation and leaves state unchanged. Release is used for normal retirement or for individually identified cancellation; it does not replace recovery invalidation.

Allocation succeeds for an in-range request belonging to `local_core_id` when the entry is free, or when exactly one successful matching ordinary release frees that entry in the same cycle. Release-and-reallocate turnover commits the new identity at the edge. Validation during that cycle matches neither the released lifetime nor the not-yet-allocated lifetime. An index selected by recovery invalidation MUST NOT be allocated in the same cycle.

Recovery invalidation clears every selected live bit at the edge regardless of its stored identity. The mask MUST be generated by reviewed ROB recovery logic from a checkpoint or precise-trap boundary. This primitive does not calculate the mask and does not establish whether the selected set is architecturally correct.

Reset clears only the 192 live bits and protocol status. Identity storage is don't-care while its live bit is clear and MUST NOT be reset merely for simulation convenience.

## Required protocol reporting

The component MUST report, and warning-fatal verification MUST reject, at least:

- out-of-range allocation or release indices;
- core or hardware-thread identities outside the instantiated product topology;
- duplicate allocation indices or duplicate release indices within one cycle;
- release of a free entry;
- release identity mismatch;
- allocation over a live entry without an exact same-cycle release;
- allocation of a recovery-invalidated index;
- reuse of the complete released lifetime identity; and
- allocation-sequence rollover without completed tagged-fabric quiescence.

These are internal protocol violations, not M64K architectural traps. Production handling belongs to the core's implementation-integrity policy; simulation and formal verification MUST make them fatal.

## Formal acceptance properties

A production implementation requires proofs of the following property classes rather than directed tests alone:

- **No stale alias:** after a release or recovery invalidates lifetime `A`, no validation carrying `A` matches until a legally quiesced reuse of that complete identity.
- **Exact ownership:** a match implies live state and equality of core, thread, index, generation, and allocation sequence.
- **Sibling isolation:** changing only hardware-thread identity changes a match to a miss.
- **Core isolation:** changing only core identity changes a match to a miss.
- **Unused-index rejection:** indices 192 through 255 never read, write, clear, or match implemented storage.
- **No partial conflict update:** duplicate or otherwise malformed lane sets leave every involved index unchanged.
- **Atomic turnover:** exact release plus distinct reallocation changes old ownership to new ownership at one edge, with neither identity matching combinationally during that edge's input cycle.
- **Recovery dominance:** every mask bit suppresses same-cycle matches and clears the corresponding live state; allocation cannot override it.
- **Noninterference:** activity at one index does not change any other index except indices independently named by valid lanes or recovery mask bits.
- **Reset hygiene:** reset produces no live entry without requiring identity-array reset values.
- **Wrap safety:** sequence reuse is unreachable unless allocation is stopped and all tagged holders have acknowledged drain.

Mutation tests MUST demonstrate that removing thread comparison, core comparison, the 192-entry bounds check, release-time match suppression, recovery dominance, or rollover interlock breaks verification.

## PPA and implementation hazards

A literal 192-entry table with six asynchronous reads, eight possible update lanes, a 64-bit sequence comparator on every validation lane, and a 192-bit recovery clear path is not assumed to map efficiently to an SRAM macro. Six replicated copies would multiply stored bits and write fan-out; a monolithic flop array can create large 192:1 read muxes, reset fan-out, and a validation critical path; a CAM is worse.

Physical candidates SHOULD compare at least banked flop storage, replicated read-only identity banks with a single authoritative live/update bank, and validation integrated into banked completion collection. Every candidate must preserve six accepted completion validations per cycle or expose reviewed bank-conflict backpressure upstream. Hashes or truncated tags are forbidden because collision would make stale completion architecturally visible.

The first implementation MUST report post-synthesis mux count, sequential bits, maximum update fan-out, recovery-mask fan-out, and validation-path timing. Place-and-route experiments MUST use identical constraints and must not waive congestion, slew, capacitance, setup, or hold diagnostics. PPA evidence may change the physical organization or add a registered validation stage, but it cannot weaken the lifetime identity or recovery semantics.
