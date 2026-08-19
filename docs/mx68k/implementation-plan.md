# MX68K implementation plan

## Workstreams

The project is divided into contracts that can be implemented and verified
independently:

1. architecture/specification and machine-readable ISA;
2. verification/reference semantics;
3. memory fabric and board adapters;
4. integer frontend/backend and precise commit;
5. caches and MMUs;
6. FPU;
7. firmware, kernel and toolchains;
8. optional MXV/MXLE/MXA/MXMP extensions.

## Module plan

```text
mx68k_core
├── frontend
│   ├── pc/control flow
│   ├── i_mmu/i_atc
│   ├── i_cache
│   ├── fetch buffer/alignment
│   └── decoder + symbolic micro-op expansion
├── backend
│   ├── integer register file
│   ├── ALU/shifter
│   ├── AGU
│   ├── mul/div
│   ├── branch
│   └── commit/exception
├── memory
│   ├── LSU
│   ├── d_mmu/d_atc
│   ├── d_cache/write buffer
│   └── atomic endpoint
├── fpu
├── vector (optional MXV)
├── control registers
└── debug/retirement trace
```

SoC-level modules include memory fabric, boot ROM, interrupt controller,
per-core timers, UART, storage/network adapters and board-specific DDR/reset.

## Milestones

### P0 — Foundation (completed 2026-08-18)

- normative architecture and protocol documents;
- shared SystemVerilog package and memory interface;
- behavioural RAM;
- fx68k-to-fabric bridge;
- automated endian/byte-lane/fault tests.

Evidence: the first-party P0 lint is clean; standalone tests cover request and
response backpressure, endian byte lanes and faults; the real fx68k executes
reset vectors, NOP and BRA through the new fabric; the architectural package
exhaustively checks byte ADD/ADDX/SUB/SUBX flags.

### P1 — Reference, frontend and fabric (in progress)

- instruction retirement trace for fx68k;
- broad M00 architectural test generator;
- epoch-tagged 16-byte line fetch and variable-length instruction queue;
- address decoder, arbiter and ROM/MMIO adapters;
- 32-bit boot map and formal bus properties;
- synthesizable DDR-controller adapter for candidate FPGA boards.

Implemented so far: the three-port masked address router with overlap checks
and unmapped-access faults, plus the two-line epoch-tagged fetch frontend with
sequential prefetch, redirect cancellation, exact-PC fault tokens and counters.
The variable-length circular instruction buffer and initial generated M00
predecoder are also integrated as `mx68k_decode_frontend`. Its tests cover
cross-line extensions, backend stalls, profile-specific branch lengths,
redirect flushes and precise extension-word faults.

### P2 — New M00 core

- symbolic opcode database and decoder generator;
- in-order fetch/decode/execute/commit skeleton;
- integer register file, ALU, AGU and branches;
- scalar LSU and precise M00 exceptions;
- differential conformance and NOMMU Linux boot.

Implemented firmware-boot slice: banked D0-D7/A0-A7, USP/SSP, SR and PC;
reset-vector loading; generated variable-length decode; classic 68000 effective
addresses; ALU/shifter and condition flags; JSR/RTS/LINK/UNLK stack paths;
multi-beat MOVEM; memory-to-memory MOVE; response-gated read-modify-write; and
precise terminal fetch/data fault records. DIVU/DIVS include quotient overflow
and vector-5 divide-by-zero handling. Basic synchronous M00 traps now build the
six-byte SR/PC frame and RTE restores it; frame faults take the terminal
double-fault path. The native core boots the real Mackerel ROM through
`.data`/`.bss` and newlib initialization, prints the full banner through a
fabric-connected 16550 model, handles absent SD through the fast SPI model,
accepts a scripted `help` command through UART RX, prints the complete command
list through newlib and returns to the interactive `> ` prompt. A standalone
Verilator terminal harness now connects host stdin/stdout to that UART for
interactive firmware use. The real firmware `info` path also completes through
newlib's decimal formatting, covering its GCC `CLR.W`/`SWAP`/`DIVU` helper
sequence, and is retained as an end-to-end smoke test.

