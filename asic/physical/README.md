# M64K physical exploration

This directory contains target-owned OpenROAD Flow Scripts configurations for physical exploration of real sequential M64K execution units. The configurations do not add timing wrappers, substitute behavioral models, or modify architectural RTL.

The first exploration point uses the pinned public Nangate45 platform, a 4 ns clock period, 20% input/output timing budgets, and 50% initial core utilization. The clock period is an optimization point rather than an architectural frequency guarantee. Nangate45 results are comparative implementation evidence only and are not fabrication sign-off.

Run the complete synthesis, floorplan, placement, clock-tree, routing, extraction, and final-report flow with:

```sh
make -f asic/physical/Makefile nangate45-native-multiply
make -f asic/physical/Makefile nangate45-native-divider
```

Generated results, logs, reports, and objects are written below `build/asic/physical/`. The immutable container lock, RTL manifests, configuration, constraints, tool versions, and flow variant together identify an exploration run.

The SDC files constrain the real `clock` input and treat `reset` as an ordinary synchronous input. The request, response, and squash interfaces are synchronous to that same execution clock, which owns their non-zero external input and output delay budgets. No false paths, multicycle paths, clock groups, case analysis, or asynchronous clock assumptions are declared. Any exception requires an independently reviewed interface contract before it may enter a target.

The public ORFS driver does not make every tool warning fatal. Therefore each target performs an independent recursive audit of its generated logs after ORFS returns. The audit has no warning allowlist: any warning or error diagnostic fails the target. A future target may classify an exact third-party diagnostic only after adding the structural proof and adjacent rationale required by the repository engineering rules.

Logic mapping may bind both outputs of a multi-output standard cell into OpenDB even when one output has no load. The target-owned pre-global-route hook removes only driver-only signal nets whose standard-cell instance has another live output. It fails closed on block terminals, input or inout pins, and instances without a live sibling output. This is database connectivity cleanup, not a warning waiver: `repair_design` never sees a connection that cannot physically carry information, while every potentially functional one-pin net remains fatal. `inspect_one_pin_nets.tcl` provides a read-only inventory before and after the hook.

Physical acceptance requires all ORFS stages to complete, the independent warning audit to pass, every register endpoint to be clocked, every input/output path to be constrained, and final setup/hold, routing, antenna, and DRC reports to be reviewed. The executable gate requires the canonical final detailed-route antenna, DRC, and OpenSTA constraint-integrity reports to exist and every report shard sharing a canonical filename prefix to be empty; absence of a canonical report is a failure, not evidence of zero violations. It cross-checks the final text report and ORFS JSON metrics for zero setup, hold, slew, capacitance, and fanout violations, zero setup/hold TNS, non-negative setup/hold slack, positive Fmax, and zero flow warnings or errors. Missing, malformed, non-finite, conflicting duplicate, or contradictory required evidence is fatal. Successful completion remains non-signoff because the public platform does not provide an authorized foundry production stack.

The first completed but rejected run and its diagnostic inventory are recorded in `exploration-results-2026-08-20.md`. The generated measurements in that report are stale whenever shared execution contracts change and must not be quoted as current QoR without a clean source-consistent rerun.
