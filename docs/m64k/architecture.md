# M64K native architecture

| Field | Value |
|---|---|
| Status | Normative draft |
| Version | 0.2-development |
| Scope | Unified native M64K v1 architecture |
| Compatibility | No M68K binary, ABI, effective-address, trap-frame, or source compatibility is provided |

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in normative sections are interpreted as described by RFC 2119 and RFC 8174.

## Version model

M64K v1 is one public architecture profile. It includes the native scalar ISA, U/S/M privilege, precise CSR traps, TSO, coherent atomics, the VA48/PA48 MMU, mandatory IEEE-754 scalar FP32/FP64 with fused multiply-add, and the LP64D ABI. Integer-only bring-up is an implementation stage of this same profile and never creates a second ABI or externally visible subset. The first product target is four cores with two hardware threads per core.

An implementation claiming M64K v1 MUST implement every v1 requirement. It MUST NOT advertise a partially implemented v1 profile. Optional facilities use independent extension identifiers and context-state discovery.

The MC68060 instruction inventory is the mandatory semantic cut line for the v1 computational vocabulary. Each computational family receives a native architectural analogue using M64K registers and operand forms. Legacy system state is replaced by the corresponding M64K CSR, trap, MMU, cache, power, or platform facility. This rule does not import Motorola encodings, effective-address modes, D/A register banks, partial-register behavior, status-register layout, hardware exception frames, or 32-bit address wrapping.

## Scalar architectural state

Each hardware thread contains:

- thirty-two writable 64-bit integer registers `r0-r31`; no register is hardwired to zero;
- a 64-bit program counter `PC`;
- `N`, `Z`, `C`, and `V` condition state written only by explicit `.F` instruction forms;
- one persistent per-thread `X` extend bit, independently renameable from `NZCV`;
- eight predicates `p0-p7`, where `p0` always reads true and ignores writes while `p1-p7` are writable per-thread state;
- current privilege, interrupt enable and threshold, address-space identifier, and exception state;
- profile, feature, address-width, topology, and implementation-identification control registers.

Integer arithmetic wraps modulo its operand width unless the instruction contract says otherwise. Byte, word, long, and quad results are 8, 16, 32, and 64 bits. Ordinary byte, word, and long register results zero-extend to 64 bits; quad results replace all 64 bits. Sign extension is always explicit. Only `ADCX`, `SBCX`, and rotate-through-X operations read or write `X`; ordinary operations and `.F` forms preserve it.

M64K v1 includes thirty-two 64-bit floating-point registers `f0-f31` holding scalar IEEE-754 FP32/FP64 values. Their operation, NaN, rounding, exception, fused-operation, and context contracts are versioned with v1. Motorola extended-precision and packed floating formats are not part of v1.

Architectural state changes become visible at retirement. Faulting and squashed operations MUST NOT publish register, control, or cache-maintenance effects. External stores that an explicitly restartable multi-access instruction has already committed are governed by that instruction's checkpoint contract.

## Addresses and byte order

M64K v1 uses 48-bit canonical virtual addresses and implementation-discovered physical addresses from 36 through 48 bits. For a canonical virtual address, bits 63:48 MUST equal bit 47. Machine-mode physical execution before translation is enabled uses the same 64-bit address-generation rules and validates the implemented physical width before issuing a request. A non-canonical translated address or an out-of-range physical address raises an address exception before a memory request.

The architecture is big-endian: the most significant byte of a scalar occupies the lowest address. Byte addresses increase monotonically through memory. Instruction fetch, scalar access, page-table walks, software-saved trap state, atomics, DMA-visible data, and MMIO use the same byte convention.

Unaligned byte accesses are always legal. The legal alignment of wider accesses is defined by each instruction class. Base loads and stores require natural alignment. A separately encoded unaligned normal-memory operation MAY decompose an access only if its contract guarantees precise faults and the access does not cross into a different memory type. Atomics and MMIO MUST be naturally aligned.

## Execution and memory

Every base instruction is one naturally aligned 32-bit word. The first word also identifies extension-envelope instructions whose total length is 64, 96, or 128 bits. Reserved encodings raise the illegal-instruction exception and MUST NOT be reinterpreted according to implementation configuration.

Reset and early Machine-mode firmware may execute with translation disabled. The complete v1 architecture nevertheless includes the MMU, scalar floating point, TSO, and atomics. Core/thread count and cache sizes are implementation properties; the first product targets four discoverable cores and two independently schedulable hardware threads per core. Microarchitecture is not architectural.

M64K v1 is not a single-thread architecture. From design stage D0, every public core, memory, interrupt, trap, maintenance, and retirement interface identifies core and hardware thread. A 1C1T configuration is only a validation projection of the same SMP/SMT-aware contracts.

## Extension boundary

Scalable vector, matrix/tile, little-endian, debug, and virtualization extensions are outside M64K v1. An extension specification MUST define state, instructions, context management, exception interaction, memory ordering, ABI use, discovery, and behavior when absent before an encoding is assigned.

## Compatibility statement

M64K v1 defines a new ISA, ELF machine identity, and ABI. M68K instructions, exception frames, status registers, and executable formats are not recognized in native execution. A system MAY contain a separately specified compatibility processor or translation layer, but it MUST NOT advertise that facility as part of M64K v1.