The M00 core now also accepts a per-core routed interrupt channel at precise
instruction/STOP boundaries. Levels 1–6 obey SR.I, level 7 has transition
semantics, an accepted interrupt updates SR.I, and both autovectored and
explicit-vector responses use the normal frame/RTE path. The simulated
Mackerel high window drives UART receive at level 5 and a programmable
10/25/50/100 Hz timer at level 6, with directed source and end-to-end core
tests.

CHK.W now covers register, immediate and memory bounds with signed comparison,
architectural N reporting, following-PC trap frames and completed
effective-address updates. M00 instruction trace samples T1 at instruction
start, follows successful retirement/control transfer, and uses vector 9 with
the normal frame. Nested directed tests verify the required
trap-before-trace-before-interrupt precedence. Divide-by-zero now likewise
stacks the following PC as an instruction trap.

The M00 group-0 path now emits the architectural seven-word bus/address-error
frame with SSW, access address, instruction register, SR and PC. SSW helpers
retain the original function-code space and access direction for future MMU
integration. Odd word/long accesses fault before the fabric, instruction-fetch
and data faults are distinguished, handlers can clean the diagnostic prefix
and return through ordinary M00 RTE, and a fault during frame construction
halts as a double fault.

The scalar LSU now decomposes every legal long access at internal line offset
14 into two ordered word beats with one final architectural commit. This common
path covers ordinary loads/stores, read-modify-write, MOVEM, control-flow stack
traffic, RTE and exception frames. Directed tests cover big-endian read/RMW,
JSR/RTS across the boundary and a second-beat bus fault with the architectural
partial write and exact failing address.

NEGX byte/word/long is now decoded from the generated ISA table and executed
through the shared subtract-with-extend primitive for both data-register and
memory destinations. It consumes CCR.X as the incoming borrow, implements the
architectural cumulative-Z rule used by multiprecision arithmetic, and shares
the response-gated RMW/fault path. Directed coverage includes register widths,
both cumulative-Z outcomes and a line-crossing long memory operand.

ADDX/SUBX now also implement the M00 predecrement-memory form. The LSU performs
the architected source read, destination read and destination write as three
ordered, response-gated accesses; each operand applies its own predecrement,
including the two-byte A7 step for byte accesses and the double decrement when
both operands name the same address register. Directed byte/word/long tests
check bus ordering, big-endian data, address-register commits and cumulative-Z
arithmetic. The complete Verilator regression, real bootloader command probe
and historical uClinux 4.4 ROMFS workload all pass; the latter reaches the
BusyBox shell and completes an interactive `uname -a` command through the
simulated UART after 41,955,425 core cycles with the iterative divider build.

The complete M00 packed-BCD arithmetic set (`ABCD`, `SBCD` and `NBCD`) now
shares explicit decimal-correction primitives with the extend sequencing.
Architecture tests exhaust every valid two-digit operand pair and both X
inputs for addition and subtraction. Core tests cover register and memory
forms, cumulative Z, decimal carry/borrow, narrow writes, same-An/A7 updates
and the documented memory transaction order. Because the manuals define N and
V as undefined, the implementation preserves them deterministically without
making them part of the architectural contract.

The shared predecrement extend sequence now has a complete three-phase fault
matrix. ADDX/SUBX byte/word/long and ABCD/SBCD byte operations are each forced
to fail on the source read, destination read and destination write, with both
distinct registers and same-An double-decrement aliases. The tests check the
exact MC68000 group-0 SSW/address/IR/SR/PC frame and the MX68K response-gated
rule that no incomplete address, CCR, memory or PC state is published. This
private checkpoint boundary is intentionally reusable by a future restartable
MMU/replay implementation without changing the M00 ISA.

`EXG` now implements all three M00 register combinations (`Dn,Dn`, `An,An`
and `Dn,An`) as a single architectural retirement with two register-file
writes. The decoder follows the opmode fields in PRM 4-104/4-105; directed
execution checks full 32-bit exchange, complete CCR preservation and the
active supervisor `A7` bank. The second write ports are confined to the
backend register file and therefore remain compatible with a future renamed,
multi-issue implementation without exposing a new architectural interface.

