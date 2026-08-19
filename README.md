# M64K

M64K is an open, synthesizable processor and system architecture. It begins with rigorously audited Motorola 68000-family compatibility profiles and evolves into a native 64-bit ISA with wider addressing, virtual memory, floating point, scalable vectors, matrix operations, coherent multiprocessing, and simultaneous multithreading.

The current first-party RTL is an in-order M00 implementation under active conformance work. It executes substantial portions of the MC68000 ISA, but the machine-readable audit still contains partial contracts. Passing software workloads does not make a processor profile complete. M10, M20, M30, M40, M60, native M64K, M64K-V, M64K-M, SMP, and SMT are roadmap targets rather than current feature claims.

Reset and current execution are big-endian. Native M64K will be a distinct 64-bit execution domain; existing M68K binaries retain their documented 32-bit behavior. The initial native target uses 48-bit canonical virtual addresses and parameterized 32–48-bit physical addresses. Full little-endian execution remains a separately specified future extension.

## Repository layout

```text
rtl/m64k/        board-neutral production RTL
sim/m68k/m00/        Verilator unit, matrix, fault, and integration tests
isa/             machine-readable instruction and audit contracts
docs/m64k/       architecture, implementation, and verification documents
scripts/         decoder generation and conformance-audit tools
third_party/     unmodified external reference IP
tools/           ignored local downloads and tool installations
```

Platform-specific RTL, vendor projects, firmware, and operating-system integration will be added only against the board-neutral M64K platform contract. The removed predecessor-board implementation is not part of this repository's active architecture.

## Build and verification

Verilator 5 or newer and Python 3 are required.

```sh
make
```

The default target runs the first-party M64K regression. It does not build any retired board target.

Focused consistency gates are also available:

```sh
make decode-check
make audit-check
make -C sim/m68k/m00 lint
```

`decode-check` proves that the generated SystemVerilog decoder matches the declarative ISA database. `audit-check` verifies inventory counts, format ownership, evidence fields, and implementation status. `make -C sim/m68k/m00 test` runs the complete current Verilator suite, including opcode matrices, effective-address aliases, exception paths, injected bus faults, memory ordering, and precise-state suppression.

Build artifacts are written under `build/` and are not tracked.

## Current verification status

The M00 audit is intentionally conservative:

```sh
make audit-check
```

At the current repository state it inventories 152 decoder patterns and 56 instruction formats. A format is marked `verified` only when its full documented M00 contract is covered; any missing legal encoding, effective address, flag, privilege, exception, alignment, or injected-fault dimension keeps it `partial`.

The MC68000 Programmer's Reference Manual, MC68000 User's Manual, and applicable Motorola/NXP errata are the primary sources for compatibility behavior. Tests, existing RTL, compiler output, and observed software behavior are supporting evidence only.

## Architecture and roadmap

- [Architecture documentation](docs/m64k/README.md)
- [Architecture direction](docs/m64k/architecture.md)
- [Implementation plan](docs/m64k/implementation-plan.md)
- [M00 conformance audit](docs/m64k/m00-conformance-audit.md)
- [Repository and upstream topology](docs/m64k/repository-topology.md)
- [FPGA platform requirements](docs/m64k/platform-requirements.md)

The hardware repository is `m64k-foundation/m64k`. Linux, GCC, binutils-gdb, newlib-cygwin, uClibc-ng, and musl use separate upstream-derived repositories under the same organization. Exact initial branch points and ownership boundaries are documented in the repository topology.

## Licensing

First-party project code is MIT licensed unless a file states otherwise. The vendored `fx68k` reference core is GPLv3. Every third-party component retains its own copyright and license terms.
