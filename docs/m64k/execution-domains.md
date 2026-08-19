# M64K execution domains and width semantics

| Field | Value |
|---|---|
| Status | Draft architectural contract; transition encodings and native ABI are not frozen |
| Version | 0.1-development |
| Scope | M00--M60 compatibility domains and native M64K scalar execution |
| Compatibility | Preserves the selected M68K profile; does not reinterpret legacy instructions as 64-bit operations |

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in normative sections are to be interpreted as described by RFC 2119 and RFC 8174 when, and only when, they appear in all capitals.

This document separates architectural width from physical implementation width. It defines the decisions that current writeback, exception, context, and micro-operation interfaces must preserve so that a native 64-bit implementation can reuse verified M68K machinery without turning the current M00 core into a hidden 64-bit processor.

## Architectural domains

Each hardware thread has exactly one active execution domain:

| Domain | Scalar view | PC view | Instruction contract |
|---|---:|---:|---|
| Compatibility | Eight 32-bit `Dn`, eight 32-bit `An`, profile-specific control state | 32 bits, with profile-specific external visibility | Exact selected Motorola-compatible profile |
| Native | Sixteen 64-bit `Dn`, sixteen 64-bit `An`, versioned native control state | 64 bits, constrained by implemented canonical virtual-address width | Versioned M64K native ISA |

The selected compatibility profile is additional architectural state. M00, M10, M20, M30, M40, and M60 are not aliases for one generic compatibility mode: they retain their own instruction availability, control registers, exception frames, MMU/FPU behavior, and observable bus or cache rules.

Reset MUST select big-endian supervisor M00 compatibility. A processor MAY implement only compatibility domains, only a subset of later profiles, or both compatibility and native domains. It MUST NOT advertise an unverified profile or native extension.

## Physical implementation is not architectural state

An M00 implementation SHOULD use a 32-bit register file and datapath where that gives better FPGA area, timing, or power. A native implementation MAY map compatibility registers onto 64-bit physical registers, renamed registers, or another internal representation. Software cannot observe that choice.

When compatibility state occupies 64-bit physical storage, the following invariant applies at every retirement and precise-exception boundary:

```text
physical_D[63:32] = 0
physical_A[63:32] = 0
physical_PC[63:32] = 0
```

The zero upper half is a representation invariant, not an extension of the compatibility ISA. It prevents stale native values from becoming hidden compatibility state, makes legacy context switching complete, and gives differential verification a simple invariant. A speculative implementation MAY temporarily hold non-canonical physical candidates, but they MUST NOT become architecturally visible and MUST be discarded on squash or fault.

The current M00 core therefore remains genuinely 32-bit. Future backends enforce the invariant in their compatibility retirement adapter rather than widening every current M00 unit.

## Compatibility writeback rules

Compatibility instructions always apply the exact rule of their selected Motorola profile within the low 32 bits:

- a byte write to `Dn` changes only bits 7:0 and preserves bits 31:8;
- a word write to `Dn` changes only bits 15:0 and preserves bits 31:16 unless the instruction explicitly specifies extension;
- a long write to `Dn` writes exactly the 32-bit result;
- address-register word operations apply their documented sign-extension and full-address-register behavior;
- address-register long operations write or compute the documented 32-bit result;
- instructions with no destination write do not canonicalize, extend, or otherwise modify the destination as a side effect.

After that 32-bit architectural result is formed, a 64-bit physical implementation sets bits 63:32 to zero. Thus an M00 `MOVEA.W` that produces `$ffff8000` is represented physically as `$00000000ffff8000`: the compatibility-visible value remains exactly `$ffff8000`.

This two-stage rule is important. Operand-size handling belongs to the compatibility instruction contract; physical canonicalization belongs to retirement. Shared ALUs and micro-operations MUST NOT silently combine the two.

## Native scalar writeback rules

The initial native scalar rule is:

