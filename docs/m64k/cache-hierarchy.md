# M64K first-product cache hierarchy

| Field | Value |
|---|---|
| Status | Normative implementation profile draft |
| Version | 0.1-development |
| Scope | First-product private L1/L2 and shared L3 organization |
| Compatibility | Caches preserve M64K v1 results and are transparent except for maintenance, discovery, and performance |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Reference geometry

| Level | Organization | Capacity | Associativity | Line |
|---|---|---:|---:|---:|
| L1I | Private per core | 32 KiB | 8-way | 64 B |
| L1D | Private per core | 32 KiB | 8-way | 64 B |
| L2 | Unified, private per core | 512 KiB | 8-way | 64 B |
| L3 | Unified, shared by four cores | 4 MiB | 8-way, 8 banks | 64 B |

These values define the first-product implementation target. Capacity and associativity are discoverable implementation parameters, but line size, coherence, maintenance, ECC reporting, and software-visible behavior remain identical. Performance targets such as a three- or four-cycle L1 load-to-use latency are goals, not architectural guarantees.

## Inclusion and coherence

L2 and L3 are non-inclusive. Evicting an L3 data copy MUST NOT invalidate a valid private copy. The L3 home directory remains authoritative for private ownership and sharers even when the L3 data array does not contain the line. Each directory entry identifies an exclusive owner or a four-bit core sharer set; the owning core endpoint resolves its two SMT requesters.

The coherence protocol is MESI: its only stable states are Modified, Exclusive, Shared, and Invalid. Transient states may sequence interventions, invalidations, fills, and writeback races but do not add a fifth stable state. A requester receives writable ownership only after all required invalidation acknowledgements. Dirty data is never discarded on replacement or error recovery.

Addresses are hashed across eight L3 banks using documented physical line-address bits so sequential traffic uses all banks. The hash MUST NOT change across reset for one implementation revision and MUST preserve one home per physical line.

## Non-blocking behavior

All levels are non-blocking. Translation and the core-side client terminate virtual `ASID` and privilege metadata before issuing a coherent physical request. The coherent fabric carries physical address, request identity, core/thread source, transaction, byte mask, memory type, ordering class, and fault-routing metadata; it MUST NOT carry `ASID` or architectural privilege as coherence lookup state. MSHRs and writeback queues MUST backpressure before identity or data can be lost. Prefetch requests are lowest priority, cannot allocate the last demand resource, cannot create architectural faults, and are dropped at forbidden or device mappings.

The initial policy permits next-line instruction prefetch in L1I and conservative stream/stride prefetch in L2. L3 prefetch is disabled in the reference configuration. All prefetchers are discoverable, controllable by machine privilege, and measured independently before enablement.

## Reliability and test

Data arrays use SECDED ECC. Tag and directory arrays use parity or SECDED strong enough to prevent silent misrouting or ownership loss. Correctable events increment per-level counters and MAY raise a threshold interrupt. Uncorrectable data is poisoned and reported as a precise access fault when attributable to an unretired request, otherwise as a machine check. Background scrub never changes architectural ordering.

Each sizeable array uses the project memory wrapper with explicit latency, ports, byte masks, read-during-write behavior, ECC, scrub, and MBIST access. Functional reset MUST invalidate metadata without resetting bulk data storage. Clock gating, SRAM binding, scan bypass, and MBIST controls remain outside the architectural datapath.

## Maintenance and QoS

The first product supplies scoped clean, invalidate, and clean-invalidate operations by address and by implementation-defined range. Completion includes all affected private levels, directory transitions, required writeback, and instruction-side acknowledgement. Maintenance obeys privilege and memory ordering; it cannot silently operate on a device mapping.

The L3 SHOULD support per-core allocation limits and fair bank arbitration. QoS affects replacement and scheduling only; it MUST NOT weaken coherence, TSO, exception precision, or eventual progress. Counters include hit/miss, eviction, intervention, retry, MSHR occupancy, prefetch usefulness, ECC, bank conflict, and per-core/thread attribution where practical.
