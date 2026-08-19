# M64K architecture documentation

| Field | Value |
|---|---|
| Status | Draft architecture set; implemented M00 subsets are identified separately |
| Architecture version | 0.1-development |
| Scope | M68K compatibility profiles and the future native M64K ISA |
| Compatibility | Reset-compatible with big-endian M00; no native M64K ABI is frozen |

M64K is an open, synthesizable processor and system architecture. It preserves documented Motorola 68000-family behavior through explicit compatibility profiles and evolves toward a native 64-bit architecture with virtual memory, floating point, scalable vectors, matrix operations, coherent multiprocessing, and simultaneous multithreading.

This directory contains the architecture contracts and engineering roadmap. A document is normative only where it explicitly says so. Roadmap decisions constrain implementation direction but do not create software-visible behavior until an encoding, state-transition contract, exception model, and versioned feature bit have been specified.

The inherited `fx68k` core remains an optional instruction-level reference. It does not define the native M64K architecture or platform.

## Documents

- [architecture.md](architecture.md): profiles, execution states, register model, addressing, endian behavior, memory ordering, and implementation direction.
- [execution-domains.md](execution-domains.md): compatibility/native width rules, canonical register representation, context state, exception return, and domain-transition requirements.
- [memory-interface.md](memory-interface.md): implemented internal request/response protocol.
- [micro-ops.md](micro-ops.md): hybrid direct-execution and symbolic micro-operation policy.
- [frontend.md](frontend.md): current fetch pipeline and future high-performance frontend constraints.
- [exceptions.md](exceptions.md): precise fault, trap, interrupt, frame, and return discipline.
- [multicore.md](multicore.md): secondary-core boot, interrupts, atomics, and the ISA/firmware boundary.
- [implementation-plan.md](implementation-plan.md): ordered work packages and their exit gates.
- [repository-topology.md](repository-topology.md): repositories, upstream baselines, and cross-repository ownership.
- [repository-layout.md](repository-layout.md): normative subsystem ownership and source-tree organization.
- [m00-conformance-audit.md](m00-conformance-audit.md): manual-first opcode and exception review gate.
- [instruction-contracts.md](instruction-contracts.md): machine-readable instruction-contract workflow.
- [platform-requirements.md](platform-requirements.md): board, FPGA, memory, and I/O selection criteria.
- [platform.md](platform.md): board-neutral boot memory map and initial UART, timer, and discovery register contract.

## Names and profiles

| Name | Meaning |
|---|---|
| M64K | Project, architecture family, and native 64-bit execution state |
| M00 | MC68000-compatible profile |
| M10 | MC68010-compatible profile |
| M20 | MC68020-compatible profile |
| M30 | MC68030-compatible profile |
| M40 | MC68040-compatible profile |
| M60 | MC68060-compatible profile |
| M64K-V | Scalable vector extension |
| M64K-M | Matrix/tile extension |
| M64K-LE | Future full little-endian execution extension |
| M64K-A | Native atomic and memory-ordering extension |
| M64K-SMP | Coherent multiprocessing architecture |
| M64K-MT | Simultaneous multithreading architecture |

An implementation advertises one compatibility profile and a separate set of native extensions. Custom instructions are never silently added to an M68K compatibility profile.

## Current architectural decisions

- Reset enters supervisor M00-compatible, big-endian execution.
- M68K compatibility remains 32-bit even on a native 64-bit implementation.
- A 64-bit backend represents compatibility Dn/An/PC with zero upper halves at retirement; this is an internal canonical invariant, not hidden 64-bit compatibility state.
- Native M64K has a 64-bit scalar register and execution model; the exact instruction encodings and ABI remain unfrozen.
- Native byte/word data-register writes preserve the unselected portion, ordinary native long writes zero-extend, and quad writes replace all 64 bits; explicit widening instructions define their own extension operation.
- Classic `RTE` cannot cross into native execution. Domain changes are privileged, serializing, precisely faulting operations with distinct native return/context contracts.
- The initial native virtual-address target is 48 canonical bits. Physical-address width is implementation-selectable from 32 through 48 bits at stable interfaces.
- Native scalar state grows to sixteen data and sixteen address/general address registers while compatibility mode exposes the architected D0-D7/A0-A7 subset.
- The future scalable vector state contains 32 vector registers and 8 predicate registers, with implementation VLEN from 128 through 1024 bits.
- The future matrix extension contains eight tile registers whose shape and element interpretation are controlled by explicit architectural state.
- The first implementation remains in-order and single-issue. The performance path advances through a decoupled frontend and a two-wide out-of-order backend without changing architectural behavior.
- The target memory model is TSO. Atomics, cache coherence, device ordering, and page-table observation must be specified together before SMP is enabled.
- SMP precedes SMT. The initial SMT target is two hardware threads per core.
- Little-endian execution is reserved as a complete architectural mode, not a DDR-controller byte swap.
- The design is board-neutral and is not constrained by a retired FPGA target.

## Source layout

```text
rtl/m68k/m00/               current M00 compatibility RTL
rtl/m64k/                    future native 64-bit RTL only
rtl/interconnect/             shared transaction interfaces and routing
rtl/soc/                      board-neutral system integration
sim/models/                  behavioral memory and device models
sim/m68k/m00/               current M00 verification suite
isa/                         machine-readable instruction contracts
scripts/                     generation and audit tools
docs/m64k/                   architecture and engineering contracts
third_party/fx68k/           optional unmodified M00 differential reference
```

## Compatibility and evidence rule

Motorola or NXP manuals and applicable errata define every claimed M68K profile. Tests, compiler output, software traces, and inherited RTL are evidence, not specifications. Native M64K behavior is valid only after it is documented here, assigned a feature/version contract, and tested at legal, illegal, privilege, flag, exception, and fault boundaries.
