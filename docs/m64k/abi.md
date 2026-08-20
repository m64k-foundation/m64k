# M64K LP64D ELF ABI

| Field | Value |
|---|---|
| Status | Normative draft; ELF numeric assignments and relocations are not frozen |
| Version | 0.2-development |
| Scope | Unified M64K v1 applications with mandatory scalar FP32/FP64 |
| Compatibility | Native objects have a distinct identity and are not M68K-compatible |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

LP64D defines 8/16/32/64-bit `char`/`short`/`int`/`long` and pointer widths, with IEEE-754 FP32 and FP64 available to the calling convention. Scalars use natural alignment up to 16 bytes. The stack grows downward and `r31` is 16-byte aligned at every public call boundary. There is no red zone or mandatory shadow space.

| Registers | Role | Preservation |
|---|---|---|
| `r0-r7` | Integer/pointer arguments; `r0-r1` return values | Caller-saved |
| `r8-r17` | Temporaries | Caller-saved |
| `r18-r27` | Saved registers | Callee-saved |
| `r28` | Thread pointer | Fixed |
| `r29` | Frame pointer when used | Callee-saved |
| `r30` | Link register | Caller-saved |
| `r31` | Stack pointer | Callee-restored |

A call always writes its following address to `r30`; return branches to `r30`. A non-leaf callee saves `r30` before making another call. Arguments beyond `r0-r7` use 8-byte stack slots. Results wider than 128 bits use a hidden result pointer in `r0`. B/W/L integer arguments and results are extended to 64 bits according to source-language signedness; ISA ordinary B/W/L writes remain zero-extending.

| Floating registers | Role | Preservation |
|---|---|---|
| `f0-f7` | FP arguments; `f0-f1` results | Caller-saved |
| `f8-f15` | FP temporaries | Caller-saved |
| `f16-f31` | Saved FP values | Callee-saved |

An aggregate of at most 16 bytes that is not a homogeneous floating aggregate is classified into one or two integer slots and passed or returned in `r0-r1` when those slots are available. A homogeneous FP32 or FP64 aggregate of one through four members uses `f0-f3`. All other aggregate results use a hidden structure-result pointer in `r0`; explicit integer arguments then begin at `r1`. Aggregates passed after their required register class is exhausted use naturally aligned stack slots.

A variadic caller allocates a 128-byte register save area in its outgoing argument frame: 64 bytes for `r0-r7`, followed by 64 bytes for `f0-f7`. The variadic callee spills every argument register that may contain an unnamed argument before the first `va_start`. `va_list` records the general-register offset, floating-register offset, overflow stack pointer, and register-save-area pointer. Named arguments consume registers normally; unnamed FP arguments remain classified in the FP area and are also recoverable through this save-area contract.

Condition flags, `X`, and predicate registers are caller-saved.

Native ELF uses ELFCLASS64 and ELFDATA2MSB with a distinct `EM_M64K` value obtained through the registry process. Relocations, TLS, PLT/GOT, DWARF numbering, and dynamic linking MUST be frozen before ABI 1.0; no provisional number is normative.

At process entry, `r31` addresses the standard 64-bit big-endian `argc`/`argv`/`envp`/auxv stack, `r0` contains `argc`, `r1` points to `argv`, and `r28` is the valid thread pointer. Syscalls place the number in `r8`, arguments in `r0-r5`, and results in `r0-r1`; exact error and restart behavior is frozen jointly with the Linux port.