| Destination operation | Result in a 64-bit `Dn` |
|---|---|
| `.B` write | Replace bits 7:0 and preserve bits 63:8 |
| `.W` write | Replace bits 15:0 and preserve bits 63:16 |
| `.L` write | Write bits 31:0 and clear bits 63:32 |
| `.Q` write | Write all 64 bits |
| Explicit sign-extending operation | Sign-extend the source size to 64 bits |

Zero-extension for ordinary native `.L` destinations avoids dependency on stale upper halves and matches the intended efficient compiler lowering. Instructions such as signed conversions, address displacement formation, division, and widening multiply still carry their own explicit input-extension and result contracts. No instruction may rely on a global assumption when its documented operation differs.

Native `.B` and `.W` preservation follows the familiar M68K partial-data-register model. This is an ISA choice, not a requirement that a high-performance backend perform a physical read-modify-write: register renaming may merge or track the preserved portion by any equivalent implementation.

### Native address-register writes

Native address registers hold 64-bit values. Their rules are operation-specific:

- a direct `.L` load or move into `An` zero-extends to 64 bits;
- a direct `.Q` load or move writes all 64 bits;
- signed displacements are sign-extended to 64 bits before address arithmetic;
- address arithmetic computes at 64-bit width and does not silently truncate to the implemented virtual-address width;
- explicit sign-extension operations may intentionally create upper-half ones.

An arbitrary value MAY reside in `An`. Canonical-address validation occurs when the value is used for instruction fetch, data access, translation maintenance, or another operation whose contract requires an address. This permits integer construction of addresses and ensures that a non-canonical-address exception is associated with the consuming instruction rather than an unrelated earlier register write.

## Program counter rules

A compatibility PC is a 32-bit architectural value. In M00, address-register and PC calculations retain their documented 32-bit behavior while the external address interface exposes only the profile-defined physical address bits. The future 64-bit compatibility representation zero-extends that 32-bit PC; it MUST NOT use the M00 external bus mask as a register mask.

A native PC is 64 bits. Every committed native control-flow target MUST be canonical for the active virtual-address width and satisfy the native instruction-alignment contract. A non-canonical or misaligned target faults before the target instruction retires. The first native target remains 48-bit canonical virtual addressing; wider revisions require an advertised capability and versioned rules.

## `MOVEM` and context state

Compatibility `MOVEM` retains the selected profile's transfer size, register order, address-register alias rules, sign extension, fault checkpoints, and restart behavior:

- a word memory-to-register transfer sign-extends to the documented 32-bit compatibility result and the physical compatibility adapter then clears bits 63:32;
- a long memory-to-register transfer writes the exact 32-bit pattern and clears physical bits 63:32;
- register-to-memory transfers expose only the documented word or long portion;
- no compatibility `MOVEM` can access native-only registers or upper halves.

Native full-width multiple-register transfer requires a separately encoded and specified operation, provisionally described as the `MOVEM.Q` class. Its register mask width, ordering, restart checkpoints, atomicity, alignment, and interaction with an expanded register namespace must be frozen before an encoding is allocated.

An exception frame is not a complete process context. A compatibility operating system can save the compatibility integer state using its normal 32-bit mechanisms because the upper-half invariant guarantees that no additional compatibility state exists. A native operating system must save 64-bit scalar registers and all enabled architectural extension state. FPU, vector, matrix, debug, and transactional state require explicit ownership and eager or lazy save/restore rules; they cannot be inferred from integer `MOVEM`.

## Exceptions and return

An exception taken in a compatibility domain uses the exact frame and stacked PC/SR semantics of the selected profile. By default it enters the supervisor state of the same compatibility domain. Native-only register halves and registers MUST NOT leak into the frame.

An exception taken in native mode uses a versioned native frame. The native frame must identify at least its format and length, saved execution domain, complete 64-bit PC, native status, fault class, access metadata, and the information required to restart any architecturally restartable operation. Vector, matrix, and transactional restart fields are added only with their defining extensions.

