# M64K architecture direction

| Field | Value |
|---|---|
| Status | Draft; compatibility behavior is normative only for audited implemented M00 contracts |
| Version | 0.1-development |
| Scope | M00 through M60 compatibility and native M64K execution |
| Compatibility | Big-endian M00 reset; native ABI and encodings are not frozen |

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in normative sections are to be interpreted as described by RFC 2119 and RFC 8174 when, and only when, they appear in all capitals.

## Architecture boundary

M64K has two architectural execution domains:

1. **M68K compatibility domain.** Software observes the selected Motorola-compatible profile, including its register widths, effective addresses, privilege model, exceptions, stack frames, and instruction encodings.
2. **Native M64K domain.** Software can use 64-bit scalar state, a larger register namespace, wider virtual and physical addresses, new system state, and versioned extensions.

Compatibility mode is not a 64-bit reinterpretation of M68K opcodes. Existing binaries retain their documented 8 data registers, 8 address registers, 32-bit arithmetic, 32-bit PC behavior, and profile-specific exceptions. Native mode may share physical implementation resources, micro-operations, caches, predictors, and execution units, but it has an independently specified architectural contract.

Reset MUST enter big-endian supervisor M00-compatible state and obtain its initial stack pointer and PC using the M00 reset-vector contract. A future transition to native M64K MUST be privileged, serializing, restart-safe, and explicitly specified before an opcode is allocated. The transition must drain or invalidate speculative frontend state and establish all newly visible state deterministically. No provisional transition mnemonic or encoding is ABI.

## Compatibility profiles

Profiles are cumulative only where the corresponding Motorola generation is cumulative. Generation-specific removals, changed exception frames, timing-independent semantic differences, and optional units remain explicit.

| Profile | Software-visible target |
|---|---|
| M00 | MC68000 integer ISA, classic effective addresses, SR, exceptions, and 24-bit-visible compatibility behavior |
| M10 | MC68010 control state, VBR, loop behavior, and restartable exception model |
| M20 | MC68020 32-bit addressing, full extension-word effective addresses, later integer operations, and generation-specific frames |
| M30 | MC68030 MMU/cache/control programming model and applicable M20 integer behavior |
| M40 | MC68040 integer, MMU, cache, FPU, control, and precise exception programming model |
| M60 | MC68060 architectural behavior, including its implemented/unimplemented instruction and exception contracts |

An implementation may physically expose more address bits than its current compatibility profile. It must not advertise a profile until the complete required architectural contract has passed the documented audit.

## Architectural state

### Compatibility state

The compatibility register view is generation-specific. Its maximal planned M40/M60 view includes D0-D7, A0-A7, PC, SR, USP/ISP/MSP, VBR, SFC, DFC, cache controls, MMU roots and transparent-translation registers, MMUSR, eight extended-precision FP registers, FPCR, FPSR, FPIAR, and generation identity state.

Compatibility writes update the corresponding low-order native physical state only at retirement. Narrow compatibility results retain the exact Motorola-defined preservation or extension rule; they do not inherit a blanket native 64-bit rule. When this state is hosted by a 64-bit backend, Dn, An, and PC have zero upper halves at retirement and precise-exception boundaries, as specified by [execution-domains.md](execution-domains.md).

### Native scalar state

The planned native scalar view contains:

- sixteen 64-bit data registers `D0-D15`;
- sixteen 64-bit address/general address registers `A0-A15`;
- a 64-bit program counter constrained by the active virtual-address width;
- distinct user, supervisor, interrupt, and machine stack/control state as finalized by the privilege specification;
- version, feature, address-width, endian, vector-length, topology, and implementation identity registers.

The compatibility-visible D0-D7/A0-A7 map to the low subset of native storage. This mapping is an implementation and context-management contract; it must not create partially visible upper halves when compatibility instructions retire or fault.

Native operand sizes include byte, word, long, and quad scalar forms. `.Q` denotes a 64-bit scalar operand only in native M64K encodings. Ordinary native `.L` data-register writes zero-extend to 64 bits; explicit sign-extending, address-arithmetic, and widening instructions retain operation-specific contracts recorded in the machine-readable ISA database. Compatibility `.L` remains exactly 32-bit.

### Vector and matrix state

M64K-V is planned with 32 scalable vector registers and 8 predicate registers. Architectural VLEN is discoverable and ranges from 128 through 1024 bits in power-of-two implementations. Vector instructions must be independent of physical lane count and may execute in multiple beats. Restart rules, fault-only-first behavior, mask semantics, lane numbering, inactive-element policy, and context save/restore are required before the first encoding is frozen.

M64K-M is planned with eight tile registers. Tile dimensions, element type, accumulator precision, saturation/rounding behavior, memory layout, and interaction with M64K-V are explicit state; tiles do not silently alias scalar, FP, or vector registers.

## Addressing and endian behavior

Compatibility logical addresses remain 32 bits for M20 and later profiles, with M00 bus visibility constrained by profile rules. Native M64K initially targets 48-bit canonical virtual addresses. Bits above the implemented virtual width must equal the sign/canonical extension defined by the native address specification; non-canonical accesses fault before translation. Stable memory-system interfaces parameterize physical width from 32 through 48 bits, allowing implementations from 4 GiB through 256 TiB of physical address space without hard-coding a board capacity.

Reset and all currently implemented execution are big-endian. Internal arrays store physical bytes with byte zero at the lowest address. Fetch, load/store, vector, matrix, page-table, stack-frame, and device units assemble bytes according to architectural state.

M64K-LE is reserved for a future complete little-endian execution state. Its specification must cover instructions, data, exception frames, page tables, atomics, scalar/FP/vector/matrix lane interpretation, debugging, DMA, devices, firmware, and ABI. A privileged endian transition must serialize execution and make stale cache or translation interpretation impossible. External DDR wiring never defines architectural endian behavior.

