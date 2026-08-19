# Mackerel ISA extensions and compiler work

Custom instructions belong after the M68040-compatible baseline. Keeping the
standard profile intact gives every extension a known fallback, makes compiler
regressions measurable and prevents project-specific behaviour from being
confused with Motorola compatibility.

## One source of truth

Do not independently hand-code the RTL decoder, assembler and compiler tables.
Define each extension in a machine-readable ISA database containing:

- stable extension name and version;
- opcode mask/value and extension words;
- operands, sizes, addressing modes and privilege;
- pseudocode semantics;
- exact X/N/Z/V/C and FP status effects;
- traps, faults, restart and memory ordering;
- latency, throughput, pipeline resources and hazards;
- required architectural registers and save/restore rules;
- assembler syntax and canonical disassembly;
- feature-discovery bit and illegal-instruction fallback.

Generators should produce decode constants, assembler/disassembler tables,
documentation skeletons and directed test vectors. The handwritten RTL remains
reviewable, but its encoding must be checked against the same database.

## Encoding policy

The baseline must preserve all legal 68040 encodings. Potential extension space
must be audited against:

- Line A emulator conventions;
- Line F FPU/coprocessor encodings;
- currently illegal/reserved encodings;
- future multiword prefixes;
- debugger and operating-system expectations.

Line F is not generally free once the 68040 FPU exists. Line A can provide a
clean extension prefix but historically traps to an emulator. Whichever space
is chosen needs a versioned architectural decision record and a guaranteed
illegal-instruction/emulation path on CPUs lacking the feature.

## Capability discovery

Define a read-only CPU identification and feature-register block, preferably
through privileged control registers rather than magic MMIO. It should expose:

- architecture baseline;
- extension bitmap and versions;
- cache line/capacity information;
- MMU page sizes and ATC capabilities;
- FPU profile;
- core count and coherency features.

Software must never infer an extension solely from clock rate or board model.

## Toolchain order

### 1. Reference semantics and tests

Before syntax exists, implement an independent executable semantic model and
random/directed vectors. RTL and toolchain tests consume the same cases.

### 2. Binutils opcode library, GAS and objdump

Add CPU/extension feature flags, encoding/operand rules, canonical assembly,
disassembly and negative tests. Linker work is needed if an extension adds new
relocations, relaxation rules or ELF attributes.

GNU `as` already models M680x0 processor selection and extensions; the project
should add a named Mackerel architecture/extension rather than enabling custom
opcodes under generic `-m68040`:
<https://sourceware.org/binutils/docs/as/M68K_002dOpts.html>

### 3. Intrinsics and builtins

Expose instructions explicitly first. This allows C tests and libraries to use
the feature without trusting compiler pattern selection. Builtins must specify
side effects, volatility, memory clobbers and fault behaviour accurately.

### 4. GCC machine description

Only after assembly and semantics are stable, teach GCC automatic selection.
The m68k backend will need some combination of:

- new `-mcpu`/`-march`/`-m` feature options and preprocessor macros;
- instruction patterns in the machine-description files;
- predicates and operand constraints;
- expanders, splits and peepholes;
- condition-code modelling;
- instruction attributes, latency and scheduling;
- cost model and address legitimization;
- builtins and target hooks;
- multilib selection and testsuite cases.

GCC's official internals manual describes `.md` patterns as the target's
instruction-selection contract:
<https://gcc.gnu.org/onlinedocs/gccint/Machine-Desc.html>

### 5. ABI, runtime, kernel and debugger

New instructions that only transform existing D/A registers may preserve the
ABI. New vector, predicate, FP or system registers can require:

- calling convention and callee/caller-save rules;
- stack alignment and argument/return classification;
- ELF attributes so incompatible objects cannot be silently linked;
- DWARF register numbers and unwind rules;
- GDB register descriptions and ptrace support;
- signal-frame and context-switch state in the kernel;
- lazy/eager state ownership rules;
- libc/compiler-runtime optimized routines.

This is why adding architectural registers is much more expensive than adding
a pure operation over existing registers.

## Extension classes ranked by integration cost

| Class | Example | Toolchain/OS impact |
|---|---|---|
| Existing-register ALU | bit operations, saturating arithmetic | Low to medium |
| Memory/atomic | wider CAS, barriers, prefetch | Medium; memory model critical |
| Multiply/crypto DSP | fused integer operations | Medium; constraints/cost model |
| Control/system | TLB/cache/core control | High; privilege/kernel semantics |
| New register file | SIMD/vector/predicate | Very high; ABI/debug/context switch |
| New address width/model | >32-bit physical or capabilities | Architectural fork |

## Compatibility policy

Each extension should support one of these explicit deployment modes:

1. baseline binary with runtime dispatch;
2. extension-specific binary carrying an ELF feature requirement;
3. trap-and-emulate fallback for correctness, not performance;
4. kernel-only privileged feature.

Never silently emit a Mackerel opcode for `-m68040`. Use an explicit target such
as `-mcpu=mackerel-v1` or `-mext-<name>` once the naming is standardized.

## Compiler validation

For every instruction pattern:

- assemble/disassemble round trip;
- exact encoding golden vectors;
- positive and negative operand tests;
- RTL versus semantic-model randomized execution;
- GCC scan-assembler tests proving when it is and is not selected;
- runtime tests at optimization levels O0/O1/O2/O3/Os;
- aliasing, volatile, exception and memory-order tests;
- old-core illegal-instruction/fallback tests;
- ABI interoperability between extended and baseline objects.

Compiler-generated code is not evidence that hardware is correct, and hardware
passing hand-written assembly is not evidence that compiler constraints are
correct. Both directions require independent oracles.