A classic compatibility `RTE` parses only frames permitted by the active compatibility profile and MUST NOT enter native mode. This keeps existing supervisor code and forged legacy frames from accidentally selecting a wider execution contract.

Returning from a native exception uses a distinct native return contract. It may restore either native state or a previously interrupted compatibility domain from a versioned frame. The instruction encoding, frame integrity checks, privilege checks, and cross-domain return rules remain to be frozen with the native privilege architecture; they will not be retrofitted into a classic frame.

## Domain transitions

Domain transition is a privileged architectural operation, not a side effect of an ordinary branch, `MOVEM`, status-register write, or compatibility `RTE`. Its final encoding and mnemonic are intentionally unassigned.

A transition MUST:

1. execute as a serializing, precisely faulting operation;
2. stop younger fetch/decode and drain or squash younger speculative work;
3. complete all older architecturally required memory effects;
4. validate the target domain, profile, PC, stack, privilege, endian state, and required feature set before publication;
5. establish every newly visible register and control bit deterministically;
6. invalidate or retag frontend, predictor, translation, and memory-ordering state that is not safe across domains;
7. commit the new domain and target PC atomically at retirement.

For the initial compatibility-to-native transition, `D0-D7`, `A0-A7`, and the compatibility PC are zero-extended from their exact 32-bit values. Native-only `D8-D15` and `A8-A15` start at zero unless a future versioned context-load form explicitly supplies them. Native privilege and system state use architecturally defined reset/entry values rather than residual implementation state.

For a native-to-compatibility transition, the selected profile must be implemented and enabled. `D0-D7` and `A0-A7` are reduced to their low 32-bit patterns, their physical upper halves are cleared, and the target PC must fit the 32-bit compatibility view. Native-only state remains part of the suspended native context but cannot affect compatibility execution. The operating system is responsible for isolating that saved context between processes or virtual machines.

Endian transition is a separate architectural concern. A future little-endian mode change may share the serialization machinery, but domain and endian changes must each have explicit requested and resulting state. Neither may occur implicitly because the other changes.

## Per-thread, SMP, and virtualization implications

Execution domain, compatibility profile, endian state, privilege state, address-space identity, and extension ownership belong to each hardware thread. Shared predictors, caches, TLBs, and coherence structures must either tag entries with every state component needed for correctness or perform the architecturally required invalidation on transition.

Interrupt routing must define the target hardware thread and the domain in which delivery begins. The baseline rule is same-domain delivery; cross-domain monitor or hypervisor entry is a future privileged feature with a versioned frame contract. SMP does not weaken the upper-half invariant or permit one core to observe another core's physical register representation.

## RTL and verification requirements

Current and future implementation interfaces should distinguish:

- architectural operand size from physical datapath width;
- compatibility result formation from physical canonicalization;
- logical address width from physical address width;
- instruction semantics from execution-domain transition;
- exception-frame construction from full context save/restore.

Reusable units SHOULD be parameterized or typed where behavior is genuinely identical. A block must not be generalized merely to appear future-proof: profile-specific behavior remains in profile-specific control or adapters.

Before native RTL is claimed, verification must include:

- the same compatibility program executed on the 32-bit reference core and a 64-bit backend, comparing retirement state, exceptions, and bus-visible effects;
- assertions that compatibility physical upper halves are zero at every retirement and exception boundary;
- byte, word, and long partial-write tests across register aliases;
- native `.L` zero-extension, `.Q` full-write, and explicit sign-extension tests;
- canonical and non-canonical PC/address tests;
- every compatible and native exception/return pairing;
- interrupted and faulting transitions with no partially published domain state;
- context-switch tests that poison all previously owned native, FP, vector, and matrix state before reassignment;
- SMP tests with different domains active simultaneously on different hardware threads.

No passing workload may substitute for these architectural checks.
