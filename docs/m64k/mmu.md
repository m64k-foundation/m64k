# M64K v1 memory-management architecture

| Field | Value |
|---|---|
| Status | Normative draft |
| Version | 0.2-development |
| Scope | M64K v1 address translation, protection, page tables, TLBs, and maintenance |
| Compatibility | Reset firmware may execute with translation disabled; no Motorola MMU format compatibility |

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are interpreted as described by RFC 2119 and RFC 8174.

## Address spaces

M64K v1 virtual addresses are 48-bit canonical values. Bits 63:48 equal bit 47. Translation uses a 16-bit address-space identifier (`ASID`); global mappings ignore the `ASID`. Physical-address width is discoverable from 36 through 48 bits. Implementations reject page-table entries containing physical bits above their width.

User and supervisor translations share one page-table format but have independent permission checks. Machine privilege MAY bypass translation for firmware recovery; bypass never bypasses physical memory attributes or access-fault reporting.

## Page-table geometry

The base page is 4 KiB. Translation uses four levels of 512 eight-byte entries. Virtual address fields are:

| Bits | Meaning |
|---|---|
| 63:48 | Canonical extension of bit 47 |
| 47:39 | Level 3 index |
| 38:30 | Level 2 index |
| 29:21 | Level 1 index |
| 20:12 | Level 0 index |
| 11:0 | Page offset |

Leaves are permitted at levels 2, 1, and 0, producing 1 GiB, 2 MiB, and 4 KiB pages. A leaf physical page number MUST be aligned to its page size. Misaligned leaves, reserved bits, invalid memory types, and illegal permission combinations cause a page-table-format fault.

## Page-table entry contract

Each entry contains valid, leaf/table, user, readable, writable, executable, global, accessed, dirty, and memory-type fields plus the physical page number. Write implies read. A table entry MUST NOT carry leaf permissions. No mapping is executable and writable simultaneously; attempting to install or use such a leaf raises a format or permission fault.

The hardware page walker atomically sets `accessed` before a successful translation and `dirty` before a successful store becomes visible. If the update cannot be completed, the original access faults without publishing its destination or store. Software MAY pre-set both bits to avoid hardware updates.

## Fault priority and records

Canonicality is checked before TLB lookup. Translation format and walk-access faults precede leaf permission faults. Instruction, load, store, and atomic accesses report distinct causes. A fault record includes virtual address, access class, privilege, `ASID`, walk level, offending entry address when applicable, and whether the failure occurred during entry fetch or accessed/dirty update.

Speculative walks MAY fill translation structures but MUST NOT set accessed or dirty bits, report architectural faults, or cross a privilege/context change until the owning instruction is non-speculative at the required boundary.

## TLB maintenance

M64K v1 provides serializing operations to invalidate:

- one virtual address for one `ASID`;
- all non-global entries for one `ASID`;
- all entries on the local hardware thread;
- a specified scope across sibling threads, one core, or all cores.

Changing a translation root or reusing an `ASID` requires a local invalidation and, when the address space ran elsewhere, a remote shootdown. Completion means every target has prevented new use of the invalidated entry and acknowledged any older access according to [memory-model.md](memory-model.md). TLB entries include `ASID`, page size, privilege permissions, memory type, global state, and a translation generation; SMT threads MUST NOT match each other's non-global entries accidentally.
