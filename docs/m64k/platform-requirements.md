# M64K FPGA platform requirements

| Field | Value |
|---|---|
| Status | Active selection criteria; no primary board selected |
| Version | 0.2 |
| Scope | Reference FPGA platform for the M64K development roadmap |
| Compatibility | Board choice must not alter the architectural ISA contract |

The legacy Tang target is not a candidate for the new core. Platform selection
will follow synthesis probes; no vendor is part of the architecture.

## Required capabilities

- modern FPGA with ample LUT/FF headroom for CPU, dual caches/MMUs, FPU, debug
  and later vector/coherence logic;
- BRAM/URAM capacity for cache data/tags, ATCs, queues and trace buffers;
- DSP blocks for pipelined multiply, divide assist and FPU/M64K-V;
- at least 4 GiB of directly usable DDR4/LPDDR4/LPDDR5 on the primary native-M64K board;
- preference for an upgrade path beyond 4 GiB so the 48-bit physical-address implementation can be exercised rather than only simulated;
- supported hard or production-quality memory controller with simulation model;
- user logic capable of measured 150 MHz or better after routing for the compatibility reference core, with materially higher performance evaluated for the later pipelined/out-of-order implementation;
- JTAG, UART and practical storage/network expansion;
- reproducible Linux-host build and programming tools.

## Evaluation scorecard

For each candidate record:

| Category | Measurement |
|---|---|
| Logic | LUT/FF count and P0/P2/P4 utilization estimates |
| Local memory | BRAM/URAM bits, ports and achievable cache geometry |
| Arithmetic | DSP count, widths, cascade and Fmax |
| External memory | capacity, width, rate, controller type and PL accessibility |
| Timing | post-route CPU/fabric Fmax using identical synthesis probes |
| Tooling | versions, license, automation, simulator and CI feasibility |
| I/O | PCIe/Ethernet/storage/UART/JTAG availability |
| Practical | price, availability, documentation and community support |

## Selection stages

1. Compile small ALU, register-file, cache-tag and 128-bit fabric probes.
2. Bring up the vendor DDR example and measure user-interface latency/bandwidth.
3. Port the first-party M64K fabric/core probes; use `fx68k` only as an optional compatibility cross-check.
4. Select the primary board using measured results and a declared cost ceiling.
5. Keep at least one second vendor adapter buildable to detect accidental
   dependence on proprietary primitives.

An onboard hard ARM/RISC-V processor may manage configuration, but it must not
execute target workloads in place of the M64K RTL.
