# M64K repository layout

| Field | Value |
|---|---|
| Status | Normative engineering policy |
| Version | 1.0 |
| Scope | Native hardware repository |
| Compatibility | Historical M68K work is retained in archive branches, not the active tree |

The active repository contains only native M64K product sources and technology-neutral infrastructure. Architecture, implementation, verification, platform integration, and physical implementation remain separate ownership domains.

```text
isa/native/          versioned machine-readable ISA and ABI contracts
model/m64k/          independent executable architectural model
docs/m64k/           normative specifications and engineering plans
rtl/packages/        minimal architecture-wide types with no higher-layer dependencies
rtl/core/            frontend, rename, scheduling, execution, and retirement implementation
rtl/core/execute/    typed execution units grouped by integer, shift, multiply/divide, branch, address-generation, floating-point, and microcode ownership
rtl/interfaces/      public protocols grouped by translation, physical memory, interrupt, retirement, debug, and control domains
rtl/memory/          MMU, TLB, caches, arrays, and memory bindings
rtl/coherence/       directory, protocol engines, and coherence properties
rtl/interconnect/    scalable transport, arbitration, and ordering points
rtl/soc/             board-neutral chip integration and system controllers
verification/model/  architectural-model tests
verification/formal/ formal properties and proof harnesses
verification/cdc/    clock/reset-domain inventories and crossing checks
verification/equiv/  RTL, synthesis, scan, and ECO equivalence flows
sim/                 native RTL simulation and platform models
firmware/            native Machine-mode boot and recovery firmware
asic/                synthesis, DFT, power, STA, and physical implementation
fpga/                vendor wrappers, constraints, and board integration
containers/          immutable tool environments
scripts/             validation, generation, and reproducible build tools
tools/sources/       ignored independent Linux, GCC, and binutils-gdb repositories
build/               ignored generated products
```

## Ownership rules

- ISA documents and machine-readable contracts define architectural behavior; RTL and tests cannot silently extend them.
- The architectural model does not share execution code with production RTL.
- Public RTL contracts carry core, hardware-thread, transaction, privilege, and address-space identity where their consumer requires it.
- Translation metadata terminates at the translation/client boundary. The physical coherent fabric carries only metadata consumed by physical routing, ordering, coherence, and completion.
- Simulation-only code never appears in synthesis manifests.
- Technology primitives remain behind reviewed memory, clock, reset, IO, and test wrappers.
- Target-specific FPGA and ASIC bindings must not leak into architectural RTL.
- Build products and external source repositories are never tracked in this repository.

## Historical work

The incomplete compatibility implementation is preserved by the local `archive/m00-compat-wip-2026-08-19` branch and tag. It is not copied into an `archive/` directory because doing so would expose obsolete sources to tools and automated agents. Historical files must not be restored to an active manifest or documentation index without a new project-owner decision.
