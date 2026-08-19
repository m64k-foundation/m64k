# MX68K specification

MX68K is a new, board-neutral M68k architecture and RTL implementation. Its
first compatibility target is the software-visible MC68040 architecture; later
revisions may add the optional MXV vector, MXLE full little-endian, MXA atomic
and MXMP multiprocessor extensions.

This directory is normative. The older `docs/knowledge-map/` directory
describes the inherited code and explains why the new architecture is needed.

## Documents

- [architecture.md](architecture.md): architectural and microarchitectural
  contract.
- [memory-interface.md](memory-interface.md): first implemented internal
  request/response protocol.
- [micro-ops.md](micro-ops.md): hybrid lowering and symbolic microprogram
  contract.
- [frontend.md](frontend.md): fetch, prefetch, prediction and pipeline hazard
  plan.
- [exceptions.md](exceptions.md): precise fault, trap, interrupt, frame and RTE
  discipline.
- [multicore.md](multicore.md): secondary-core boot, IPIs, atomics and the
  boundary between firmware mechanisms and ISA extensions.
- [implementation-plan.md](implementation-plan.md): modules, milestones and
  feature exit gates.
- [m00-conformance-audit.md](m00-conformance-audit.md): manual-first opcode,
  privilege, flag and bus-side-effect review gate.
- [platform-requirements.md](platform-requirements.md): FPGA and external
  memory selection criteria.

## Naming

| Name | Meaning |
|---|---|
| MX68K | Architecture and project family |
| M00/M10/M20/M40 | Motorola-compatibility profiles |
| MXV | Vector extension |
| MXLE | Full little-endian execution extension |
| MXA | Extended atomic/memory-ordering extension |
| MXMP | Multiprocessor extension |

An implementation advertises a base profile and independent extension bits.
Custom instructions are never silently included in generic M40 mode.

## Current decisions

- Reset and the first implementation are big-endian.
- Full little-endian execution is reserved in the architecture, not implemented
  by byte swapping only the data bus.
- Logical and physical addresses are 32 bits.
- The internal memory transfer width is 128 bits, matching one M40 cache line.
- The first new CPU is in-order and single-issue with precise retirement.
- `third_party/fx68k` remains an unmodified M00 differential reference.
- The new design is not constrained by the legacy Tang Nano target.

## Source layout

```text
rtl/mx68k/
    mx68k_pkg.sv             shared architectural/fabric types
    mx68k_mem_if.sv          memory request/response interface
    compat/                  bridges for the inherited fx68k
    fabric/                  arbiters, decode and adapters
    core/                    fetch, decode and native M00 core
        backend/             architectural state and execution units
    cache/                   future I/D caches and coherence endpoint
    mmu/                     future MMUs, ATCs and table walker
    fpu/                     future floating-point pipeline
    vector/                  future MXV implementation
    models/                  simulation-only memories/devices

sim/mx68k/                   focused unit and integration tests
isa/                         machine-readable instruction descriptions
scripts/gen_mx68k_decode.py  validated decode-table generator
```

## Compatibility rule

Where MX68K claims M00/M10/M20/M40 compatibility, the Motorola/Freescale
manuals are authoritative. Project-specific behaviour must live behind a named
MX extension and a discoverable feature bit.
