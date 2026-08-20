# M64K v1 implementation roadmap

| Field | Value |
|---|---|
| Status | Active roadmap; no milestone completion is claimed |
| Version | 2.0-development |
| Scope | Unified native M64K v1 through first-product 4C2T validation |
| Compatibility | MC68060 semantic cut line; no M68K binary, ABI, effective-address, or trap-frame compatibility |

This roadmap replaces the former public N0/N1 split. M64K v1 is one architecture profile containing the native scalar ISA, U/S/M privilege, CSR traps, TSO, coherent atomics, VA48/PA48 translation, mandatory IEEE-754 FP32/FP64 with fused multiply-add, and LP64D. Integer-only execution is an internal bring-up projection and does not define another ABI.

## Permanent delivery rule

Every architectural tranche follows this order: validate primary sources, close semantic-cut-line coverage, freeze the English and machine-readable contract, generate independent artifacts, implement the smallest complete unit, verify positive and negative behavior, compare against the executable model, and measure synthesis effects. A downstream repository may begin implementation only when the contracts it consumes are frozen. All enabled first-party warnings are errors.

One assembly statement encodes one architectural instruction. One-to-one aliases are permitted, but an assembler expansion into multiple instructions cannot satisfy the MC68060 operation floor. Common instructions decode directly to typed micro-operations; complex instructions may use internal microcode while retaining one architectural retirement and one specified exception/restart contract.

## Current phase ledger

| Phase | State | Evidence and remaining gate |
|---|---|---|
| P0 | In progress | Twelve primary documents pass identity, parser, page-count, and digest validation. Cross-repository release manifests and the complete delegated-source map remain open. |
| P1 | In progress | Table 1-3 names, Appendix C integer variants, all Table C-3 forms, and all 42 Table C-4 cells are structurally inventoried. Instruction-form granularity, the system-contract corpus, erratum impact, and every multidimensional row review remain open. |
| P2 | Draft only | Native64 state, LP64D direction, VA48/PA48, TSO, topology, and cache targets are documented, but encodings, CSRs, causes, PTE bits, ELF identity, relocations, and the ABI are not frozen. |
| P3 | Started | A scalar semantic-model seed and SMP/SMT-aware interface contracts exist. Generated ISA artifacts, the complete model, typed uops, and microcode compiler/store do not. |
| P4 | Blocked | GCC, binutils-gdb, and Linux worktrees remain upstream baselines; no native backend or port is claimed. P2 must close first. |
| P5-P8 | Not started | No production core, cache hierarchy, coherent product, firmware, Linux boot, FPGA closure, or ASIC signoff is claimed. |

The terms `in progress`, `draft`, `started`, `blocked`, and `not started` are literal gate states, not percentage estimates. A phase becomes complete only when all listed exit evidence is reproducible.

## P0: source and repository integrity

- validate every cached manual as a parseable PDF with the expected document identity and page range in addition to its digest;
- complete the official MC68060/40 corpus and add MC68020/30 sources where semantic delegation requires them;
- preserve historical compatibility work only on archive branches;
- keep GCC, binutils-gdb, and Linux as independent ignored worktrees pinned by a versioned cross-repository integration manifest.

Exit evidence: corrupted or access-denied downloads fail closed; every cited document is reproducible from official metadata; active native branches contain no unreviewed compatibility commits.

## P1: closed MC68060 semantic cut line

- inventory every computational instruction family in the MC68060 instruction summary, documented integer-emulation set, applicable floating-point set, system facility, and erratum;
- maintain bidirectional MC68060-to-M64K and M64K-to-lineage coverage independent of allocated opcodes;
- record separate dispositions for encoding, widths, state, operand evaluation, result, conditions, memory, exceptions, restart, privilege, and ABI;
- decide lineage disposition, architectural identity, and lowering independently: every computational family requires a native analogue; that analogue may be a distinct instruction or a proven one-to-one alias, and either identity may lower to direct typed uops or reviewed microcode;
- replace legacy SR, USP, vector-frame, translation, cache, power, and reset facilities with explicit M64K system contracts rather than recreating Motorola state.

Exit evidence: deleting either side of a coverage row fails validation; every computational family has a native architectural operation; no empty ledger or self-derived decoder table can claim completeness.

## P2: M64K v1 architecture freeze

- freeze the complete instruction inventory, canonical syntax, fixed32 and extended encodings, illegal holes, immediates, branches, and relocation-bearing fields;
- freeze CSR numbers, cause numbers, trap priority, trap values, serialization, and atomic trap return;
- freeze the VA48/PA48 page-table bits, permissions, A/D behavior, ASIDs, invalidation, and shootdown;
- freeze TSO, MMIO ordering, coherent atomics, and the native double-compare analogue;
- freeze IEEE-754 FP32/FP64 plus FMA, NaN, rounding, exception, and context contracts while explicitly excluding FP80 and packed floating formats;
- freeze LP64D, ELF64 big-endian identity, RELA relocations, DWARF, unwind, TLS, syscall, signal, ptrace, and debug state;
- freeze the FDT boot protocol, timer, interrupt/IPI controller, and secondary-context release contract;
- request the official `EM_M64K` allocation before distributable ELF objects exist.

