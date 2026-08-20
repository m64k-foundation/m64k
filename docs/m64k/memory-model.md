# M64K TSO memory model

| Field | Value |
|---|---|
| Status | Normative draft |
| Version | 0.2-development |
| Scope | M64K v1 normal memory, atomics, fences, MMIO, page tables, and instruction visibility |
| Compatibility | Native TSO contract; no Motorola bus-lock or uniprocessor-order compatibility |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## TSO normal-memory rules

Each hardware thread has one architectural memory order. Loads are observed in program order with respect to older loads. Stores are observed in program order by all observers. A load MAY complete before an older store to a different address, but it MUST obtain the value of the youngest older overlapping store from its own thread. No other load/load, load/store, or store/store reordering is architecturally visible.

All coherent observers agree on a single order for stores to the same byte. A naturally aligned byte, word, long, or quad normal-memory load or store is single-copy atomic. Misaligned and wider composite accesses are not atomic. Instruction fetch is not an implicit coherent load for self-modifying-code purposes; software uses the instruction-synchronization sequence below.

## Fences

| Operation | Required effect |
|---|---|
| `FENCE.R` | Completes older loads before younger loads or stores become visible |
| `FENCE.W` | Drains older stores to the point required by their memory type before younger stores become visible |
| `FENCE.RW` | Combines read and write ordering and prevents an older store/younger load bypass |
| `FENCE.IO` | Completes prior device accesses before subsequent device accesses |
| `ISYNC` | Discards stale instruction-side translation, prediction, and fetch state at the executing thread |

Atomic read-modify-write instructions are indivisible in the coherence order. Acquire prevents later loads and stores from becoming visible before the atomic. Release prevents the atomic from becoming visible before earlier loads and stores. Sequentially consistent atomics additionally participate in one total order consistent with each thread's program order.

## Memory types

| Type | Cache | Speculation | Combining | Ordering |
|---|---|---|---|---|
| Normal write-back | Coherent | Allowed subject to permissions | Allowed within TSO | TSO |
| Normal non-cacheable | No allocation | Read speculation allowed only when idempotent | Implementation-defined, fenceable | TSO |
| Device | Never | Prohibited | Prohibited unless the mapping explicitly enables it | Strongly ordered by `FENCE.IO` |

Memory type is a property of the final physical mapping. Conflicting aliases are forbidden; the operating system MUST not map one physical line with incompatible cacheability or device attributes. Atomics are legal only on coherent normal memory and naturally aligned operands contained within one 64-byte cache line.

## Page tables, DMA, and code modification

After writing page-table entries, software executes `FENCE.W`, the required scoped TLB invalidation, and the defined shootdown acknowledgement before reusing a translation. A page-table walker observes coherent normal memory but does not bypass the required invalidation protocol.

DMA coherence is a platform property advertised per device. A coherent DMA agent participates in the same line coherence domain. A non-coherent agent requires explicit clean/invalidate maintenance and device fences.

To make modified code executable, the writer stores the new bytes, executes `FENCE.W`, performs any required data-cache clean to the point of instruction coherence, requests instruction-cache invalidation on every target core/thread, waits for acknowledgement, and each executing thread performs `ISYNC`. Data coherence alone is insufficient.

## Litmus commitments

M64K v1 forbids load/load and store/store reordering. Store buffering (`Store x=1; Load y` on each of two threads both reading zero) is permitted. Message passing with `Store data; Store flag` preserves store order, so a thread that observes the new flag through coherent normal memory also observes the older data store. IRIW outcomes inconsistent with the single coherent store order are forbidden.
