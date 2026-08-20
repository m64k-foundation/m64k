# Iterative Rotate-Through-X Execution Unit

Status: implementation candidate, functionally verified, not production-frozen
Document version: 1.0
Architecture scope: `M64K-v1.scalar-shift-rotate` `ROXL` and `ROXR` operations
Compatibility statement: this is a native M64K execution implementation and does not provide M68K binary, encoding, ABI, exception-frame, or bus compatibility

## Normative contract

The architecture-visible behavior is defined by `isa/native/semantics/scalar-shift-rotate-v1.json` and the scalar shift and rotate section of `docs/m64k/base-isa.md`. This document records a microarchitectural implementation and verification result; it does not add architectural behavior.

The historical semantic rationale is the *M68000 Family Programmer's Reference Manual*, 1992 edition, `ROXL/ROXR`, pp. 4-163 through 4-165. The MC68060 semantic-floor inventory presence is recorded by the *M68060 User's Manual*, Revision 1, Section 1.9, Table 1-3, pp. 1-16, 1-18, and 1-19. M64K deliberately changes the architectural width set, encoding ownership, explicit flag-update policy, narrow-result extension rule, operand forms, and software-visible machine state as specified by the native contract.

## Organization

`m64k_rotate_extend_iterative` accepts a typed request containing the complete backend allocation tag, source, low-six-bit count, operand size, direction, persistent input X value, and flag-update policy. It constructs a 9-, 17-, 33-, or 65-bit ring with X in bit zero and executes six conditional fixed-distance stages corresponding to distances 1, 2, 4, 8, 16, and 32. Counts are reduced modulo `W+1` before iteration.

ROXR reuses the ROXL stage network through bit-order normalization. The ring is reversed when a right-rotate request is accepted, traverses the same left-rotation hardware, and is reversed again only for architectural response formatting. This is a wiring transformation selected at the unit boundary rather than a duplicated right-rotation datapath.

The latency from an accepted request to response publication is exactly six execution cycles for every size, direction, count, X value, and flag policy. The unit holds one operation at a time. Ordinary shifts and rotates remain on the independent throughput-one fast path, so an iterative rotate-through-X operation does not reserve that datapath.

The response atomically contains the zero-extended GPR result and the persistent output X value. When `.F` is selected, the same response also carries freshly computed `N`, `Z`, cleared `V`, and `C` equal to output X. Without `.F`, `flags_valid` is clear while the output X update remains valid. No intermediate ring or X state is architectural.

## Precise execution identity and squash

Every operation retains the complete `m64k_execute_tag_t`: core, hardware thread, ROB index, ROB generation, allocation sequence, and micro-operation index. An exact-tag squash cancels an unpublished operation and returns the unit to idle. A squash differing in any identity field cannot cancel it. Once a response is published, it is irrevocable and remains stable under backpressure; squash cannot retract or alter it. Retirement must commit the GPR result and X update together or commit neither.

The unit has no operating-system, firmware, simulator, FPGA, or benchmark-specific behavior. It neither owns architectural X state nor assumes a single core or hardware thread.

## Verification evidence

The warning-fatal Verilator target compiles the production RTL and explicitly binds `verification/rtl/m64k_rotate_extend_iterative_checker.sv` with assertions enabled. Assertions are external to production RTL; synthesis does not receive the checker and does not use an assertion-ignore option.

The differential test uses a repeated one-bit rotate oracle, independent of the RTL's binary-decomposed fixed-stage algorithm. It covers:

- every byte source value, count 0 through 63, both directions, both X inputs, and both flag-update policies;
- word, long, and quad boundary values, alternating patterns, high discarded narrow-source bits, and every relevant `W`, `W+1`, `2W`, modulo-ring, 32, 33, and 63 count boundary;
- exact six-cycle latency;
- stable irrevocable response behavior under backpressure and matching squash;
- exact-tag cancellation before publication and accept-time cancellation;
- wrong-thread squash isolation and full returned allocation identity;
- atomic result and X validity, carry/X equality, zero extension, and all flag values.

The current exhaustive and protocol regression passes with Verilator 5.046 under `--Wall --assert`, with warnings fatal. Slang/Yosys synthesis in the immutable ASIC container also completes warning-fatal. With the required 64-bit allocation-lifetime sequence, the integrated synthesis target retains 334 sequential cells, independently checked before classifying ABC's exact extracted-combinational-cone diagnostic.

## Current structural evidence and production gate

The integrated generic Yosys flow reports 3,035 cells and 334 sequential cells for the isolated iterative unit. This is the reproducible target-owned baseline; earlier exploratory counts are not used as acceptance evidence.

Combining this isolated count with the current 2,151-cell ordinary fast candidate gives 5,186 generic cells, about 6.2 percent above the 4,882-cell complete combinational reference. This does not satisfy the shift acceptance plan's early 20-percent generic-cell sanity threshold. Therefore functional completeness and protocol correctness are established, but the combined organization is not production-frozen and no area, frequency, power, or silicon-readiness claim is made.

The next implementation comparison must evaluate integration that shares normalization, response formatting, or stage resources with the ordinary fast path, and must run identical technology mapping, sequential timing constraints, placement, routing, and activity assumptions. Architectural behavior, six-cycle bound, exact execution identity, atomic X publication, and precise squash semantics remain non-negotiable during that optimization.
