# Roadmap to an M68040-class system

## Target definition

The primary goal is **software-visible M68040 architectural compatibility**,
not pin-for-pin or cycle-for-cycle reproduction of a Motorola package. The new
processor must correctly implement instructions, registers, privilege, faults,
MMU, caches and FPU state while using a board-neutral internal memory protocol.

The Tang Nano 20K is not a design constraint for the new system. Its existing
target may remain as a frozen MC68000 regression artifact until superseded.

## Proposed modular architecture

```text
                 +---------------- retirement / precise state ---------------+
                 |                                                            |
fetch -> decode/EA -> integer issue/execute -> load/store -> writeback/commit
  |          |             |                    |                 |
  |          |             +-- mul/div          |                 +-- faults
  |          +-- control-register file           +-- D-MMU/D-ATC/D-cache
  +-- I-MMU/I-ATC/I-cache                        +-- write buffer
                 |                                      |
                 +---------- internal memory fabric ----+
                                      |
                         board-specific DDR adapter

F-line decode -> FPU register file -> FP execute/round -> precise FP commit
```

The architectural state/commit boundary is essential. Page faults, access
errors and FPU exceptions must report a precise instruction and be restartable;
this cannot be added reliably after an imprecise pipeline is complete.

## Frequency strategy

Clock rate is a result of pipeline boundaries, FPGA family and place-and-route,
not a constant chosen by calendar year. The design should nevertheless stop
targeting historical 68000 frequencies.

Proposed performance gates for the new core:

| Gate | CPU target | Purpose |
|---|---:|---|
| Bring-up | 100 MHz | First complete timing-clean pipeline |
| Normal target | 150 MHz or better | Practical modern soft CPU baseline |
| Stretch | 200–250+ MHz | Larger/faster FPGA after profiling |

These are targets, not claims. Every milestone must publish post-route Fmax,
resource usage and benchmark IPC. A 150 MHz six-stage design with caches can
greatly outperform a higher-clock serialized core; IPC, miss rate and memory
latency matter as much as clock.

Required clock architecture:

- CPU, interconnect and DDR user interface may use different clock domains.
- CDCs must use explicit asynchronous FIFOs or synchronizers.
- PLL/reset generation belongs in board adapters, outside the CPU.
- Long decode, EA, shifter, TLB and FPU paths need deliberate pipeline stages.
- Multicycle/false-path constraints must be generated and reviewed, not hidden.
- Performance counters should expose cycles, retired instructions, branches,
  cache/TLB misses and stalls.

## Memory capacity

An M68040 has 32-bit logical and physical addresses. Therefore:

- each virtual address space is at most 4 GiB;
- the shared physical address space is at most 4 GiB;
- RAM, ROM, MMIO, PCIe/expansion windows and reserved regions share that 4 GiB;
- a system cannot expose a full 4 GiB of linear RAM plus MMIO simultaneously
  without remapping/banking or a non-68040 physical-address extension.

Recommended milestones are 256 MiB for early bring-up, 1 GiB for the main
development platform and 2–4 GiB when the board and physical map are selected.
The RTL must use 32-bit physical addresses from the beginning even if the first
board populates less memory.

The MMU gives each process its own 4 GiB virtual view; it does not multiply
physical RAM. All cores in an SMP system share the same physical capacity.

Going beyond 4 GiB would be a later Mackerel-specific architectural extension,
for example wider physical page descriptors while retaining 32-bit virtual
addresses. It would require kernel and toolchain/platform changes and would no
longer be a strict M68040 memory model.

## New FPGA/board requirements

Board selection happens after small synthesis probes and must not leak vendor
primitives into the processor. Mandatory criteria:

- enough LUT/FF capacity for CPU, dual MMUs/caches, FPU and debug headroom;
- substantial BRAM for tags, ATCs, queues and early cache prototypes;
- DSP blocks suitable for pipelined integer and floating-point multiply;
- at least 1 GiB attached DDR for the primary development board, preferably
  2–4 GiB for the final single-board target;
- a supported DDR3/DDR4/LPDDR4 controller with a documented AXI/Avalon/native
  user interface and simulation model;
- credible 150–200 MHz user-logic timing closure;
- JTAG, UART, storage/network expansion and reproducible build tools;
- availability, price and licensing acceptable to the project.

Current platform classes worth evaluating include AMD UltraScale+/Versal and
Altera/Intel Agilex families with DDR4/LPDDR4. The final choice requires an
explicit cost ceiling and synthesis results; marketing clock rates are not CPU
Fmax evidence.

Primary vendor references show why a new class of board is appropriate:

- AMD offers UltraScale+ development boards with multi-gigabyte DDR4:
  <https://www.amd.com/en/corporate/university-program/aup-boards/realdigital-aup-zu3.html>
- Intel documents hard DDR4 controllers and Avalon-facing memory interfaces in
  Agilex devices:
  <https://www.intel.com/content/www/us/en/docs/programmable/683216/22-1-2-6-1/hard-memory-controller-features.html>

