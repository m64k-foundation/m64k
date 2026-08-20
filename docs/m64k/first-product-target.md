# M64K first-product microarchitecture target

| Field | Value |
|---|---|
| Status | Normative implementation target; no implementation-completion claim |
| Version | 0.1-development |
| Scope | First-product performance, scalability, and interface constraints |
| Compatibility | Implements M64K v1 without creating software-visible microarchitecture behavior |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Product target

The first product targets four out-of-order cores with two independently schedulable hardware threads per core. Each core targets four decoded and four retired architectural instructions per cycle, issue capacity of six typed micro-operations per cycle, and a 192-entry reorder buffer. These values are design constraints recorded by `isa/native/m64k-native-v1.json`; they are not claims that a production core currently exists or that any frequency, area, or power target has closed.

The target includes VA48 translation, a discoverable physical-address width from 36 through 48 bits, and a 48-bit first-product physical datapath. It also includes mandatory scalar IEEE-754 binary32/binary64 with fused multiply-add, the LP64D ABI, private L1I/L1D and unified L2 caches, a shared banked L3, directory-based MESI coherence, and TSO.

Scalable vectors and matrix/tile operations remain separate future extensions. Base interfaces MUST NOT freeze a vector length, tile geometry, or extension-context size. This requirement preserves an extension path; it does not reserve architectural state or advertise an unimplemented facility.

## D0 invariants

Every shared or reusable microarchitectural structure MUST preserve the owning core and hardware-thread identity through allocation, wakeup, response, fault, squash, and retirement. A backend token MUST distinguish at least execution context, ROB slot, slot reuse generation, allocation lifetime, and micro-operation index. A 1C1T build is a verification projection and MUST NOT replace these identities with implicit globals.

The 192-entry ROB requires at least eight index bits. Unused index encodings do not represent implemented entries. Allocation and generation identity MUST prevent a delayed completion from matching a later occupant of the same slot. Execution units MUST return typed result roles and MUST NOT publish architectural state directly; the live ROB allocation and precise retirement boundary remain authoritative.

The 48-bit physical transport width is the maximum first-product width, not permission to address unimplemented bits. An implementation exposing fewer than 48 physical bits MUST reject out-of-range addresses and page-table entries before a physical request and MUST report its width through the architectural discovery contract.

## Present alignment evidence

The current architecture-wide context type contains explicit core and hardware-thread identifiers. The private execution tag contains an eight-bit ROB index plus generation, allocation-sequence, and micro-operation identity. Current multiply and divide responses preserve the complete tag under backpressure and squash. The retirement observation interface defaults to four lanes, and physical memory and translation requests carry context and transaction identity.

This evidence proves only that these isolated contracts do not bake in a 1C1T or sub-192-entry identity assumption. It does not prove a four-wide frontend, rename, scheduler, ROB, LSQ, MMU, FPU, cache, coherence fabric, four-core integration, SMT fairness, or product-level PPA closure.

## Required acceptance evidence

The production core requires independent trace equivalence against the architectural model; formal allocation, wakeup, replay, squash, retirement, and memory-order properties; adversarial sibling-thread isolation and forward-progress tests; translation and coherence fault injection; and post-synthesis and post-route timing, area, power, congestion, and memory-macro evidence. Width or capacity values in a parameter list are not implementation evidence.
