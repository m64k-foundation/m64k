# M64K semantic-lineage audit

| Field | Value |
|---|---|
| Status | Normative architecture-development gate |
| Version | 0.2-development |
| Scope | Every M64K v1 instruction and software-visible system contract |
| Compatibility | The MC68060 is a historical audit baseline, not an ISA, ABI, or binary-compatibility profile |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Purpose and authority

M64K is a new native architecture. The Motorola MC68060 semantic corpus is the mandatory semantic cut line against which every proposed instruction and system facility is audited. This requirement provides a disciplined record of what M64K preserves, deliberately changes, rejects, or invents; it does not import MC68060 encodings, register layouts, exception frames, privilege state, ABI behavior, or binary compatibility.

No behavior becomes normative M64K behavior merely because it appears in a Motorola manual. M64K behavior is normative only after it is adopted in the English M64K specification, represented in the machine-readable contract, assigned to a version/profile, and accepted through the required verification gate. Where a proposal rejects or changes the historical behavior, the M64K specification controls.

Tests, emulators, existing RTL, compiler output, and observed software are verification evidence and MUST NOT replace the primary-document audit.

## Required source set

The primary cut-line baseline is the official Motorola or NXP MC68060 user's manual, together with the M68000 Family Programmer's Reference Manual for the instruction semantics delegated by that user manual, and all applicable published addenda and errata. Each audit entry MUST record the exact manual title, document identity, revision, section, and page range used.

An MC68060 manual may delegate a definition to an earlier generation, remove an earlier facility, or describe behavior only by contrast. In those cases, the audit MUST also consult and cite the applicable official MC68000, MC68020, MC68030, or MC68040 programmer's reference or user's manual and its errata. Earlier manuals are supporting primary sources only where the MC68060 lineage requires them; they do not independently expand the M64K contract.

If official sources disagree or leave a behavior ambiguous, the audit MUST quote no more than the minimal identifying phrase, describe the ambiguity in original words, and record the explicit M64K decision and rationale before implementation.

### Baseline document identities

The versioned [reference-manual manifest](../../references/manuals/manifest.json) is the sole authoritative list of reviewed document identities, official download locations, revisions, page counts, identity markers, and SHA-256 digests. It includes the MC68060 cut-line documents, the family programmer's reference, and the earlier-generation manuals and errata required when MC68060 material delegates, removes, or changes a contract. PDF files are local review inputs and MUST NOT be committed.

The MC68060 manual itself identifies the M68000 Family Programmer's Reference Manual as the source of the complete family instruction set. Instruction audits therefore cite both documents when the user manual supplies processor-specific execution, MMU, cache, FPU, or exception behavior while the programmer's reference supplies instruction semantics.

## Per-contract lineage matrix

Every computational instruction family in the closed MC68060 inventory MUST have a disposition even before an M64K encoding is allocated. Every M64K instruction, CSR, trap cause, privilege transition, MMU operation, atomic, fence, cache-maintenance operation, and other software-visible system facility MUST also have a lineage row. The two inventories are independent and bidirectionally cross-referenced; deriving either inventory from allocated opcodes is forbidden. One row may cover a family only when every listed member has identical behavior for every required field.

| Field | Required content |
|---|---|
| M64K contract identity | Stable instruction/system identifier, profile or extension, and specification version |
| Primary source | Official manual title, document identity, revision, section, and exact page range |
| Additional lineage source | Exact MC68000/20/30/40 citation when the MC68060 delegates, removes, or differs; otherwise `not required` |
| Disposition by dimension | One of `adopted`, `modified`, `rejected`, `new`, or `not-applicable` for encoding, widths, state, operand evaluation, result, conditions, memory, exceptions, restart, privilege, ABI, and implementation |
| Architectural identity | Distinct native instruction, one-to-one alias with a resolved identical target, native system facility, or rejected historical facility |
| Lowering strategy | Direct typed uops, reviewed microcode, no execution, or explicitly unresolved pending PPA and semantic review |
| Exact semantic differences | Complete M64K-versus-lineage differences, including widths, registers, encoding-independent state, and removed behavior |
| Flags and predicates | Reads and writes of `NZCV`, persistent `X`, and `p0-p7`; non-sticky/sticky behavior and preserved state |
| Operand evaluation | Source/destination evaluation order, address calculation, aliasing, and partial-completion checkpoints |
| Exceptions | Cause priority, saved `PC`, trap CSR values, restart point, and illegal/privilege behavior |
| Memory behavior | Access ordering, atomicity, alignment, endian interpretation, memory side effects, and fault timing |
| Privilege and context | Legal modes, serialization, per-thread state, context-switch requirements, and absent-feature behavior |
| Rationale | Why the historical behavior was adopted, modified, rejected, or why a new facility is necessary |
| Verification | Directed, matrix, negative, exception, fault-injection, reference-model, and formal evidence required |

`Adopted` means the identified semantic property is intentionally retained after translating it into native M64K state and terminology. `Modified` requires every difference to be stated. `Rejected` records that the historical behavior was considered and intentionally excluded. `New` records that no applicable Motorola semantic ancestor was found after the required source review. `Not-applicable` requires a reviewed reason and cannot be used as a generic escape.

Each reviewed row records three separate decisions: lineage disposition, architectural identity, and lowering strategy. A distinct instruction or a one-to-one alias may lower to direct typed uops or to reviewed microcode; alias identity is therefore not itself a lowering strategy. A one-to-one alias encodes one architecturally identical instruction. Multi-instruction assembler expansion is not an implementation class and cannot satisfy semantic-cut-line coverage. Provisional routing labels in the cut-line inventory do not become any of these decisions until the row-level audit is approved.

## Review gate

An encoding MUST NOT be frozen and production RTL, assembler, compiler, firmware, or operating-system code MUST NOT depend on a contract until the closed cut-line inventory and its lineage matrix are complete and reviewed. The English specification and machine-readable contract MUST agree with the selected dispositions and differences. Generated consistency checks MUST reject a contract that lacks its source identity, disposition, semantic-difference record, or verification plan.

The audit is repeated when a semantic contract changes, when new primary errata are incorporated, or when review discovers an earlier-generation dependency. Changing a disposition or cited interpretation requires corresponding specification, machine-readable, verification, and implementation review; it is not an editorial-only change.

## Explicit non-compatibility statement

The lineage gate does not require M64K to decode MC68060 instructions, expose Motorola registers, construct Motorola exception frames, reproduce cycle timing, accept M68K ELF objects, or run M68K binaries. Any future compatibility facility requires a separate versioned profile and cannot be inferred from this audit.