## Instruction encoding direction

M68K encodings retain their profile-defined 16-bit-word format. The native M64K encoding space will be versioned and separately decoded. Line-A is the preferred exploration namespace because it is architecturally trapped in classic profiles, but no Line-A word becomes native merely by implementation convention. Allocation requires a published encoding table and collision proof for every compatibility profile.

The native decoder target accepts instructions up to 16 bytes. Common scalar operations should remain compact, while extension words carry larger register indices, `.Q`, predicates, vector shape, or immediate data. Decoder structure must identify instruction length and faults before younger instructions can retire. Toolchain syntax, relocation behavior, disassembly, illegal encodings, and forward-compatible reserved fields are part of each encoding decision.

## Execution implementation

### Current reference pipeline

The first-party M00 core is an in-order, single-issue implementation with precise state publication. It uses a decoupled line fetcher, variable-length instruction buffer, generated decode metadata, direct execution for common operations, and typed multi-cycle sequences for complex memory or iterative work.

Microcode is an implementation mechanism, not a second public ISA. Multi-step, restartable, iterative, and sequencing-heavy instructions lower to symbolic typed micro-operations. Common arithmetic and logical instructions may execute directly when doing so reduces latency and critical depth without duplicating semantics. Both paths share the same ALU, address-generation, load/store, flag, exception, and retirement contracts.

### Performance evolution

The performance target is a decoupled, speculative frontend feeding a two-wide out-of-order backend with up to four decoded micro-operations delivered per cycle. Planned structures include branch prediction, instruction cache, translation lookaside buffers, physical-register renaming, integer and address-generation issue queues, load/store ordering, a reorder buffer, precise retirement, and replay after recoverable memory events.

This is not implemented by widening the current state machine. Each stage is introduced behind architectural trace equivalence and precise-exception gates. The in-order core remains a readable reference implementation and differential oracle. Frequency claims require post-route evidence on a selected FPGA; the architectural target does not promise a MHz value.

## Memory hierarchy, MMU, and ordering

M40 compatibility targets separate instruction and data translation/cache behavior, including its ATCs, transparent translation, maintenance operations, page attributes, fault status, and exception frames. Native M64K uses an independently versioned page-table contract capable of the initial 48-bit virtual and physical widths. Compatibility and native TLB entries carry address-space, privilege, endian, page-size, access, and global metadata sufficient to prevent aliasing across modes and hardware threads.

Private L1 caches connect through coherence endpoints. The exact cache sizes and associativity are implementation parameters; line size and architecturally observed maintenance semantics are versioned platform/architecture contracts. Instruction coherence after code modification, DMA coherence, page-table observation, and non-cacheable/device accesses must not depend on software accidentally using a uniprocessor path.

The native memory model target is TSO. Loads, stores, atomics, fences, cache maintenance, MMIO, page-table updates, DMA, and instruction synchronization must have a single written ordering model. M00 TAS and M20 CAS/CAS2 use indivisible fabric transactions even in a single-core build. M64K-A extends atomics only after their success/failure results, alignment, exception, endian, cacheability, and ordering semantics are specified.

## Exceptions, privilege, and precise retirement

Every instruction carries its architectural PC, execution domain, profile/version, privilege, hardware-thread identity, and pending effects until retirement. Fetch, decode, execution, translation, cache, fabric, FPU, vector, and matrix units report structured fault records. The retirement boundary selects the architecturally oldest event, commits only permitted older effects, suppresses younger effects, and constructs the exact profile- or native-specific frame.

Compatibility exceptions use the applicable generation contract, not a common invented frame. Native M64K will define a versioned frame containing enough state to restart scalar, vector, matrix, transactional memory, and mode-transition operations. Double-fault and machine-check behavior must be deterministic and testable. Interrupt routing includes target core, target hardware thread or thread policy, priority, vector/source identity, and privilege domain.

## Floating point

Compatibility FPU behavior follows the selected generation, including extended state, rounding modes, accrued/current exception flags, traps, packed/extended formats where required, and documented unimplemented-operation handling. Host floating-point types are never a specification oracle.

The implementation uses an explicit recoded internal format and shares precise retirement with the integer backend. Native FP operations may add wider scalar or vector capabilities only behind separate feature bits and ABI contracts.

## Multiprocessing and multithreading

M64K-SMP consists of private cores and L1 caches, coherent endpoints, a shared coherence fabric and optional last-level cache, per-core reset and identity, routed interrupts/IPIs, per-core timers, and firmware-defined secondary-core release. Core count is discoverable; no public interface assumes one or two cores.

SMP does not inherently require new ordinary arithmetic opcodes. It requires an architected memory model, atomic/fence operations, cache and TLB maintenance, interrupt routing, topology discovery, and firmware/kernel boot contracts.

M64K-MT follows a working SMP implementation. Each hardware thread has complete precise architectural state and an independently addressable interrupt/debug/context identity. Shared frontend, execution, cache, predictor, and translation resources require partitioning or tagging. The initial implementation target is two hardware threads per core, but interface widths must remain parameterized.

## Debug and verification visibility

Implementations expose an architectural retirement trace rather than requiring verification to inspect simulator hierarchy. Trace records identify core, hardware thread, execution domain, PC, instruction bytes, decoded operation, register/memory effects, exception, and retirement order. Debug context includes compatibility, native scalar, MMU, FPU, vector, matrix, interrupt, and thread state.

No performance optimization may weaken precise exceptions or make architectural correctness depend on a testbench. The in-order reference, generated instruction contracts, directed matrices, randomized differential testing, formal properties, firmware, and Linux are complementary evidence; primary manuals or versioned M64K specifications remain the source of truth.
