# MX68K FPGA platform requirements

The legacy Tang target is not a candidate for the new core. Platform selection
will follow synthesis probes; no vendor is part of the architecture.

## Required capabilities

- modern FPGA with ample LUT/FF headroom for CPU, dual caches/MMUs, FPU, debug
  and later vector/coherence logic;
- BRAM/URAM capacity for cache data/tags, ATCs, queues and trace buffers;
- DSP blocks for pipelined multiply, divide assist and FPU/MXV;
- at least 1 GiB directly usable DDR3/DDR4/LPDDR4 on the primary board;
- preference for 2–4 GiB on the long-term board;
- supported hard or production-quality memory controller with simulation model;
- user logic capable of measured 150 MHz or better after routing;
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
3. Port the P0 fx68k fabric system without changing protocol semantics.
4. Select the primary board using measured results and a declared cost ceiling.
5. Keep at least one second vendor adapter buildable to detect accidental
   dependence on proprietary primitives.

An onboard hard ARM/RISC-V processor may manage configuration, but it must not
execute target workloads in place of the MX68K RTL.
