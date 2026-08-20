# M64K

M64K is an open, synthesizable native 64-bit processor and system architecture designed for high-performance FPGA prototypes and eventual ASIC implementation. The architecture targets out-of-order superscalar execution, virtual memory, IEEE-754 floating point, directory-based cache coherence, multiprocessing, simultaneous multithreading, and future scalable-vector and matrix extensions.

M64K is a new ISA. It does not execute M68K binaries and does not reuse the M68K ELF ABI, effective-address modes, exception frames, bus protocol, or processor modes. The complete MC68060 computational instruction inventory is the semantic floor for M64K v1, but every operation uses native 64-bit registers, operand forms, encodings, traps, and memory semantics. Programs must be assembled or compiled specifically for M64K.

## Current status

The project is establishing the unified M64K v1 architecture and implementation contracts. No native processor core, toolchain backend, firmware, or Linux port is complete yet. A historical M00 compatibility implementation is preserved on the local archive branch and tag `archive/m00-compat-wip-2026-08-19`; it is not part of the active product or default build.

The first product configuration targets:

- four cores and two simultaneous hardware threads per core;
- a four-wide out-of-order core with precise retirement;
- 48-bit canonical virtual addresses and a discoverable 36-to-48-bit physical-address width behind a 64-bit architectural address model;
- private L1 instruction/data and unified L2 caches;
- a shared banked L3 cache with directory-based MESI coherence;
- a scalar IEEE-754 binary32/binary64 FPU with fused multiply-add;
- a big-endian LP64D software ABI;
- technology-independent RTL with explicit FPGA and ASIC memory/cell bindings.

These are design targets, not implementation claims. Frequency, area, power, cache capacity, and queue sizing remain subject to reproducible synthesis, timing, placement, routing, and workload measurements.

## Repository layout

```text
isa/native/          versioned machine-readable ISA and ABI contracts
docs/m64k/           normative architecture and implementation documentation
rtl/core/            native core and architectural contract RTL
rtl/packages/        minimal architecture-wide RTL types
rtl/interfaces/      SMP/SMT-aware memory, interrupt, and retirement interfaces
rtl/memory/          cache, MMU, TLB, and technology-neutral memory integration
rtl/coherence/       directory and coherence protocol RTL
rtl/interconnect/    scalable on-chip transport
rtl/soc/             board-neutral system integration
verification/        formal, differential, coverage, CDC/RDC, and equivalence collateral
sim/                 architectural and RTL simulation
asic/                synthesis, DFT, power, timing, and physical-flow integration
fpga/                target-specific FPGA wrappers and constraints
firmware/            native Machine-mode boot firmware
scripts/             contract validation and generated-artifact tools
tools/sources/       ignored Linux, GCC, and binutils-gdb worktrees
```

Large build products, toolchains, source checkouts, FPGA outputs, traces, and disk images are not tracked.

## Architecture baseline

- 32 writable unified 64-bit general-purpose registers.
- Fixed 32-bit base instruction encoding aligned to four bytes.
- `.B`, `.W`, and `.L` register writes zero-extend; `.Q` writes all 64 bits.
- Explicit signed loads and signed widening operations.
- Hybrid condition model with renameable NZCV, scalar predicates, and a separate explicit `X` carry-chain state.
- User, Supervisor, and Machine privilege levels.
- CSR-based precise trap state rather than hardware-created variable stack frames.
- TSO memory ordering and coherent 8/16/32/64-bit atomic operations.
- A single ELF64 big-endian LP64D ABI. M64K will request a distinct official ELF machine identifier and will never reuse `EM_68K`.

The complete normative contracts, rationale, and implementation gates are indexed from [docs/m64k/README.md](docs/m64k/README.md).

## Current validation

Run the complete native-contract development gate with:

```sh
make check
```

It validates the M64K v1 machine-readable contract, executes the independent scalar semantic model tests, lints every native RTL interface with all Verilator warnings fatal, verifies the structural integrity of the still-draft semantic-cut-line inventory, and verifies the persistent primary-manual cache. This gate does not claim that the semantic audit is closed.

RTL tests are compiled incrementally per execution-unit cluster. Re-running `make rtl-execute-test` executes the current integer semantics, tagged integer execution, ordinary shift/rotate, iterative rotate-through-X, multiply, and divide matrices without rebuilding unchanged Verilator models. Clean compilation uses bounded parallel C++ jobs through `VERILATOR_BUILD_JOBS` and must not regress into one separately compiled whole-core executable per test case. Test executables are built under a `.pending` name, validated as executable ELF files, synchronized, and atomically published so an interrupted build cannot replace the last valid binary with a zero-length or partial artifact.

Official manuals are cached under the ignored `references/manuals/` directory because their copyright does not grant this project redistribution rights. Restore or verify the exact reviewed documents using their official URLs and recorded SHA-256 values:

```sh
make manuals-fetch
make manuals-check
```

`make full-build` is intentionally blocked until the instruction encoding, semantic-lineage matrix, official ELF identity, relocation ABI, binutils backend, and compiler backend are complete. It never substitutes an M68K toolchain or payload to report false progress.

The silicon-frontend gate uses the immutable ORFS container recorded in `containers/asic/tool-lock.json`; no host Slang, Yosys, OpenROAD, or OpenSTA installation is required:

```sh
make asic-tools
make silicon-frontend-check
```

The current frontend targets perform independent Slang elaboration and generic Yosys/ABC synthesis of the native scalar integer ALU, its tagged registered execute pipe, shift/rotate alternatives, pipelined multiplier, and iterative divider. They record input, flow, and output hashes together with structural counts under ignored `build/asic/`.

Target-owned Nangate45 OpenROAD configurations and SDCs now exercise the real multiplier and divider clocked RTL through placement, clock-tree synthesis, routing, extraction, STA, IR analysis, and GDS generation. The first runs are explicitly rejected because the independent fatal log audit found unresolved diagnostics; their preliminary measurements are not accepted PPA or frequency claims. See [asic/physical/README.md](asic/physical/README.md) and the dated rejected-evidence report before running the physical targets.

## Software repositories

The supported local workspace keeps independent upstream-derived repositories under `tools/sources/`:

```text
tools/sources/linux          Linux 6.18 development line
tools/sources/gcc            GCC 16.2 development line
tools/sources/binutils-gdb   binutils 2.47 development line
```

Native binutils support begins only after the closed MC68060 cut-line inventory, instruction encodings, ELF identity, relocations, and psABI are frozen. GCC follows a working assembler/linker/disassembler. Native firmware and a freestanding payload follow the toolchain; `arch/m64k` is created only after the hardware-visible exception, MMU, atomic, and boot contracts execute correctly. Musl will be introduced for native Linux userspace when that milestone is reached.

## Engineering policy

- Architecture is specified before RTL or toolchain implementation.
- One assembly statement encodes one architectural instruction; hidden multi-instruction expansion cannot claim ISA coverage.
- Common instructions decode directly to typed uops, while complex architectural instructions may use reviewed internal microcode.
- Tests and software traces are evidence, never architectural specifications.
- First-party warnings are errors.
- Unsupported encodings trap; the project does not add fake feature paths or placeholder implementations.
- Architectural effects become visible only at precise retirement.
- All public interfaces identify core, hardware thread, transaction, privilege, and address space where relevant.
- Performance changes require timing, area, power, and equivalence evidence.
- Open PDK results are exploratory and never presented as production-foundry sign-off.

See [AGENTS.md](AGENTS.md) for the mandatory contribution and review rules.

## Licensing

First-party project code is MIT licensed unless a file states otherwise. External repositories and dependencies retain their own licenses.
