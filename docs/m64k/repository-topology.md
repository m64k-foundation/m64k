# M64K repository topology and upstream baselines

| Field | Value |
|---|---|
| Status | Active engineering policy |
| Version | 1.0 |
| Scope | M64K hardware, firmware, operating systems, toolchains, and C libraries |
| Compatibility | Repository policy only; no ISA or ABI contract is created here |

The M64K ecosystem uses separate repositories under `m64k-foundation`. Keeping upstream-derived projects separate preserves their history, licenses, review flow, and ability to rebase or merge from upstream. A local workspace may check them out as siblings for integrated builds; they must not be copied into the hardware Git history.

## Repository ownership

| Repository | Responsibility | Initial upstream |
|---|---|---|
| `m64k-foundation/m64k` | ISA specification, RTL, verification, board support, reference firmware, integration metadata | This repository |
| `m64k-foundation/linux` | Linux architecture port, platform drivers, Kconfig, device tree/boot protocol, SMP and ABI support | `torvalds/linux` plus the Linux stable remote |
| `m64k-foundation/gcc` | M64K target backend, machine descriptions, ABI, builtins, vectorization, multilibs, tests | `gcc-mirror/gcc` |
| `m64k-foundation/binutils-gdb` | assembler, linker, ELF ABI, relocations, disassembler, simulator-independent GDB architecture support | Sourceware `binutils-gdb` |
| `m64k-foundation/newlib-cygwin` | bare-metal C library and target integration | Sourceware `newlib-cygwin` |
| `m64k-foundation/uclibc-ng` | compact Linux C library port | `wbx-github/uclibc-ng` |
| `m64k-foundation/musl` | native M64K Linux ABI and libc port | upstream musl |

## Initial branch points

The following baselines were selected on 2026-08-19. Each fork should retain an unmodified upstream tracking branch and create an M64K development branch from the named point.

| Project | Baseline | Development branch | Upstream remote |
|---|---|---|---|
| Linux | `v6.18.44` from the 6.18 LTS series | `m64k-6.18.y` | `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git` |
| Linux forward work | current upstream `master` | `m64k-mainline` | `https://github.com/torvalds/linux.git` |
| GCC | `releases/gcc-16.2.0` | `m64k-gcc-16` | `https://github.com/gcc-mirror/gcc.git` |
| GCC forward work | current upstream `master` | `m64k-mainline` | `https://github.com/gcc-mirror/gcc.git` |
| binutils-gdb | `binutils-2_47` | `m64k-binutils-2.47` | `https://sourceware.org/git/binutils-gdb.git` |
| binutils-gdb forward work | current upstream `master` | `m64k-mainline` | `https://sourceware.org/git/binutils-gdb.git` |
| newlib-cygwin | `newlib-4.6.0.20260123` | `m64k-newlib-4.6` | `https://sourceware.org/git/newlib-cygwin.git` |
| uClibc-ng | `v1.0.59` | `m64k-1.0.y` | `https://github.com/wbx-github/uclibc-ng.git` |
| musl | `v1.2.6` | `m64k-1.2.y` | `https://git.musl-libc.org/git/musl` |

Linux 6.18 LTS is the bring-up and stabilization base, not a permanent fork point. Architecture work must be kept mergeable into current mainline. GCC and binutils likewise maintain a release-based bootstrap branch and a continuously forward-ported mainline branch so the project does not accumulate an unmergeable toolchain delta.

## Local workspace

A recommended developer layout is:

```text
workspace/
    m64k/               hardware, ISA, firmware, and integration
    linux/              m64k-foundation/linux
    gcc/                m64k-foundation/gcc
    binutils-gdb/       m64k-foundation/binutils-gdb
    newlib-cygwin/      m64k-foundation/newlib-cygwin
    uclibc-ng/          m64k-foundation/uclibc-ng
    musl/               m64k-foundation/musl
    build/              disposable out-of-tree builds
    toolchains/         installed cross toolchains
    images/             kernels, root filesystems, and disk images
```

The hardware repository may provide manifests, version-lock metadata, CI scripts, patches that are not yet upstreamed, and cross-repository test drivers. It must not vendor full source trees or generated toolchains. Local paths are configuration inputs and must not become fixed absolute paths in tracked files.

## Cross-repository dependency order

1. Freeze the initial ELF machine identity, byte order, scalar data model, register numbering, relocation model, and calling convention in the M64K ABI specification.
2. Add binutils assembler, linker, ELF, relocation, and disassembler support.
3. Add GCC freestanding code generation and compiler tests, initially using newlib.
4. Add firmware entry, discovery, exception, timer, interrupt, and SMP boot contracts in this repository.
5. Add the Linux architecture port and early console using the release-based Linux branch.
6. Add uClibc-ng for constrained systems and musl for the primary native userspace ABI.
7. Add vector and matrix compiler intrinsics before enabling automatic vectorization; enable automatic vectorization only after semantics and cost models are stable.

M68K-compatible binaries continue to use the existing big-endian M68K ELF ABI. Native M64K uses a distinct ELF machine/ABI identity. A single executable must never be ambiguously interpreted as both architectures.

## Integration contract

Every cross-repository revision used by CI or a release is recorded by immutable commit ID in a manifest. The manifest also records the ISA version, ABI version, platform version, compiler target triple, multilib profile, and required simulator/FPGA feature set. Changes that require coordinated updates land behind feature detection and preserve a bisectable combination of repositories.
