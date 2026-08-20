# Native M64K architecture documentation

| Field | Value |
|---|---|
| Status | Draft architecture set |
| Architecture version | 0.2-development |
| Scope | Unified native M64K v1 architecture and first-product profile |
| Compatibility | MC68060 semantic cut line; no M68K binary, ABI, addressing-mode, or trap-frame compatibility |

M64K is a native 64-bit, big-endian processor architecture. M64K v1 includes the scalar ISA, U/S/M privilege, precise CSR traps, TSO, coherent atomics, VA48/PA48 translation, mandatory scalar FP32/FP64 with fused multiply-add, and LP64D. The first product targets coherent four-core, two-thread execution. Motorola-compatible execution is outside the native architecture.

A document is normative only where it says so. Draft encodings and ABI assignments are not frozen merely because they appear in a roadmap. Implementations may advertise only complete, verified profiles and extensions.

## Native specification set

- [architecture.md](architecture.md): profile composition, architectural state, addressing, and extension rules.
- [base-isa.md](base-isa.md): scalar execution, instruction classes, encoding policy, and instruction-contract requirements.
- [semantic-lineage.md](semantic-lineage.md): mandatory MC68060-centered historical semantic audit and per-contract disposition matrix.
- [privilege.md](privilege.md): privilege levels, control state, reset, traps, and interrupt routing.
- [exceptions.md](exceptions.md): precise exception selection, entry, return, and restart rules.
- [abi.md](abi.md): native ELF identity, data model, calling convention, stack, and process-entry contract.
- [memory-model.md](memory-model.md): TSO rules, fences, atomics, MMIO, and instruction synchronization.
- [microcode.md](microcode.md): direct lowering, typed uops, sequencing, precise retirement, and patch overlay.
- [mmu.md](mmu.md): canonical addresses, translation, page tables, permissions, and TLB maintenance.
- [multicore.md](multicore.md): first-product coherent SMP boot, interrupts, and two-way SMT.
- [cache-hierarchy.md](cache-hierarchy.md): private L1/L2 and shared banked L3 organization.
- [first-product-target.md](first-product-target.md): machine-checked 4C2T, four-wide, six-issue, ROB-192 destination and D0 interface constraints.
- [rob-allocation-lifetime.md](rob-allocation-lifetime.md): exact ROB allocation ownership, stale-response rejection, speculative recovery, and allocation-sequence rollover rules.
- [outstanding-uop-completion.md](outstanding-uop-completion.md): exact uop membership, terminal-completion validation, typed speculative publication, and strict retirement separation.
- [rob-completion-physical-candidates.md](rob-completion-physical-candidates.md): quantified lifetime/completion storage candidates, bank conflicts, validation placement, SRAM feasibility, and controlled PPA/formal selection gates.
- [implementation-plan.md](implementation-plan.md): ordered M64K v1 delivery and silicon gates.

Supporting engineering documents describe implementation mechanisms and repository policy. They do not extend the native ISA.

- [shared-shift-rotate-candidate.md](shared-shift-rotate-candidate.md): complete tagged shared-barrel experiment, verification evidence, structural QoR, and explicit production-selection rejection.

## Profiles

| Profile | Required architectural capability |
|---|---|
| M64K v1 | Native 64-bit scalar ISA, MMU, FP32/FP64+FMA, LP64D, precise CSR traps, big-endian memory, TSO, fences, and coherent atomics |

The first product target is 4 cores with 2 hardware threads per core and private L1/L2 plus shared L3. Scalable vector, matrix, little-endian, and virtualization facilities require separate versioned extensions.

## Conformance rule

An instruction or system facility is conforming only when its semantic-cut-line dispositions have been reviewed and its encoding, operands, state transitions, exceptions, privilege checks, ordering effects, illegal cases, and feature discovery are present in the English specification and machine-readable contract. Tests and RTL are evidence, not architecture definitions. No current document claims that M64K v1 has been implemented.
