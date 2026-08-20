# M64K privilege and trap architecture

| Field | Value |
|---|---|
| Status | Normative draft |
| Version | 0.2-development |
| Scope | M64K v1 U/S/M privilege and translation control |
| Compatibility | Native control state; privilege H is reserved |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Privilege modes

User (`U`), supervisor (`S`), and machine (`M`) are implemented. `U` runs applications, `S` runs an operating-system kernel, and `M` controls physical platform state and fatal recovery. Hypervisor (`H`) encodings and state are reserved and MUST trap as illegal until a virtualization extension is specified.

## Control state

Each hardware thread owns current privilege, interrupt enable and threshold, `ASID`, translation root, trap-vector base, and trap CSRs. Control registers have a specified minimum privilege, writable mask, reset value, and serialization class. Unknown registers or reserved writes trap as illegal; insufficient privilege traps as a privilege violation.

Reset starts core 0 thread 0 in M mode with interrupts and translation disabled. Other contexts are held. `PC`, `r31` (SP), and the platform argument come from the reset descriptor. All other integer registers are unspecified and firmware initializes them before entering S or U mode.

## CSR trap contract

Trap entry writes CSRs rather than a hardware stack frame. At minimum the selected target mode receives:

- `tpc`: restart or following PC;
- `tcause`: interrupt bit and cause;
- `tval`: fault address, instruction word, or zero;
- `tstatus`: prior privilege, interrupt state, `NZCV`, `X`, predicates, and architecturally required status;
- `tasid`: prior address-space identity;
- `tinst`: complete first 32-bit instruction word and extension length metadata.

Entry writes this state atomically, changes privilege and interrupt state, and sets `PC` to `tvec_base + cause_offset`. `tvec_base` and the cause offset are addresses computed internally; no vector-table memory slot is fetched. Software chooses and manages its own stack using ordinary registers. There are no dedicated hardware privilege stacks.

Nested traps require software to save trap CSRs before re-enabling a same-target trap. A trap while trap state is unavailable escalates to M mode; failure in the M-mode fatal path halts the hardware thread and reports platform-visible fatal state.

Trap return validates saved privilege, canonical target, alignment, feature state, and translation state before atomically restoring control. It does not read a memory frame. Translation-root changes, TLB/cache maintenance, trap return, core release, and thread enable/disable are serializing at their defined scope.

## Interrupts

Interrupt requests carry identity, priority, target privilege, core, and thread or any-thread policy. Maskable interrupts are accepted between retired instructions only when enabled and above the threshold. Non-maskable interrupts and machine checks target M mode. Pending requests remain stable until acknowledged and re-routing cannot lose an event.
