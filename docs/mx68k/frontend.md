# MX68K frontend and pipeline plan

## Baseline pipeline

The first new core uses six conceptual stages:

```text
F0  choose PC, predict/redirect and begin translation
F1  I-ATC/I-cache lookup, line request and fetch queue fill
D   align variable-length instruction, decode and lower to micro-ops
E   ALU, branch, effective address and multi-cycle issue
M   D-MMU/cache, memory completion and fault capture
C   architectural commit, trace, interrupt and exception entry
```

Stage boundaries may gain skid buffers to close timing. Their ready/valid
contracts are architectural verification boundaries, not permission to change
instruction semantics.

## Instruction fetch

The fetch path operates on canonical 16-byte physical lines. The first RTL
keeps two lines (32 bytes) and emits an ordered 16-bit word stream. The
implemented circular instruction buffer attaches an exact PC and fault code to
each word and presents a configurable logical window to decode. It supports
simultaneous consume/fill at full occupancy, so steady-state decoding need not
insert a queue bubble. The path must handle:

- an instruction beginning at every legal word boundary;
- extension words crossing one or more cache lines/pages;
- independent faults on each fetched line with the exact faulting logical PC;
- cache-inhibited and serialized fetches;
- redirect cancellation without confusing a late response for a current PC;
- self-modifying code through the profile's cache-maintenance rules.

Requests carry an epoch plus transaction identity. Branch, exception, RTE and
debug redirects increment the epoch; responses from older epochs may fill a
safe physically tagged cache line but cannot enter the active decode queue.

The initial `mx68k_fetch_frontend` allows one miss in flight, tags it with an
epoch, buffers two lines and counts line requests, stale responses, delivered
tokens and redirects. The performance version will allow at least two line
fills so sequential prefetch can overlap decoder consumption and DDR latency.

`mx68k_decode_frontend` currently connects fetch, instruction buffering and the
generated M00 predecoder behind one ready/valid backend interface. A redirect
flushes queued words and advances the fetch epoch. Tests cover an instruction
whose extension crosses a line, downstream stalls, odd-PC address error and a
faulting extension at the exact next-line PC.

## Initial predecode rules

The current predecoder is an expanding firmware-boot subset, not yet a claim
of complete M00 decode. It includes general classic effective-address parsing,
MOVE/MOVEA, branches/DBcc, JSR/JMP/RTS, LEA/PEA/LINK/UNLK, MOVEM, quick and
immediate arithmetic/logical operations, register shifts/rotates, bit test,
multiply/divide, both EA-to-Dn and Dn-to-EA arithmetic/logical directions, and
the trap/RTE system forms needed by the real boot ROM. Unknown encodings produce
vector 4. Variable-length forms do not issue until every required word is
present, and a fault remains attached to the exact extension word that caused
it.

Branch displacement length is profile sensitive: `0x00` selects a signed
16-bit extension; `0xff` remains a signed 8-bit displacement in M00/M10 and
selects a signed 32-bit extension only in M20/M40. All targets use the
architectural `instruction_pc + 2` base.

## Prediction

Bring-up uses next-sequential fetch plus early resolution of unconditional
branches. Performance revisions add, in this order:

1. small tagged BTB;
2. saturating direction table for conditional branches;
3. return-address stack for BSR/JSR/RTS-style flows;
4. optional larger or hybrid predictor only if measurement justifies it.

Every prediction records predicted PC and metadata beside the instruction.
Commit compares actual control flow, increments misprediction counters and
redirects by epoch. Prediction never changes exception PC, trace behaviour or
privilege checks.

## Backend hazards

The in-order backend uses bypass/forward paths for integer results and a
scoreboard for iterative multiply/divide, LSU, FPU and future MXV operations.
A micro-op issues only when its operands and destination hazards are clear.
Commit remains ordered even when a long-latency execution unit finishes early.

Stores enter a checked store path only at their profile-defined visibility
point. Speculative MMIO side effects are prohibited. Loads may execute early
only when faults and ordering can still be attributed to the correct oldest
instruction.

## Performance gates

The frontend is measured with counters for fetched bytes, useful decoded bytes,
I-cache/ATC misses, queue-empty cycles, redirects, predictor hits/misses and
discarded old-epoch responses. A feature is kept only when FPGA timing and
workload measurements show a net gain.

The first physical target gate is post-route 150 MHz. A 200–250 MHz result is a
stretch target, not an architectural promise. Pipeline depth and FPGA family
may change without affecting MX68K software compatibility.