The presence of an ARM/RISC-V hard core on a board does not replace the m68k
RTL. It may be used only for board management if the architecture keeps the
M68k processor as the machine executing the target software.

## M68040 architectural facts to implement

The official M68040 model includes:

- MC68030-compatible integer architecture with a six-stage pipeline;
- 32-bit nonmultiplexed address/data model and a 4 GiB range;
- separate instruction and data MMUs;
- a 64-entry ATC for each MMU;
- URP, SRP, TCR, ITT0/1, DTT0/1 and MMUSR;
- 4 KiB I-cache and 4 KiB D-cache, each four-way set associative with 16-byte
  lines;
- physical caches, page-controlled write-through/copyback and snooping;
- cache/TLB maintenance instructions;
- integrated 68881/68882-compatible FPU programming model with a hardware
  subset and software emulation hooks;
- multiprocessor atomics and bus-coherency support.

These are coupled requirements. For example, copyback caching changes page
attributes, exception behaviour, DMA and SMP coherence; it is not a standalone
performance option.

## Implementation milestones and exit gates

### M0 — Freeze and characterize MC68000

- Broad ISA/CCR/exception/bus conformance suite.
- Instruction retirement trace from fx68k.
- Symbolic description and round-trip tooling for existing micro/nanocode.
- FPGA post-route timing/resource baseline.

Exit: reproducible differential reference, not merely a smoke test.

### M1 — Board-neutral fabric and new memory platform

- Typed request/response protocol carrying address, size, byte enables,
  instruction/data, privilege, atomic and cacheability information.
- fx68k adapter, RAM model, DDR adapter and error responses.
- 32-bit physical map and discovery/boot structure.
- Select a new FPGA board from measured synthesis and DDR probes.

Exit: existing 68000 firmware runs through the fabric at 100 MHz-class timing
with at least 256 MiB memory.

### M2 — New integer core, 68000 compatibility mode

- Modular fetch/decode/EA/execute/LSU/commit pipeline.
- Precise exceptions from the start.
- Differential execution against fx68k for legal 68000 instructions.

Exit: full 68000 conformance and Linux NOMMU boot on the new core.

### M3 — MC68010 and MC68020 architecture

- Control registers, VBR, restartable faults and new stack frames.
- Full 32-bit addressing, extension-word EA engine and generation ISA.
- Long arithmetic, bitfields, CAS/CAS2 and revised privilege/trace state.

Exit: architecture tests plus an explicit 68020 toolchain profile.

### M4 — MC68EC040-class integer/cache system

- Six-stage performance-oriented IU.
- Separate I/D caches, write buffer and 16-byte line fills.
- Cache-control instructions and self-modifying-code correctness.
- Memory attributes and board DDR burst adapter.

Exit: cache stress, precise-fault tests and timing at the normal target.

### M5 — MC68LC040-class MMU

- Separate I/D MMUs and 64-entry ATCs.
- 4/8 KiB page-table walker, transparent translations and page attributes.
- URP/SRP/TCR/TTR/MMUSR and PTEST/PFLUSH behaviour.
- Precise page/access faults and context-switch/TLB tests.

Exit: MMU-enabled Linux boots, isolates processes and survives fault/restart
stress.

### M6 — Full MC68040 FPU

- Eight 80-bit FP registers, FPCR/FPSR/FPIAR.
- IEEE formats, rounding modes, status and precise exceptions.
- Hardware instruction subset plus software package path for unimplemented
  68881/68882 operations.
- hard-float ABI/toolchain/userspace profile.

Exit: numerical conformance, exception, context-switch and Linux hard-float
tests.

### M7 — Mackerel ISA extensions

Only after the baseline is stable: versioned custom instructions, capability
discovery, assembler/disassembler, compiler patterns and OS state support. See
`isa-extensions.md`.

### M8 — Multicore/SMP

- Multiple cores behind a coherent fabric.
- CAS/CAS2/TAS atomicity and a documented memory model.
- Cache-coherence protocol or an initially uncached shared-memory milestone.
- Per-core reset/ID/timer, IPI and interrupt routing.
- TLB shootdown, cache maintenance and OS platform support.

Exit: litmus tests, concurrent stress, secondary-core boot and an audited OS
SMP port. SMP is a SoC project after the single-core CPU is trustworthy.

## Complexity assessment

| Goal | Relative scope |
|---|---|
| Verify current MC68000 | Medium |
| MC68010 compatibility | High |
| MC68020 ISA/addressing | Very high |
| EC040 pipeline and split caches | New CPU microarchitecture |
| LC040 dual MMU and precise faults | New virtual-memory subsystem |
| Full 040 FPU | New numerical execution subsystem |
| Custom ISA and GCC | Hardware plus complete toolchain contract |
| Coherent SMP | New multiprocessor SoC and OS platform |

The project is feasible only as gated, separately testable generations. Trying
to implement MMU, FPU, new opcodes, high clock and SMP in one core revision
would make failures nearly impossible to localize.