`TAS` now uses the existing fabric atomic contract rather than an ordinary
load followed by store. PRM 4-186/4-187 requires an indivisible byte RMW for
semaphore use; the core therefore emits one ordered `MX_MEM_ATOMIC`/OR request,
and the endpoint returns the pre-update line while setting bit 7 in the same
accepted transaction. Directed execution covers Dn, every legal memory EA
class, flags from the original byte, address side effects, the special A7 byte
step, extension/data access faults and the exact atomic request.
The RAM protocol test independently checks pre-update response data, the
indivisible update and explicit rejection of unsupported atomic operations.
The decoder rejects An/PC-relative holes, and a faulting `(An)+` atomic request
is verified to leave An/CCR unchanged while building the documented group-0
write frame. The same endpoint is intended for M20 CAS/CAS2 and MXA.

The execute datapath now contains a bounded-depth barrel shifter/rotator and a
32-step restoring word divider. The shifter is differentially checked over
49,152 operation/size/direction/count/input combinations, including the
M68000 zero-count and ROX modulo-9/17/33 rules. DIVU/DIVS no longer infer a
large combinational `/` or `%` network; result, overflow and divide-by-zero are
committed only after the iterative unit completes.

The M00 word multiply/divide planes are now closed against PRM 4-91–4-98 and
4-134–4-140. Decoder coverage classifies all 1,696 legal words and 352 holes;
integrated execution covers every source EA and register alias, while a fault
matrix covers both extension positions and operand reads. Divider boundaries,
signed remainder, overflow preservation and the vector-5 following-PC frame
are directed. This review also corrected the zero-divisor exception frame:
the PRM makes N/Z/V undefined and X unaffected, but requires C to be cleared.

`CMPM.B/W/L` is the first client of the common ordered-memory sequence state.
All 192 CMPM words are decoded into the same typed operation. Directed tests
cover every Ax/Ay encoding, source-before-destination reads, flags, A7 byte
stepping, same-An double postincrement and bus/alignment faults at either read.
The first successful read is an explicit M00 checkpoint; a fault in the second
read retains the completed source increment but suppresses destination/CCR
commit. The adjacent 64 words with the apparent size field `11` are verified
against PRM 4-78/4-81 as `CMPA.L An,Ax`, not misclassified as CMPM or EOR.

The formerly missing M00 memory-shift subspace is now implemented. All eight
word/count-one AS/LS/ROX/RO directions share the barrel shifter and the ordered
LSU RMW path. Decoder coverage classifies all 512 words in the subspace (336
legal memory-alterable encodings and 176 illegal EA holes); execution covers
all operations and a write-fault injection proves that failed RMW completion
does not commit memory, postincrement, CCR or PC.

`TST.B/W/L` is now closed as a complete M00 family rather than a workload
sample. The decoder classifies every one of its 150 legal opcode words and 42
M00-invalid EA combinations; the core executes every legal word across all
register aliases and EA classes. Separate extension- and operand-fault checks
prove that no flags or address side effects leak across a failed read.

The register AS/LS/ROX/RO family is also closed over its complete 3,072-word
encoding space. A simulation-only one-bit-at-a-time oracle is shared by the
standalone barrel-shifter and integrated-core tests: 49,152 datapath vectors
cover every operation, direction, size, X input and six-bit count, while the
core matrix verifies every encoded source/destination alias and narrow write.

The common unary data-alterable path now closes `CLR`, `NEG` and `NOT`
together instead of relying on workload samples. The decoder classifies 450
legal words and 126 illegal EA holes across the three families. A reusable
integrated matrix executes every legal word, checks sized register writes,
all address side effects, exact flags and the ordered memory read-modify-write
sequence (including the M68000/68008 read-before-clear rule). Independent read
and write fault injection for each operation verifies the complete group-0
frame and suppresses every candidate destination, address, CCR and PC commit.

`Scc` is likewise closed over the complete M00 space rather than a few
conditions used by software. The decoder distinguishes 800 legal Scc words,
128 overlapping `DBcc` encodings and 96 illegal EA holes, and now records its
NZVC read dependency explicitly for future scoreboards. The integrated matrix
executes every legal word across all 16 conditions and all 50 destinations,
preserves the complete CCR, observes the M68000/68008 memory READ→WRITE rule,
and verifies read/write group-0 fault suppression independently.

