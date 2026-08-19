# MX68K micro-operation architecture

## Decision

MX68K uses a hybrid decoded-micro-operation design. M68k remains the only base
software ISA. There is no public RISC ISA below it and software cannot branch
into the micro-op stream.

The frontend recognizes an instruction and produces one of two forms:

- a directly issued micro-op for common register ALU, simple move and branch
  cases;
- an entry into a symbolic microprogram for multi-step effective addresses,
  MOVEM, bitfields, atomics, control-register, cache, MMU and FPU operations.

Both forms use the same typed micro-op representation and commit machinery.
This avoids penalizing frequent simple instructions with a ROM lookup while
keeping complex CISC behaviour reviewable.

## Initial micro-op classes

```text
ALU       add/sub/logic/compare/BCD helper
SHIFT     shift/rotate/bitfield fragments
EA        calculate/update an effective address
LOAD      translated scalar or line read
STORE     translated scalar or line write
BRANCH    condition, target and control-flow serialization
REG       register/control-register transfer
SYSTEM    trap, reset, stop, cache/MMU maintenance
MULDIV    iterative or pipelined multiply/divide
FPU       scalar floating-point operation
VECTOR    reserved MXV operation
COMMIT    instruction completion/checkpoint marker
```

Every micro-op carries an instruction sequence ID, instruction-start PC,
operand size, profile, privilege and exception eligibility. Memory micro-ops
also carry the logical address, function/access space, ordering class and a
restart checkpoint.

## Architectural visibility

Register and flag results are staged until their defined commit point. Younger
instructions never become architecturally visible before an older faulting
instruction.

This does **not** incorrectly make every CISC instruction transactional.
Externally visible writes cannot be rolled back, and generation-specific
multi-access instructions may expose completed sub-accesses before a later
fault. Their microprograms therefore define architectural checkpoints and the
exception frame records the state needed by the relevant profile. CAS/CAS2 and
future MXA operations use explicit fabric atomicity instead.

“Precise exception” means the visible state exactly matches the documented
profile-specific fault point. It does not mean pretending that a partially
completed instruction never began.

## Symbolic source and generation

Microprograms will be stored as reviewed symbolic source. A generator must
produce:

1. packed synthesizable tables;
2. field constants and static legality checks;
3. a human-readable disassembly/listing;
4. decoder-to-entry-point tables;
5. coverage metadata for architectural tests.

Generated files are reproducible build products. An unexplained binary
microstore like the inherited fx68k ROMs is not accepted for the new core.

The first implemented slice lives in `isa/mx68k_m00.json`. The generator
`scripts/gen_mx68k_decode.py` validates identifiers, masks, values and opcode
overlap, then emits
`rtl/mx68k/core/decode/generated/mx68k_m00_decode_table_pkg.sv`. Every MX test
first checks that the committed table exactly matches its JSON source.

`mx68k_uop_pkg.sv` is the implemented decoder/backend contract. Besides the
operation and operand references, each record carries its compatibility
profile, instruction ID/start PC/sequential PC, CCR dependencies, privilege,
serialization, memory ordering, fault eligibility and restart checkpoint.
The predecoder emits one direct µop for simple/system instructions. Complex
operations use explicit symbolic sequence state behind the same typed
interface. `CMPM` is the first generic two-read client: source read and source
postincrement checkpoint precede destination read and final flags/address/PC
commit. MOVEM and the existing extend/BCD paths retain their specialized loops
until they are migrated without changing their documented fault checkpoints.

Memory µops also carry a canonical 32-bit logical address independently from
their operand references. The first native LSU path uses it for byte stores,
places the byte in the matching 16-byte fabric lane and delays architectural
PC update/retirement until the memory response succeeds. A faulting store
therefore leaves PC and register state at the instruction boundary.

## Why this is preferable here

M68k effective-address parsing, profile differences and faultable multi-access
instructions create much more control complexity than datapath complexity.
Typed micro-ops give the pipeline a regular interface, permit one common fault
record, and allow later implementations to change physical execution width
without changing the ISA.

The first core remains in-order and single-issue. Out-of-order execution, macro
fusion or multiple issue are explicitly later microarchitectures; the symbolic
micro-op contract is designed not to preclude them.
