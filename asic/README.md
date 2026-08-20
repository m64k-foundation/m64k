# M64K ASIC exploration flow

This directory owns reproducible silicon-frontend and physical-exploration recipes for first-party native M64K RTL. The tool environment is locked by immutable OCI digest in `containers/asic/tool-lock.json`; generated products belong under `build/asic/` and are not tracked.

The initial `native_integer_alu` and `native_shift_rotate` targets are intentionally focused structural probes. They validate independent Slang elaboration and generic Yosys/ABC synthesis of the production scalar execution datapaths. They are combinational and therefore cannot produce a meaningful clock-frequency or routed-core claim. Timing, floorplanning, clock-tree, power, IR-drop, DRC, LVS, and antenna gates begin only after a sequential core partition and its SDC are available.

Run from the repository root:

```sh
make asic-tools
make asic-native-integer-lint
make asic-native-integer-synth-check
make asic-native-integer-synth
make asic-native-shift-lint
make asic-native-shift-synth-check
make asic-native-shift-synth
make asic-native-shift-netlist-equiv
make asic-native-shift-fast-lint
make asic-native-shift-fast-synth-check
make asic-native-shift-fast-synth
make asic-native-shift-fast-equiv
make asic-native-shift-shared-lint
make asic-native-shift-shared-synth-check
make asic-native-shift-shared-synth
make asic-native-rotate-extend-lint
make asic-native-rotate-extend-synth-check
make asic-native-rotate-extend-synth
make asic-native-multiply-lint
make asic-native-multiply-synth-check
make asic-native-multiply-synth
make asic-native-divider-lint
make asic-native-divider-synth-check
make asic-native-divider-synth
```

The tagged scalar-integer execute pipe, four-register multiplier, and radix-4 divider are sequential execution-unit baselines. After adoption of the 64-bit allocation-lifetime sequence and fail-closed illegal-uop handling, generic synthesis reports 2,118 cells and 164 enabled flip-flops for the integer execute pipe, 30,795 cells and 1,291 enabled flip-flops for the multiplier, and 5,240 cells with 513 sequential cells for the divider. The scalar integer ALU itself contains 1,687 generic cells. A dedicated structural gate fails if synthesis removes the expected registered state before the exact ABC extracted-cone diagnostic can be classified. These counts are not mapped area or frequency evidence. Physical comparison begins only with target-owned SDC, library mapping, floorplan, placement, clock-tree, routing, and STA.

The generic synthesis counts are structural baselines, not technology area. The current functional shift/rotate reference intentionally remains unfrozen for production: it computes width-specific rotate-through-X rings in parallel and is therefore substantially larger than the integer ALU. The production selection requires an equivalence-checked comparison between a shared throughput-one fast path plus tagged iterative rotate-through-X execution and any proposed fixed-latency alternative under a real library and SDC.

The netlist-equivalence target uses the Yosys internal SAT engine to prove every output of the generated generic shift/rotate netlist exactly equal to its RTL source for every input combination. Candidate-selection equivalence and PPA requirements are defined in `shift-rotate-acceptance.md`.

The ordinary fast-path candidate synthesizes to 2,151 generic primitive cells and 2,503 wire bits, compared with 4,882 cells and 5,498 wire bits for the complete functional reference. Its constrained SAT miter proves the generated candidate netlist equal to the reference for `ASL`, `ASR`, `LSL`, `LSR`, `ROL`, and `ROR`, including validity and every flag value. It also proves that the candidate rejects `ROXL` and `ROXR` with invalid, zero-valued outputs and that the reference preserves X for the six supported operations. The ignored build directory contains `equivalence.json` with hashes of both source manifests, every source, the generated candidate netlist, miter, proof log, flow recipe, and immutable tool image. This is deliberately not a like-for-like complete-unit comparison: the candidate excludes both rotate-through-X operations, their persistent-X interface, and all eventual iterative or direct ROX implementation cost.

The tagged iterative rotate-through-X companion synthesizes to 3,035 generic cells and retains 334 sequential cells with the 64-bit allocation-lifetime sequence. Its exhaustive and protocol regression is complete, but adding this isolated count to the fast path yields 5,186 cells, about 6.2 percent above the 4,882-cell complete reference. It therefore fails the current 20-percent early selection threshold and is not production-frozen. Further sharing and technology-mapped physical comparison are required; functionality alone does not justify selecting it for replication.

The complete tagged shared-barrel candidate reuses one fast datapath for ordinary operations and two algebraic passes for rotate-through-X. It synthesizes reproducibly to 4,482 generic cells and 242 sequential cells. Its arithmetic count is 13.6 percent smaller than the current-tag sum of the separately synthesized fast and iterative blocks, but that sum is not a like-for-like integrated design: the fast block has no tag, response storage, or arbitration wrapper. The candidate is only 8.2 percent smaller than the conservative acceptance reference and therefore still fails the 20-percent selection threshold. It remains preserved as verified negative design evidence, not as a selected production unit.

The public ORFS image and public technology platforms provide comparative architecture and flow evidence only. They do not constitute foundry production sign-off.

Real sequential Nangate45 placement-and-route configurations live under [physical/](physical/README.md). Their acceptance targets fail on every warning or error found recursively in generated logs. The first multiplier and divider runs reached GDS but remain rejected evidence while their physical diagnostics are unresolved.