Exit evidence: specification and machine-readable contract agree bit-for-bit; collision and reserved-space proofs pass; no backend-readiness blocker remains.

## P3: generated architecture, model, and microcode

- generate encoder metadata, disassembly metadata, RTL decode, documentation tables, and test matrices from the reviewed ISA database;
- implement a complete independent executable model with deterministic retirement and memory-order traces;
- define the private typed micro-operation contract with core, hardware-thread, ROB, transaction, privilege, and exception identity;
- direct-decode frequent scalar, branch, load/store, and FP operations;
- compile complex operations into a generated control store with checked entry points, bounded loops, explicit fault checkpoints, and precise retirement;
- provide ECC/parity-protected base ROM with at least 25 percent unused capacity after v1 compilation and a 32-entry patch overlay;
- allow Machine firmware to load patches only while secondary contexts are held, expose revision and digest CSRs, and lock the overlay until reset.

Exit evidence: exhaustive legal/illegal model tests, direct-versus-microcode equivalence, patch-lock tests, fault-checkpoint tests, and reproducible generated artifacts.

## P4: toolchain waves

1. Implement complete libopcodes and disassembly after encoding freeze.
2. Implement GAS encoding and fixups from the same generated metadata.
3. Implement BFD ELF64 big-endian, RELA, LD, readelf, static linking, and every relocation after ELF and psABI freeze.
4. Implement GCC freestanding C and libgcc after a functional assembler/linker; then add C++, unwind, TLS, atomics, scheduling, and cost models.
5. Add GDB bare-metal state after DWARF and breakpoint contracts freeze; add Linux support after ptrace and signal UAPI freeze.

Exit evidence: exhaustive assembler/disassembler round trips, illegal/reserved rejection, relocation overflow tests, ABI torture, unwind/TLS tests, and compiler-generated payload execution on the model and RTL. A copied or renamed M68K backend is never acceptable.

## P5: production out-of-order core and silicon baseline

- implement the production core directly with 4-wide decode, rename, and retirement, issue capacity up to six micro-operations per cycle, and a 192-entry ROB;
- tag every queue, mapping, request, fault, trap, and retirement event for SMP/SMT from D0;
- implement branch recovery, load/store ordering, forwarding, replay, precise traps, atomics, MMU, and FP before claiming v1;
- integrate SRAM wrappers, clock/reset-domain inventory, CDC/RDC primitives, scan boundaries, and MBIST interfaces from the first RTL tranche;
- measure direct logic, shared units, and microcode alternatives through timing/area/power Pareto probes;
- validate one core and one thread without introducing single-core public interfaces.

Exit evidence: executable-model trace equivalence, formal commit/squash/replay/order properties, fault injection, warning-clean lint and synthesis, and recorded PPA effects.

## P6: memory hierarchy and coherent scaling

- integrate 32 KiB eight-way L1I and L1D, private 512 KiB eight-way unified L2, and shared eight-bank 4 MiB eight-way non-inclusive L3;
- implement MESI, directory ownership, non-blocking misses, ECC/parity, maintenance, prefetch controls, and MBIST boundaries;
- validate projections in order: 1C1T, 2C1T, 4C1T, then 4C2T;
- prove coherence races, atomic linearization, TLB shootdown, self-modifying code, DMA interaction, sibling isolation, and bounded progress.

## P7: firmware and Linux

- boot Machine firmware, validate microcode revision, initialize coherent platform state, and enter Supervisor mode with FDT in `r0` and an aligned stack in `r31`;
- create `arch/m64k` only as a functional vertical slice after binutils, GCC, trap, MMU, atomic, boot, and platform contracts are executable;
- reuse generic FDT, syscall numbering, 8250 console, fixed clock, virtio-mmio, dma-direct, and PCI ECAM infrastructure where contracts match;
- reach a native ELF64 BusyBox shell in UP mode, then enable 2-core, 4-core, and finally 4C2T operation.

Exit evidence: kernel build and boot, native init, signals, fork/exec, filesystems, timer progress, exception probes, atomics, IPIs, shootdown, false-sharing stress, and sustained eight-thread workloads.

## P8: FPGA and ASIC product closure

- keep FPGA wrappers for laboratory validation without leaking vendor primitives into architectural RTL;
- run independent frontend/elaboration, formal, synthesis, equivalence, CDC/RDC, scan/MBIST, STA, power, IR, DRC, LVS, and antenna gates appropriate to each target;
- use open PDKs only for comparative exploration and use the selected foundry PDK and signoff decks for manufacturing claims;
- claim frequency only from post-route multi-corner STA and report area, power, SRAM, congestion, fan-out, and critical-path evidence with each product baseline.

## Deferred extensions

Scalable vectors, matrix/tile operations, little-endian execution, virtualization, and compatibility facilities begin after M64K v1 closure. Their namespaces and context-extension mechanism remain reserved, but no placeholder instruction or state is advertised as implemented.
