# M64K first-product multicore and SMT profile

| Field | Value |
|---|---|
| Status | Normative draft |
| Version | 0.1-development |
| Scope | First-product four-core coherent SMP and two hardware threads per core |
| Compatibility | Product topology implements M64K v1 without changing instruction semantics |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Required topology

The first-product topology contains four cores, each with two hardware threads. Core and thread identifiers are stable from reset and form a unique pair. Software discovers implemented, enabled, online, and failed states rather than assuming that every physical context is usable.

Each hardware thread owns complete scalar registers, `PC`, condition state, privilege and trap CSR state, interrupt mask, `ASID`, translation root, and retirement state. A thread MUST NOT observe speculative, renamed, buffered, or faulted state belonging to its sibling. Cores MAY share frontend, execution, TLB, and cache resources only when tags and arbitration preserve architectural isolation and forward progress.

## Reset and secondary start

Reset starts core 0, thread 0 in machine privilege. All other contexts remain held and emit no memory transactions. Machine firmware writes a naturally aligned physical entry `PC`, stack pointer, boot argument, and initial privilege for each target, performs the required release fence, then changes that context to runnable through the system controller.

The released context begins with translation disabled, interrupts disabled, clean speculative state, and the programmed values. It validates topology and reports online through coherent memory or a platform doorbell. Core release is an MMIO/platform operation, not an ISA opcode.

## Interrupts and IPIs

Interrupt routing specifies source identity, priority, target privilege, target core, and either a target thread or an explicit any-thread policy. Pending state remains asserted until accepted or acknowledged according to its trigger mode. Re-routing MUST NOT lose a pending interrupt.

IPIs use the same routed interrupt mechanism. The first product requires IPI classes sufficient for scheduler reschedule, function call, TLB shootdown, instruction-cache synchronization, stop, and fatal recovery. Per-thread interrupt masks are independent. A stopped or waiting thread remains eligible for configured wake events.

## Coherence and atomics

All private L1 and L2 caches and the shared L3 participate in one coherent domain for normal write-back memory. Coherence is at 64-byte line granularity and provides the single store order required by TSO. The L3 home directory tracks the owner and a sharer bit for every core; per-core coherence endpoints track which sibling thread issued a request.

Atomics are linearized at the line's coherence home while exclusive ownership is held. Contending atomics eventually make progress under fair arbitration. A cache, core, or thread cannot be declared online until its coherence endpoint, interrupt route, and maintenance acknowledgements are operational.

## SMT scheduling and progress

The two hardware threads may fetch and issue concurrently. Retirement remains in order within each thread; there is no retirement order between threads beyond [memory-model.md](memory-model.md). Shared queues, MSHRs, store buffers, and execution units MUST retain thread identity through response and fault paths.

One runnable thread MUST make forward progress when its sibling is halted, waiting, repeatedly faulting, or generating cache misses. Implementations SHOULD provide bounded or reservable queue entries for each thread and SHOULD expose performance counters for sibling interference. Machine firmware can disable either sibling without resetting the other after the target reaches a quiescent architectural boundary.

## Required verification

Product acceptance includes cold and warm secondary boot, asymmetric core availability, all IPI targets, concurrent exceptions on sibling threads, atomics under contention, false sharing, cache-to-cache transfer, TLB shootdown during page reuse, self-modifying code across cores, DMA interaction, thread disable, queue starvation, and sustained eight-thread stress.
