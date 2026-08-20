# M64K source-repository topology

| Field | Value |
|---|---|
| Status | Active engineering policy |
| Version | 1.0 |
| Scope | Hardware and native software stack |
| Compatibility | Every component uses a distinct native M64K target; no M68K backend is renamed |

M64K components remain independent Git repositories under the `m64k-foundation` organization. For efficient local development, their worktrees live under the ignored `tools/sources/` directory of the hardware workspace.

| Local path | Project repository | Adopted baseline | Active purpose |
|---|---|---|---|
| repository root | `m64k-foundation/m64k` | native branch | architecture, RTL, verification, firmware, FPGA, and ASIC flows |
| `tools/sources/binutils-gdb` | `m64k-foundation/binutils-gdb` | binutils 2.47 | BFD, ELF64, GAS, LD, disassembler, readelf, and later GDB |
| `tools/sources/gcc` | `m64k-foundation/gcc` | GCC 16.2 | freestanding compiler, libgcc, and later Linux compiler |
| `tools/sources/linux` | `m64k-foundation/linux` | Linux 6.18 | native `arch/m64k` after architecture/toolchain gates |

## Dependency order

1. Close the bidirectional MC68060 semantic-cut-line inventory.
2. Freeze the unified M64K v1 English contract and machine-readable encoding allocation.
3. Freeze M64K v1 ELF64/LP64D, relocations, DWARF, TLS, syscall, signal, and debug contracts.
4. Implement binutils static bare-metal support and exhaustive negative/relocation tests.
5. Implement GCC freestanding C and libgcc; add C++ only after unwind and ABI tests pass.
6. Execute native freestanding payloads against the independent model and RTL.
7. Implement firmware, MMU, atomics, interrupts, timer, and boot protocol.
8. Create `arch/m64k` and enable the Linux target only after those hardware-visible contracts are executable.
9. Fork and integrate musl when native Linux userspace is ready.

Newlib is introduced only if a hosted bare-metal environment becomes an actual requirement. uClibc-ng is not part of the current native plan.

## Upstream policy

- `origin` identifies the M64K Foundation fork. `upstream` is fetch-only and has a disabled push URL.
- Adopted release branches are never advanced by an unattended merge or rebase.
- An upstream update records the previous and new upstream commits, release identity, test results, generated-file differences, and local conflict resolutions.
- Hardware, ABI, toolchain, and kernel changes that depend on one another use a versioned cross-repository integration manifest before release.
- External repositories, object trees, installed toolchains, archives, and disk images remain ignored by the hardware repository.
- `make full-build` must eventually consume a reviewed integration manifest; a branch name alone is not a reproducible dependency pin.

## Backend boundary

M64K requires new architecture identities and backends. Code may reuse generic BFD, GAS, GCC, LLVM, GDB, and Linux infrastructure, but it must not obtain apparent support by copying and renaming M68K target files. `EM_M64K`, relocation numbers, instruction encodings, calling convention, DWARF numbering, and Linux audit identity must be assigned by their applicable registries or versioned specifications before being presented as stable.
