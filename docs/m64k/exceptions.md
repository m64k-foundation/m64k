# M64K precise traps and exceptions

| Field | Value |
|---|---|
| Status | Normative draft |
| Version | 0.2-development |
| Scope | M64K v1 synchronous traps, interrupts, and restart behavior |
| Compatibility | Native CSR traps; no Motorola vector table or hardware stack frames |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

An exception is precise when all older instructions have completed their permitted effects, the faulting instruction has produced no uncommitted effect, and no younger instruction has changed architectural state. Out-of-order implementations MUST present the same boundary.

Priority is reset/fatal machine check, oldest synchronous fault, explicit trap or syscall, debug event, non-maskable interrupt, then maskable interrupt. Instruction address and translation precede decode; illegal encoding precedes operand access; privilege precedes state mutation; data canonicality, translation, permission, and alignment precede a memory request.

Synchronous faults save the faulting `PC`; explicit traps save the following `PC`; interrupts save the next instruction to execute. Trap entry writes the CSRs defined by [privilege.md](privilege.md). Hardware MUST NOT write a stack frame, select a dedicated privilege stack, or fetch a handler pointer from a memory vector slot.

Required M64K v1 causes include instruction address/access, illegal instruction, privilege violation, breakpoint, syscall, load/store address/access, instruction/load/store page faults, atomic alignment/type, divide by zero, enabled scalar floating-point traps, and machine check. Numeric cause assignments are frozen with the machine-readable ISA contract.

Ordinary instructions restart at `tpc`. A multi-access instruction MUST specify any externally visible checkpoint. Retired stores awaiting M64K v1 TSO visibility cannot later generate a precise instruction fault; an attributable late failure is a machine check. Trap return validates all CSR state before a single architectural restoration.

Conformance covers every cause, priority collision, CSR field, nested escalation, invalid return, speculative suppression, interrupt boundary, translation-walk failure, atomic contention, and both SMT threads trapping concurrently.