`ADDQ/SUBQ` now covers every one of its 2,656 legal M00 words and all 416
illegal EA combinations in the byte/word/long plane. The matrix varies every
quick field (including zero-as-eight), both operations, sizes, EA aliases and
arithmetic boundaries. It separately proves the architecturally special An
full-32-bit/no-flags path, memory RMW ordering and extension/read/write fault
suppression; size `11` remains owned by the overlapping `Scc/DBcc` formats.

The six generic immediate families are now closed over their complete M00
spaces: 300 `ADDI/SUBI`, 450 generic `ORI/ANDI/EORI`, and 150 `CMPI` words.
The decoder exhaustively distinguishes their 630 illegal holes and the six
exact CCR/SR overlaps. Integrated execution uses an independent sized ALU
oracle across every legal EA and alias, while a separate group-0 matrix forces
the first and second immediate words, destination extension, operand read and
RMW write to fail. This also closes the formerly missing extension-fault path
for every logical CCR/SR form.

The two-register binary directions are now closed from the manuals rather
than from workload sampling. Across `ADD/SUB/AND/OR/CMP <ea>,Dn`, all 6,744
legal words and 936 holes are classified and executed with every legal source
EA, size and register alias. Across `ADD/SUB/AND/OR/EOR Dn,<ea>`, the decoder
separates 5,232 generic words from 1,408 architecturally distinct overlaps and
1,040 illegal holes; every generic word executes with exact flags and ordered
memory RMW. A separate group-0 matrix forces source/destination extension,
operand read and operand write failures and proves that uncompleted state is
not committed.

The adjacent address-register arithmetic block is also closed across all
2,928 legal `ADDA/SUBA/CMPA` words and 144 mode-7 holes. Word sources are
sign-extended before an always-32-bit operation, `ADDA/SUBA` preserve the
complete CCR, and `CMPA` preserves X while producing 32-bit NZVC without
writing its destination. Every M00 source EA and register alias executes in
the integrated matrix; a separate fault matrix covers the first and second
extension words and operand reads for both sizes.

This is a boot milestone, not complete M00 conformance. Remaining opcode
families, cycle-level interrupt/trace corner
cases and differential/random architectural coverage remain open before M00
can be advertised as complete.

### P3 — M10/M20

- VBR/control registers and restartable faults;
- full 32-bit EA extension parser;
- later integer instructions, stack frames and atomics;
- explicit compiler/binutils profile.

### P4 — EC040 performance core

- six-stage timing closure;
- split I/D caches and write buffer;
- 16-byte burst fills and cache maintenance;
- performance counters and 150 MHz-class target closure.

### P5 — LC040 MMU

- dual MMUs/ATCs, table walker and transparent translation;
- page attributes, precise faults and TLB maintenance;
- MMU Linux process-isolation boot and stress.

### P6 — Full 040 FPU

- FP state, pipeline, rounding/status/exceptions;
- software-emulation hooks and hard-float ABI;
- numerical and context-switch conformance.

### P7 — Extensions and SMP

- MXV only after M40 retirement/context state is stable;
- MXLE only after complete fetch/exception/page-table ABI design;
- MXA/MXMP with coherent fabric, IPI, per-core state and OS support.

## Foundation quality gates

P0 remains complete only while:

- Verilator lint/build accepts the new first-party RTL without blanket warning
  suppressions;
- request and response backpressure are tested;
- word and independent upper/lower byte accesses preserve big-endian semantics;
- memory observes canonical physical byte lanes;
- an out-of-range response becomes legacy BERR;
- existing fx68k simulation tests remain unaffected;
- documentation and RTL agree bit-for-bit on interface fields.

The active P1 exit gate additionally requires generated-ISA freshness checks,
fetch-to-decode integration, exact fault-PC propagation and complete M00 opcode
coverage accounting. Only the first three of those are currently implemented;
full opcode coverage and a retirement reference trace remain open.

## Change policy

- Do not modify fx68k to make the new fabric easier.
- Do not add a feature without a specification and test oracle.
- Do not encode instructions in opaque ROMs or duplicated handwritten tables.
- Do not couple the CPU to a board/vendor primitive.
- Do not claim a clock until post-route timing proves it.
- Do not claim M40, MXV, MXLE or SMP from partial datapath demonstrations.
