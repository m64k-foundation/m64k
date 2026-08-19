# M00 conformance audit

This document is the review gate for every instruction advertised by the
native `mx68k_core_m00`.  A firmware or Linux workload may expose a defect, but
workload behaviour is not an architectural specification and cannot by itself
justify an RTL change.

## Normative sources

The M00 profile is reviewed against these primary NXP/Motorola documents:

- [M68000 Family Programmer's Reference Manual](https://www.nxp.com/docs/en/reference-manual/M68000PM.pdf),
  Revision 1;
- [M68000 8-/16-/32-Bit Microprocessors User's Manual](https://www.nxp.com/docs/en/reference-manual/MC68000UM.pdf),
  Revision 9.1;
- [68K Programmer's Reference Manual Errata](https://www.nxp.com/docs/en/reference-manual/M68000PRMER.pdf),
  Revision 1, March 2007.

The errata changes FDBcc, FMOD, FMOVE and an MC68040 FRESTORE frame
description.  It does not amend the M00 integer instructions in the current
audit set.  The exact CPU profile still matters: behaviour documented only for
MC68010 or later must not leak into M00.

For the simulation-only Mackerel-08 peripheral overlay, the primary sources are
the [MC68681/MC68HC681 DUART User's Manual](https://www.nxp.com/docs/en/user-guide/MC68681UM.pdf)
and the pin-compatible
[MaxLinear XR68C681 datasheet](https://www.maxlinear.com/ds/XR68C681v210.pdf).
The latter is normative for XR68C681-only extended baud-rate commands.

## Required review sequence

Before enabling or correcting an opcode:

1. identify the exact compatibility profile and encoding;
2. read the instruction entry, addressing-mode table and relevant user-manual
   timing/bus sections, plus applicable errata;
3. record operand widths, extension/sign rules, CCR/SR effects, privilege,
   legal effective addresses, PC value, exceptions and visible address-register
   side effects;
4. record read/write ordering for any memory or MMIO destination;
5. compare those requirements with decode, execution, commit and fault paths;
6. add directed architectural and bus-transaction tests;
7. only then change RTL and run firmware/Linux as system regression.

An opcode discovered in a workload remains unimplemented until this sequence
is complete.  Differential comparison with `fx68k` is additional evidence, not
a replacement for the manuals.

## Status terminology

- **verified**: the documented behaviour listed here has directed coverage;
- **partial**: a deliberate architectural subset is implemented and all other
  encodings are rejected, or the effective-address matrix is not yet complete;
- **unverified**: RTL may exist, but this audit has not established a
  conformance claim.

## Current audited slice

| Instruction | Normative requirements reviewed | Status and evidence |
|---|---|---|
| `CLR.B/W/L` | PRM 4-73/4-74: data-alterable destination; X unchanged, N/V/C cleared, Z set. MC68000/MC68008 read a memory destination before clearing it. | **verified**. Decoder coverage classifies all 150 legal words and 42 illegal EA holes. The shared unary matrix executes every size, EA class and register alias, checks narrow writes, A7 stepping, exact flags and READ→WRITE ordering. Separate read/write fault cases check the complete group-0 frame and suppress destination, address, flags and PC commit. |
| `MOVE <ea>,CCR` | PRM 4-123/4-124: word source from data addressing modes; low byte supplies XNZVC, source upper byte ignored, SR upper byte unchanged; unprivileged. | **partial**. Immediate and memory sources plus SR preservation are directed; the complete legal-EA matrix remains open. |
| `MOVE <ea>,SR` | PRM 6-19/6-20: word source from data addressing modes; supervisor-only; all implemented SR bits affected; user execution takes privilege violation. | **partial**. Immediate/memory sources and the user-mode vector-8 path are directed; full EA/fault matrix remains open. |
| `MOVE SR,<ea>` | PRM 4-125: M00/M08 form, word data-alterable destination, unimplemented SR bits read as zero, flags unchanged, and a memory destination is read before it is written. | **verified for Dn and absolute-word memory**. `mx68k_core_sr_tb.sv` observes memory READ→WRITE and the stored SR. Other legal EA combinations remain coverage work. |
| `MOVE USP,An` / `MOVE An,USP` | PRM 6-20/6-21: long transfer selected by direction bit 3 in encodings `$4e60`–`$4e6f`; supervisor-only; condition codes unaffected. `An=A7` refers to the active supervisor A7 because the instruction cannot execute in user mode. | **verified**. Decode tests cover both directions and boundary register A7. `mx68k_core_usp_tb.sv` covers both transfers, A7/SSP banking, complete CCR preservation, and vector 8 with the faulting instruction PC stacked when attempted in user mode. |
| `PEA <ea>` | PRM 4-140/4-141: compute a control effective address without reading its operand, predecrement A7 by four, then push the 32-bit address; flags are unaffected. | **verified for `(An)`, displacement and absolute-long sequencing**. `mx68k_core_pea_tb.sv` checks consecutive effective addresses, big-endian stack layout, final A7 and complete CCR preservation. The remaining legal control-EA forms are still coverage work. |
| `CMPA.W/L <ea>,An` | PRM 4-76/4-77: subtract the source from the address register only to set N/Z/V/C; do not store the result, preserve X, and sign-extend a word source to 32 bits. Normal source-EA side effects still occur. | **verified**. All 976 legal words and 48 mode-7 holes are classified. The integrated matrix executes every source EA, size and register alias with an independent 32-bit subtract oracle, including PC-relative/immediate sources and same-An pre/postincrement. The fault matrix covers both absolute-long extension words and operand reads without premature address/CCR/PC commit. |
| `CMPM.B/W/L (Ay)+,(Ax)+` | PRM 4-80/4-81: read source then destination, subtract source from destination only for NZVC, preserve X and postincrement both address registers. MC68000UM table 7-12 confirms two operand reads and no write. | **verified**. All 192 encodings, every Ax/Ay pair, all sizes, flags, A7 byte stepping, same-An ordering and faults at either read are directed. M00 uses an explicit completed-source checkpoint because its group-0 frame is not restartable. The neighboring field value `11` is checked as legal `CMPA.L An,Ax`. |
| `BSR.B/W` | PRM 4-54/4-55: push the PC immediately following the complete branch instruction, then branch relative to the PC after the opcode word; displacement zero selects the word extension on M00, while `$ff` remains an 8-bit displacement because long branches start at M20. Flags are unaffected. | **verified for byte and word displacement**. `mx68k_core_bsr_tb.sv` checks both stacked return PCs, branch targets, RTS return flow, big-endian stack writes, A7 restoration and complete CCR preservation. |
| `DBcc` | PRM 4-89/4-90: if the condition is true, do not decrement or branch; otherwise decrement only the low word of Dn and branch relative to opcode+2 unless the result is `$ffff`. The upper word and all flags are unchanged. | **verified for the three control paths**. `mx68k_core_dbcc_tb.sv` checks condition-true/no-decrement, condition-false/decrement-and-branch, terminal `$ffff` fall-through, upper-word preservation and unchanged flags. Other displacement values remain coverage work. |
| `RTR` | PRM 4-167: pop a word into CCR, then a long PC, advance the active A7 by six; only the low byte of the stacked word affects SR. | **verified for the supervisor-stack path**. `mx68k_core_rtr_tb.sv` checks the two ordered reads, ignored stacked upper byte, preserved SR upper byte, restored PC/CCR and six-byte A7 update. User-stack and injected-fault paths remain open. |
| `TRAP #n` / `TRAPV` | PRM 4-187–4-190 and UM 6.3: `TRAP #n` selects vector `32+n`; `TRAPV` selects vector 7 only when V is set. M00 uses the six-byte group-1/2 frame containing SR and the following PC; flags are unchanged. | **verified for boundary vector and both TRAPV conditions**. `mx68k_core_trap_tb.sv` checks `TRAP #15`, V-clear fall-through, V-set vector 7, following-PC/SR stack layout and flag preservation. The trace regression separately checks synchronous-trap-before-trace priority. |
| `RESET` instruction | PRM 6-82 and UM 5.5.3: supervisor-only; assert the external RESET signal for 124 MC68000 clocks; internal registers and SR are unaffected, PC continues at the next instruction. User execution takes vector 8 at the faulting PC. | **verified at the core boundary**. `mx68k_core_reset_instruction_tb.sv` checks exactly 124 asserted clocks on `reset_devices_n`, delayed retirement, state preservation and the user privilege frame. Wiring/reset policy for each future SoC peripheral is intentionally a separate integration task. |
| `ORI/ANDI/EORI #imm,CCR/SR` | PRM 4-19–4-22, 4-103–4-105 and 4-154–4-157: CCR forms are byte-wide, preserve SR upper byte and are unprivileged; SR forms are word-wide and privileged. | **verified for all six exact words**. `mx68k_core_logical_sr_tb.sv` checks OR/AND/XOR snapshots, upper-byte preservation, legal user CCR access, full-word EORI to SR and vector 8 for user SR access. `mx68k_core_immediate_fault_tb.sv` forces the mandatory extension fetch to fail for every CCR/SR form and checks the supervisor-program group-0 frame. |
| `NOP` | PRM 4-145/4-146: no architectural effect other than advancing PC; it begins only after pending bus cycles complete and therefore synchronizes the pipeline; flags are unchanged. | **verified for the in-order M00 core**. `mx68k_core_system_control_tb.sv` checks sequential execution and complete SR preservation after an ordered RTS memory read. The current backend cannot have an older data cycle outstanding when NOP retires. |
| `RTS` | PRM 4-168/4-169: pop a long PC from the active A7, advance A7 by four and leave all flags unchanged. | **verified for the supervisor-stack path**. `mx68k_core_system_control_tb.sv` checks the big-endian stack read, restored PC, four-byte SSP update and full SR preservation. User-stack and injected read-fault coverage remain open. |
| `ILLEGAL` | PRM 4-105/4-106: exact opcode `$4afc` forces vector 4, does not affect condition codes and, on M00, uses the six-byte frame with the faulting instruction address. Other reserved encodings must not be used by software as a portable substitute. | **verified for the architected `$4afc` opcode**. `mx68k_core_system_control_tb.sv` checks vector 4 and the stacked SR/faulting PC. Generic unmatched-opcode rejection remains separately covered by the decoder test. |
| `RTE` | PRM 6-83/6-84 and UM figure 6-5: supervisor-only; M00 pops SR then PC from its six-byte exception frame and advances SSP by six. The restored S bit selects the active A7 bank; restored condition codes come from SR. | **verified for the M00 short frame and privilege path**. `mx68k_core_system_control_tb.sv` checks SR/PC restoration, SSP advancement, transition to user mode, pre-existing USP selection and a user-mode vector-8 attempt at the faulting PC. Injected faults on either stack read remain open. |
| `STOP` | PRM 6-84/6-85 and UM 6.3.4: supervisor-only; load the complete immediate word into SR, advance PC and stop all fetches. Trace eligibility is sampled at instruction start; an eligible trace completes STOP and takes vector 9 before the next instruction. An accepted interrupt or external reset resumes a stopped M00. | **verified for immediate SR load, trace, privilege and interrupt wake**. `mx68k_core_system_control_tb.sv` checks the traced STOP frame and following PC; reset/SR tests check vector 8; `mx68k_core_irq_tb.sv` checks masking and level-7 wake. External reset recovery is covered by the normal reset-vector path rather than this directed test. |
| `MOVEQ` | PRM 4-133/4-134: sign-extend the embedded byte to a long Dn result; set N/Z from all 32 bits, clear V/C and preserve X. Bit 8 is fixed clear. | **verified**. `mx68k_core_unary_quick_tb.sv` checks negative and zero immediates, complete long writes and X preservation; the generated mask excludes bit-8-set encodings. |
| `EXT.W/L` | PRM 4-105/4-106: M00 supports byte-to-word and word-to-long only; EXT.W preserves Dn[31:16]. N/Z follow the sized result, V/C clear and X is unchanged. | **verified**. The unary/quick regression checks both sign extensions, narrow upper-half preservation, zero based only on the word result and X preservation. |
| `EXG` | PRM 4-104/4-105: the three M00 opmodes exchange complete 32-bit values between Dn/Dn, An/An or Dn/An; all condition codes are unaffected. MC68000UM table 7-13 confirms that every form is register-only. | **verified**. Decoder tests cover all three opmodes. `mx68k_core_exg_tb.sv` checks simultaneous dual-register retirement, complete CCR preservation and the active supervisor A7 bank. All register numbers are selected by identical field logic, including the boundary indices used by the test. |
| `TAS` | PRM 4-186/4-187: test the original destination byte for N/Z, clear V/C, preserve X, then set bit 7; a memory form is an indivisible read-modify-write. MC68000UM table 7-7 gives the distinct register and memory timing forms. | **verified**. `mx68k_core_tas_tb.sv` checks Dn preservation, original-value flags, every legal data-alterable EA class, address-register side effects, the A7 byte step and a write-classified group-0 access fault with no premature postincrement. Decoder tests cover extension demand/faults and illegal An/PC-relative holes. `mx68k_ram_protocol_tb.sv` independently checks old-value return, indivisible update and unsupported-op rejection. |
| `SWAP` | PRM 4-183/4-184: exchange Dn[31:16] and Dn[15:0], set N/Z from the complete 32-bit result, clear V/C and preserve X. | **verified**. The unary/quick regression covers negative and zero long results; decoder coverage checks the exact Dn-only encoding. |
| `TST.B/W/L` | PRM 4-191/4-192: read without modifying a legal operand, set N/Z, clear V/C and preserve X. M00 has exactly 50 data-alterable EAs per size; An direct, immediate and PC-relative forms are not legal. | **verified**. Decoder coverage classifies all 150 legal words and all 42 M00 illegal EA holes, including extension-fetch faults. `mx68k_core_tst_matrix_tb.sv` executes all 150 legal words and checks every register alias, EA side effect, A7 byte step, flags and absence of writes. `mx68k_core_tst_fault_tb.sv` checks the group-0 read frame and suppression of CCR/postincrement on failure. |
| `NEG.B/W/L` | PRM 4-142/4-143: compute zero minus destination; X equals C, C clears only for a zero operand, Z is non-cumulative, and data-alterable memory forms are RMW. | **verified**. All 150 legal words, 42 illegal holes, sizes, EA classes and aliases execute against an independent sized arithmetic expectation over zero, one, minimum-negative and all-ones operands. Ordered RMW and read/write group-0 faults are directed with no premature architectural commit. |
| `NOT.B/W/L` | PRM 4-147/4-148: complement a data-alterable destination, set N/Z, clear V/C and preserve X; memory forms are RMW. | **verified**. The same 150-word complete execution matrix checks sized complement, upper-Dn preservation, all EAs, flags, address effects and ordered RMW. The decoder rejects all 42 holes, and extension/read/write faults are directed. |
| `ADDQ/SUBQ` | PRM 4-10–4-12 and 4-180–4-182: encoded data zero means eight; byte/word/long data-alterable operations update XNZVC. An permits word/long only, always updates all 32 bits and changes no flags. | **verified**. The decoder classifies all 2,656 legal words and 416 illegal byte/word/long EA combinations; size `11` remains correctly assigned to `Scc/DBcc`. The core executes every legal quick/operation/size/EA word against independent arithmetic expectations, including full-width An, narrow Dn, all flags, RMW order, A7 byte step, extension faults and read/write group-0 suppression. |
| `ADDI/SUBI` | PRM 4-8–4-10 and 4-178–4-180: sized immediate plus/minus data-alterable destination, normal XNZVC arithmetic flags, no An/PC-relative/immediate destination. Byte immediate occupies the low byte of its extension word. | **verified**. The decoder classifies all 300 legal words and 212 holes. `mx68k_core_immediate_matrix_tb.sv` executes every legal size/EA/register alias against an independent arithmetic oracle, including upper-Dn preservation, big-endian long immediates, A7 byte stepping and ordered memory RMW. The fault matrix covers first/second immediate words, EA extensions and operand read/write suppression. |
| `ORI/ANDI/EORI #imm,<ea>` | PRM 4-15–4-19, 4-101–4-103 and 4-152–4-154: sized logical operation on a data-alterable destination; set N/Z, clear V/C, preserve X; memory destinations are RMW. CCR/SR encodings are separate exact forms. | **verified**. All 450 generic legal words execute across every M00 data-alterable EA and size; the decoder separately recognizes the six exact CCR/SR overlaps and rejects the remaining 312 holes. The same matrix checks byte/long immediate layout, flags, narrow Dn writes, RMW order and extension/read/write faults. |
| `CMPI` | PRM 4-78–4-80: sized destination minus immediate updates NZVC, preserves X and never writes the destination. The manual's footnote explicitly excludes PC-relative modes on MC68000/MC68008. | **verified**. All 150 legal words execute against an independent subtract oracle and all 106 holes are rejected. Every EA alias and size is checked for flags, postincrement/predecrement behavior, a single read with no write, byte/long immediate layout and extension/operand-read fault suppression. |
| `MULU.W/MULS.W` | PRM 4-134–4-140: multiply the low words of Dn/source into a full 32-bit Dn result; signedness selects extension. N/Z use the long result, V/C clear and X is preserved. An direct is not a legal source; immediate and PC-relative are legal. | **verified**. The decoder classifies all 848 legal words and 176 holes. The integrated matrix executes every source EA and Dn alias against independent signed/unsigned products, checking the ignored upper multiplicand, complete 32-bit result, exact flags, PC-relative/immediate layout, address effects and one memory read. Both extension words and operand-read faults suppress all candidate state. |
| `DIVU.W/DIVS.W` | PRM 4-91–4-98: divide a 32-bit Dn by a word source, returning remainder in the upper word and quotient in the lower. DIVS remainder follows the dividend sign. Divide by zero takes vector 5; quotient overflow preserves Dn, sets V and clears C while N/Z are undefined; X is always preserved. On a zero divisor N/Z/V are undefined, X is preserved and C is still always cleared. | **verified**. All 848 legal words and 176 holes are classified; every legal source EA and Dn alias executes through the iterative divider. Independent oracles check result layout, remainder sign and defined flags. Directed boundaries cover unsigned `$ffff/$10000`, signed `$7fff/-$8000`, both adjacent overflows and `$80000000/-1`; overflow preserves Dn. Both zero-divisor forms take vector 5 with the following PC and cleared stacked C. Extension and operand-read faults are precise. |
| `AS/LS/ROX/RO` register shifts | PRM 4-20–4-23, 4-112–4-115 and 4-159–4-165: immediate field zero means eight; a register count is modulo 64. Effective zero preserves X and clears C except ROX copies X to C. N/Z follow the sized result, logical/rotate V clears, and ASL sets V if the sign changes at any step. | **verified**. Decoder and integrated-core tests cover all 3,072 legal opcode words, including same-register count/destination aliases and narrow writes. The shared independent one-bit oracle compares all 49,152 combinations of 16 boundary operands, three sizes, eight operations, two X states and counts 0–63 against the barrel RTL; directed integration additionally checks encoded 8, 64 and 65 cases. |
| `AS/LS/ROX/RO` memory shifts | PRM 3-8/3-9, 4-22/4-23, 4-114/4-115 and 4-161/4-165: every memory form is word-sized with an implicit count of one and accepts only memory-alterable EAs. It is an ordered read-modify-write; flags have the same one-bit semantics as the corresponding register operation. | **verified**. The decoder test exhausts the complete 512-word encoding subspace: 336 legal opcode words and 176 illegal EA holes. The core test covers all eight operations, exact results/flags and postincrement. The injected write-fault test checks the group-0 frame, unchanged memory/A0 and suppression of the computed CCR. |
| `JMP` / `JSR` / `LEA` | PRM 4-107–4-110: only control EAs are legal. JMP transfers directly; JSR first pushes the PC following the complete instruction; LEA writes the calculated 32-bit address without reading memory. None affects condition codes. PC-relative EAs use the extension-word address as their base on M00. | **partial**. An integrated test covers absolute JMP, absolute-long JSR/RTS, big-endian following-PC stack data, absolute-word sign extension and PC-relative LEA. Decoder tests reject Dn and postincrement holes. Remaining legal control EAs and injected faults are open. |
| `LINK.W` / `UNLK` | PRM 4-110–4-112 and 4-193/4-194: LINK decrements SP, pushes An, copies the decremented SP to An, then adds the sign-extended word displacement to SP. UNLK copies An to SP, pops a long into An and advances SP by four. These operations are sequential, so when An=A7 LINK stores the decremented SP and UNLK adds four to the value just pulled. Flags are unchanged. | **partial**. The normal A6 frame-create/frame-destroy sequence and both A7 alias orders, memory images, signed allocation, final registers and flags are directed. Injected stack faults remain open. |
| `CHK.W` | PRM 4-68–4-70: compare signed Dn[15:0] with zero and a signed word upper bound. Dn<0 or Dn>bound takes vector 6 and stacks the following PC. N is set for the negative trap and cleared for the upper-bound trap; N is undefined in range, Z/V/C are undefined and X is unaffected. An direct is illegal; other data EAs retain normal side effects. | **partial**. Immediate in-range, immediate negative and postincrement-memory upper-bound paths are directed. The test records both stacked N values, following PC and the postincrement before the trap. Complete legal data-EA and injected-fault coverage remains open. |
| `ADD/SUB/AND/OR/CMP <ea>,Dn` | PRM 4-3–4-5, 4-14–4-16, 4-74–4-76, 4-149–4-151 and 4-173–4-175: the source data EA includes immediate and PC-relative forms. ADD/SUB/CMP permit An only in word/long; AND/OR never permit An. Arithmetic writes XNZVC except CMP preserves X and does not store; logical operations preserve X and clear V/C. | **verified**. The decoder classifies all 6,744 legal words and 936 holes across the five direction-clear planes. `mx68k_core_binary_source_matrix_tb.sv` executes every legal size/EA/register alias against an independent sized ALU oracle, including PC-relative and immediate sources, An restrictions, narrow writes, exact flags, single-read memory behavior and A7 stepping. `mx68k_core_binary_fault_tb.sv` covers extension and operand-read group-0 suppression. |
| `ADD/SUB/AND/OR/EOR Dn,<ea>` | The same PRM entries require memory-alterable destinations for ADD/SUB/AND/OR; EOR permits data-alterable destinations including Dn. Memory forms are read-modify-write. Arithmetic updates XNZVC; logical operations preserve X, set N/Z and clear V/C. | **verified**. The decoder exhaustively separates 5,232 generic words, 1,408 specialized overlaps (`ADDX/SUBX`, `ABCD/SBCD`, `EXG`, `CMPM`) and 1,040 illegal holes. `mx68k_core_binary_destination_matrix_tb.sv` executes every generic word with independent results/flags and exact READ→WRITE ordering; the fault matrix proves extension/read/write suppression. |
| `MOVE` / `MOVEA` | PRM 4-115–4-119: MOVE accepts all source EAs and data-alterable destinations; An direct is forbidden for byte. MOVE sets N/Z, clears V/C and preserves X. MOVEA accepts word/long, sign-extends word to all 32 An bits and changes no flags. Source extension words precede destination extensions, and memory source is read before destination is written. | **partial**. Directed register, immediate, absolute and memory-to-memory paths cover narrow writes, source/destination address updates, extension ordering, big-endian data, A7's two-byte step for byte access, MOVE flags and MOVEA sign extension/no-flags. Same-An double-EA corners and the complete fault matrix remain open. |
| `MOVEM.W/L` | PRM 4-127–4-130: control/postincrement transfers walk D0→D7→A0→A7; predecrement stores in the reverse architectural order with a reversed mask. Word loads sign-extend. On M00, a predecrement base in the list stores its initial value; a postincrement base in the load list ignores memory and receives the final address. Store excludes PC-relative/postincrement; load excludes predecrement. Flags are unchanged. | **partial**. Directed control-mode word store/load, long predecrement and long postincrement cases cover ordering, sign extension and both base-register rules. A zero mask performs no transfer. Decoder tests cover direction/EA holes. Complete masks, control EAs and injected partial-transfer faults remain open. |
| `Scc` | PRM 4-172/4-173 and table 3-19: byte data-alterable destination, all 16 conditions, flags unchanged; MC68000/MC68008 read memory before writing `$00/$ff`. | **verified**. The decoder classifies all 800 legal Scc words, the 128 overlapping `DBcc` words and 96 illegal holes. The core executes every legal word with both attainable outcomes, every EA/register alias, A7 byte step, preserved CCR and exact READ→WRITE order. Extension and operand read/write faults suppress all candidate state. |
| `BTST` | PRM 4-61–4-63: Dn destination is long/modulo 32; other data EAs are byte/modulo 8; only Z changes. Dynamic BTST permits immediate data as its destination, while static BTST does not. | **partial**. Static/dynamic Dn and memory operations plus dynamic-immediate destination are directed. PC-relative and the rest of the legal EA matrix remain open. |
| `BCHG/BCLR/BSET` | PRM 4-27–4-32 and 4-56–4-58: Dn is long/modulo 32, memory is byte/modulo 8, destination must be data alterable, and only Z changes according to the original bit. | **partial**. Dn and `(An)` static/dynamic paths are directed. Complete alterable-EA and fault coverage remains open. |
| `ADDX/SUBX` register form | PRM 4-13/4-14 and 4-183/4-184: byte/word/long, X input, X=C output, cumulative Z and normal N/V/C; narrow Dn writes preserve upper bits. | **verified for register form**. Byte arithmetic flags are exhaustive; integrated byte/word/long cases cover carry, borrow, overflow, cumulative Z and narrow-write preservation. |
| `ADDX/SUBX` predecrement memory form | PRM 2-7, 4-13/4-14 and 4-183/4-184: source and destination are independently predecremented memory operands; byte A7 decrements by two. Source is read before the destination RMW sequence. When both fields name the same An, the destination observes the source decrement and An is decremented twice. Z is cumulative and X mirrors C. MC68000UM table 7-12 confirms the memory form has two operand reads and one operand write. | **verified**. All 384 byte/word/long words are decoded. Directed execution observes source-read → destination-read → destination-write, both-register updates, same-An double decrement, A7 byte alignment, big-endian values and cumulative flags. A 36-case fault matrix covers every operation/size/access phase with distinct and same-An operands, exact group-0 frame data and response-gated suppression of incomplete state. |
| `ABCD/SBCD` | PRM 3-10, 3-18, 4-1/4-2 and 4-169/4-170: packed-BCD byte arithmetic only, register or independently predecremented memory operands; X supplies the incoming decimal carry/borrow and is set equal to C, while Z is cumulative. N and V are undefined. | **verified**. All 256 register/memory words are decoded; every valid packed-BCD operand pair and both X inputs are independently checked. Integrated tests cover narrow writes, decimal carry/borrow, cumulative Z, deterministic preservation of undefined N/V, ordered memory RMW, same-An/A7 behavior, plus 12 injected cases spanning all three accesses with distinct and same-An operands. |
| `NBCD` | PRM 3-10, 3-18 and 4-140/4-142: compute packed-BCD `0-destination-X` on a byte data-alterable operand; X=C is the decimal borrow, Z is cumulative, and N/V are undefined. | **partial**. Exhaustive decimal-subtract primitives plus directed register and predecrement-memory RMW cases cover tens/nines complement, borrow, narrow writes, address update and deterministic N/V preservation. The complete data-alterable EA/fault matrix remains open. |
| `ADDA/SUBA.W/L` | PRM 4-6/4-7 and 4-176/4-177: all source EAs, word source sign-extended, 32-bit address-register arithmetic, flags unaffected, with normal EA side effects. | **verified**. The decoder classifies all 1,952 legal words and 96 holes. Every legal source EA, size, source/destination alias, PC-relative/immediate layout and same-An pre/postincrement case executes against an independent 32-bit oracle with the complete CCR preserved. First/second extension and operand-read group-0 faults suppress all uncompleted state. |
| `SUB.B/W <ea>,Dn` | PRM 4-173–4-175: data source EAs; An source is word/long only; X/N/Z/V/C follow subtraction and narrow Dn writes preserve upper bits. | **verified** as part of the complete `ADD/SUB/AND/OR/CMP <ea>,Dn` matrix above, including every byte/word/long source EA, register alias, arithmetic boundary and extension/read fault. |

## Peripheral correction recorded by the same rule

The Mackerel-08 Linux compatibility model uses the MC68681 counter/timer
contract, not a value inferred from the kernel's branch path:

- ISR bit 3 is Counter/Timer Ready;
- IMR bit 3 enables that source;
- reading ISR reports state and does not acknowledge the counter/timer;
- a stop-counter command acknowledges/clears the ready indication.

`mx68k_linux_workload_memory_tb.sv` verifies the mapped byte lanes and that ISR
read leaves the interrupt pending until the stop-counter register is read.  The
Linux image is only the subsequent integration regression.

The channel-B receive path follows the same documented boundary:

- SRB bit 0 reports RxRDY and bit 1 reports a full three-byte receiver FIFO;
- ISR bit 5 selects RxRDY or FFULL according to MR1B bit 6;
- IMR bit 5 gates that source onto the interrupt output but does not hide it
  from ISR;
- reading RBB removes exactly one FIFO byte and updates RxRDY/FFULL;
- CRB receiver enable, disable and reset-receiver commands use the complete
  four-bit miscellaneous-command field;
- XR68C681 commands `$80` and `$a0` select the extended receive/transmit baud
  tables and must not alias the MC68681 `$00`/`$20` commands.

The directed peripheral test covers RxRDY mode, FFULL mode, FIFO ordering,
interrupt masking, receiver reset and the XR68C681 extended commands.  The
direct-preload simulation explicitly initializes RX enabled because it bypasses
the real Mackerel-08 boot ROM's documented `uart_init()` handoff, which issues
CRB `$05` before jumping to the image.

The end-to-end `firmware-linux-smoke` regression, selected with platform
`mackerel-08`, then boots the real historical uClinux image, waits for the
BusyBox `# ` prompt, sends `uname -a` through the simulated UART receiver and
requires both the non-echoed `uClinux mackerel-08` response and a second prompt.

The Mackerel-F high-window model is checked against the vendored peripheral
RTL rather than inferred from Linux control flow:

- the Mackerel-F decoder selects identical tiny-SPI instances in slots 3 and
  4 (`$fffb00` and `$fffc00`);
- the upstream tiny-SPI register map places status at `base+8`, with TXR in bit
  1 and TXE in bit 0; both are set after reset or while idle;
- the OpenCores 16550 RTL uses IER bit 1 for THRE, identifies that interrupt as
  `$02` in IIR, clears its pending latch on an identifying IIR read or THR
  write, and rearms it when the transmitter becomes empty again;
- receive-data-available has higher IIR priority than THRE, and FIFO-present
  bits 7:6 read as `11`.

`mx68k_high_model_irq_tb.sv` directs both SPI status slots and the 16550 THRE
enable, IIR identification, clear and rearm sequence.  The Linux 7.1.0
Mackerel-F image is an integration regression after those contracts pass; it
is not their specification.

## Open audit rule

The generated instruction database is a decode inventory, not proof of
conformance.  Until an entry has a row here (or in a successor machine-readable
matrix) with normative references and directed evidence, it must not be used to
claim complete M00 compatibility.

## Complete decoder-inventory gate

`isa/mx68k_m00.json` currently advertises 152 ordered decode patterns in 56
format groups. `isa/mx68k_m00_audit.json` records every one of those groups,
and `scripts/check_mx68k_audit.py` makes an omitted or stale entry a build
failure. The current machine-checked classification is:

- **verified**: `ABCD_SBCD`, `ADDQ_SUBQ`, `ADDSUB_ADDRESS`, `ADDSUB_IMMEDIATE`, `ADD_EA_DN`, `ADDX_SUBX_MEMORY`, `ADDX_SUBX_REGISTER`, `BINARY_DN_EA`, `BINARY_EA_DN`, `CLR`, `CMPA`, `CMP_IMMEDIATE`, `CMPM`, `DBCC`, `DIV`, `EXG`, `EXT`, `ILLEGAL`, `LOGICAL_IMMEDIATE`, `LOGICAL_IMMEDIATE_SR`, `MOVEQ`, `MUL`,
  `MOVE_USP`, `NEG`, `NEGX`, `NOP`, `NOT`, `RESET`, `SCC`, `SHIFT_MEMORY`, `SHIFT_REGISTER`, `STOP`, `SWAP`, `TAS`, `TEST`, `TRAP`, `TRAPV`;
- **partial**: `BIT_DYNAMIC`, `BIT_IMMEDIATE`, `BRANCH`, `CHK`,
  `JMP`, `JSR`, `LEA`, `LINK`,
  `MOVEM`, `MOVE`, `MOVE_FROM_SR`, `MOVE_TO_CCR`, `MOVE_TO_SR`,
  `PEA`,
  `NBCD`, `RTE`, `RTR`, `RTS`, `UNLINK`;
- **unverified**: none.

The conservative label is deliberate. Existing workload coverage does not
promote a remaining group until its manual entry, model-specific rules,
legal/illegal EA matrix, flags, exception PC and memory ordering have been
recorded and compared with the RTL.

## Format-level review closure

The first documentation-led pass is complete: every one of the 56 generated
format groups has a primary-manual reference, an explicit implemented scope,
directed evidence (or an explicit rejected subset), and a machine-checked
status.  There are no unreviewed decoder groups.  This closes the inventory
audit; it does **not** claim exhaustive MC68000 conformance.

The remaining partial work is deliberately visible rather than inferred from
successful workloads:

- complete legal/illegal effective-address products for the 23 partial groups;
- inject faults at each read, write, extension fetch and partial-MOVEM stage;
- resolve same-address-register source/destination MOVE side effects only from
  processor-specific cycle documentation plus differential evidence;
- implement the MC68000 first bus error during group-1/2 exception processing,
  while retaining the documented halt for a second group-0/reset fault;
- add generated arithmetic/shift boundary products beyond the defining cases
  already directed.

The regression gate for this pass is `make -C sim/mx68k test`, followed by the
real bootloader smoke and the uClinux/BusyBox `uname -a` smoke.  Workload boot
remains an integration result, not the source of any opcode or peripheral
semantics.
