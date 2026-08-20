# M64K FPGA platform requirements

| Field | Value |
|---|---|
| Status | Active selection criteria; no primary board selected |
| Version | 0.2 |
| Scope | Reference FPGA platform for the M64K development roadmap |
| Compatibility | Board choice must not alter the architectural ISA contract |

Platform selection follows native-core synthesis and memory-controller probes; no vendor primitive or board is part of the architecture.

## Required capabilities

- modern FPGA with enough logic for at least one complete native OoO core, MMU, scalar FPU, coherence endpoint, debug, and representative cache controllers;
- BRAM/URAM capacity for cache data/tags, ATCs, queues and trace buffers;
- DSP blocks for pipelined multiply, divide assistance, the scalar FPU, and future vector execution;
- at least 8 GiB of directly usable DDR4/LPDDR4/LPDDR5 on the primary board, with 16 GiB or more preferred so addresses above the 32-bit boundary are exercised continuously;
- supported hard or production-quality memory controller with simulation model;
- post-route timing, bandwidth, latency, area, and power reports for the same native RTL probes on every candidate; an RTL or synthesis-only clock target is not evidence of achieved frequency;
- JTAG, UART and practical storage/network expansion;
- reproducible Linux-host build and programming tools.

## Evaluation scorecard

For each candidate record:

| Category | Measurement |
|---|---|
| Logic | LUT/FF count and native frontend/backend/cache utilization estimates |
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
3. Port the first-party native M64K fabric, cache, MMU, and core probes without substituting another processor.
4. Select the primary board using measured results and a declared cost ceiling.
5. Keep at least one second vendor adapter buildable to detect accidental dependence on proprietary primitives.

An onboard hard processor may manage configuration, but it must not execute target workloads in place of the M64K RTL.
