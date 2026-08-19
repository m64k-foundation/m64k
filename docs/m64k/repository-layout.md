# M64K repository layout

| Field | Value |
|---|---|
| Status | Normative engineering layout |
| Version | 1.0 |
| Scope | Ownership and placement of RTL, verification, firmware, FPGA, ISA, and integration files |
| Compatibility | File placement does not change an architectural profile or ABI |

This document defines subsystem ownership. New files must be placed according to architectural responsibility rather than the project name alone. In particular, an M68K-compatible core is not native M64K RTL merely because it belongs to the M64K project.

## Top-level layout

```text
rtl/                    synthesizable first-party RTL
sim/                    testbenches, simulation models, reference adapters, and harnesses
isa/                    machine-readable instruction and audit contracts
firmware/               first-party boot and diagnostic software
fpga/                   vendor/board build adapters selected from measured targets
docs/m64k/              architecture and engineering specifications
scripts/                reproducible generation, audit, and integration tools
third_party/            unmodified externally maintained source
tools/                  ignored local downloads and tool installations
```

Generated build products belong under `build/` and are never tracked.

## Production RTL

```text
rtl/
├── lib/                        architecture-neutral reusable primitives
│   ├── fifo/
│   ├── arbitration/
│   ├── memory/
│   └── utility/
├── interconnect/               transaction and transport contracts
│   ├── interfaces/
│   ├── routing/
│   ├── arbitration/
│   ├── bridges/
│   ├── ordering/
│   └── coherence/
├── m68k/                       Motorola-compatible execution domains
│   ├── common/                 explicitly shared compatibility semantics
│   ├── m00/
│   │   ├── frontend/
│   │   ├── decode/
│   │   ├── execute/
│   │   ├── backend/
│   │   └── core/
│   ├── m10/
│   ├── m20/
│   ├── m30/
│   ├── m40/
│   └── m60/
├── m64k/                       native 64-bit execution domain only
│   ├── architecture/
│   ├── frontend/
│   ├── decode/
│   ├── rename/
│   ├── schedule/
│   ├── execute/
│   ├── retirement/
│   ├── lsu/
│   ├── mmu/
│   ├── fpu/
│   ├── vector/
│   ├── matrix/
│   ├── coherence/
│   └── debug/
└── soc/                        board-neutral system integration
    ├── common/
    ├── boot/
    ├── interrupt/
    ├── peripherals/
    └── topology/
```

Directories are created when they obtain a complete implementation or specification-owned source. Empty roadmap directories and placeholder modules are prohibited.

### Ownership rules

- `rtl/lib` contains reusable hardware without M68K or M64K architectural state.
- `rtl/interconnect` owns ready/valid transport, transaction identity, routing, arbitration, ordering metadata, bridges, and coherence messages. Architectural cores consume these contracts but do not redefine them.
- `rtl/m68k` owns only compatibility behavior defined by the corresponding Motorola/NXP profile. Common code moves to `rtl/m68k/common` only after at least two profiles share the identical documented contract.
- `rtl/m64k` owns only the native 64-bit ISA. M00/M10/M20/M30/M40/M60 implementations must never be placed there.
- `rtl/soc` owns software-visible platform integration that is independent of a particular FPGA board. Peripherals require a documented register contract and complete protocol/error behavior.
- Vendor primitives, PLLs, pin constraints, DDR wrappers, and programming scripts belong under `fpga/<vendor>/<board>`.

Simulation-only `$display`, host files, terminal handling, behavioral disk images, unrestricted memory arrays, fault injectors, and workload shortcuts are prohibited under `rtl`.

## Verification layout

```text
sim/
├── common/                     reusable scoreboards, assertions, and reference functions
├── models/                     behavioral memories and devices
│   ├── memory/
│   └── peripherals/
├── interconnect/               protocol, routing, ordering, and coherence verification
├── m68k/
│   ├── common/
│   └── m00/                    current M00 unit, matrix, fault, and integration suite
├── m64k/                       future native-ISA verification
├── soc/                        platform and firmware integration
└── reference/                  optional external differential/reference harnesses
    └── fx68k/
```

The current regression Makefile remains with the M00 suite while that suite is the only implemented execution domain. Shared tests migrate to their owning directory when a second client exists or when the interconnect obtains an independent regression target.

## Firmware layout

```text
firmware/
├── common/                     freestanding routines with no execution-domain dependency
├── m68k/
│   └── m00/                    reset, exception, and compatibility bring-up
└── m64k/                       native entry, ABI, and later multiprocessor boot
```

Firmware must use versioned platform headers generated or reviewed against `docs/m64k/platform.md`. A firmware image that only emits a test byte is not a boot milestone. The first accepted image must validate platform identity, initialize required architectural state, exercise the documented console and timer path, report failures, and enter a documented monitor or payload handoff.

## Migration map

| Previous location | Canonical destination |
|---|---|
| `rtl/m64k/core/*` | `rtl/m68k/m00/*` |
| `rtl/m64k/m64k_pkg.sv` | `rtl/interconnect/interfaces/m64k_pkg.sv` |
| `rtl/m64k/m64k_mem_if.sv` | `rtl/interconnect/interfaces/m64k_mem_if.sv` |
| `rtl/m64k/m64k_irq_if.sv` | `rtl/interconnect/interfaces/m64k_irq_if.sv` |
| `rtl/m64k/fabric/m64k_router_3.sv` | `rtl/interconnect/routing/m64k_router_3.sv` |
| `rtl/m64k/compat/fx68k_mem_bridge.sv` | `rtl/interconnect/bridges/fx68k_mem_bridge.sv` |
| `rtl/m64k/models/*` | `sim/models/*` |
| `rtl/m64k/platform/*` | `rtl/soc/peripherals/*` after complete contract verification |
| `sim/m64k/*` | `sim/m68k/m00/*` for the existing compatibility suite |

Module names retain the `m64k_` project prefix during this migration to avoid mixing file ownership with public identifier changes. Native and compatibility module naming will be versioned separately before an external RTL integration API is frozen.

## Change gate

A layout change must update this document, affected build files, scoped `AGENTS.md` instructions, and all path references in the same change. The complete owning regression must pass after a move. A path migration must not be combined with semantic RTL changes unless the semantic change is required to preserve a documented interface.
