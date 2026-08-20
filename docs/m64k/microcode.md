# M64K v1 internal micro-operation and microcode policy

| Field | Value |
|---|---|
| Status | Normative implementation policy; uop fields and control-store depth are not frozen |
| Version | 0.1-development |
| Scope | M64K v1 instruction lowering, sequencing, precise retirement, and patch overlay |
| Compatibility | Internal implementation contract; never a software-visible ISA |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Architectural boundary

Every accepted assembly instruction encodes exactly one architectural M64K instruction. The assembler MUST NOT expand a mnemonic into multiple architectural instructions to claim semantic-cut-line coverage. A one-to-one alias MAY share the canonical instruction encoding only when operands, state effects, exceptions, ordering, and retirement are identical.

The frontend lowers each architectural instruction into typed internal micro-operations. A frequent instruction SHOULD use direct decode when its complete semantics fit the ordinary execution and retirement machinery. A multi-step, iterative, restart-sensitive, or uncommon instruction MAY enter the microcode sequencer. Both paths consume the same typed execution primitives and produce the same retirement contract; microcode is not a second public ISA.

## Micro-operation contract

Every issued micro-operation carries its architectural instruction identity, core identity, hardware-thread identity, ROB identity, source and destination physical-register identities, operand width, flag and predicate policy, privilege, memory-order class, and exception metadata where applicable. Memory micro-operations additionally carry transaction identity, access size, byte mask, memory type, atomic class, and a checkpoint identity.

Micro-operations MUST NOT publish architectural state directly. Register mappings, CSR changes, stores, maintenance effects, and architecturally visible condition state become visible only through the retirement and memory-order machinery. A squashed or faulting sequence cannot leak a partial result.

## Sequencer rules

A microcode entry point belongs to one versioned architectural instruction family. Its generated metadata specifies legal operands, temporary resources, maximum sequence length or bounded loop condition, interruptibility, fault checkpoints, memory-order behavior, and final retirement action.

A sequence with no architecturally visible checkpoint retires atomically as one instruction. A multi-access instruction that permits partial completion MUST name every checkpoint in the architectural specification and record sufficient restart state before the corresponding effect is committed. The sequencer MUST NOT invent restart or partial-completion behavior merely because an internal operation can fault.

Microcode may call reviewed shared subroutines only when call depth is statically bounded and the compiler proves that no recursion exists. The generated control-flow graph MUST reject unreachable entry points, invalid targets, unbounded loops, use-before-definition of temporaries, illegal resource combinations, and paths that terminate without retire, trap, or an explicitly bounded retry.

## Control store and silicon patching

The first product uses an immutable generated base control store protected by parity or ECC. After the complete M64K v1 corpus is compiled, its selected implementation MUST retain at least 25 percent unused entry capacity. Control-store width and depth are selected from the generated corpus and synthesis Pareto results rather than fixed before the uop contract is known.

Each core has a 32-entry patch overlay that matches a base microcode address and supplies a replacement control word. Patch state is outside architectural context and is identical for both hardware threads of a core. Machine firmware may populate the overlay only while all secondary contexts are held and no patched instruction can be in flight. A write-once lock remains asserted until chip reset.

The platform exposes immutable base revision and digest values plus the active patch-set revision and digest through Machine-readable CSRs. Loading firmware authenticates the patch payload through the platform secure-boot policy before programming the overlay. The core enforces sequencing and lock state; it does not define a second cryptographic trust root inside the execution pipeline.

A patch MUST preserve the architectural contract of its target instruction. It may correct implementation errata, timing sequences, or internal hazards, but cannot add opcodes, change operands, alter exception priority, weaken ordering, or expose new architectural state.

## Verification and PPA gates

Direct and microcoded forms that implement the same typed primitive MUST be checked against the same executable-model semantics. Verification covers entry decode, sequence bounds, temporary lifetime, every trap and checkpoint, squash, replay, simultaneous sibling execution, patch hit/miss, lock behavior, corrupted-control-word detection, and revision reporting.

Common operations remain on the direct path unless measured synthesis and workload evidence supports a different choice. A change between direct and sequenced implementation requires trace equivalence plus timing, area, power, control-store, and frontend-bandwidth comparison. Source-code compactness is not evidence of a better silicon implementation.
