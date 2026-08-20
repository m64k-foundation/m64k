# Rejected Nangate45 execution-unit exploration — 2026-08-20

> **Superseded input notice:** the measured netlists below used the earlier 16-bit execution allocation sequence. The first-product ROB lifetime contract now requires 64 bits, so these already-rejected measurements are also stale with respect to current RTL. They remain diagnostic history only and must be regenerated after the physical-warning root cause is resolved.

## Status

These runs are root-cause diagnostic history, not reproducibility evidence or accepted PPA baselines. The historical run did not capture a complete immutable input manifest, and the tracked RTL has since changed, so its exact netlists cannot be reconstructed from current source. OpenROAD Flow Scripts completed synthesis, floorplan, placement, clock-tree synthesis, global routing, detailed routing, extraction, STA, IR analysis, and GDS generation for both real sequential RTL tops. The independent M64K diagnostic audit then rejected both runs because their logs contain warnings and the route-report shard contains physical shorts.

The generated artifacts and measurements are now stale because the shared execution allocation-sequence identity widened after these runs were synthesized. They MUST NOT be quoted as current QoR. A clean source-consistent rerun is required after the remaining physical diagnostics are resolved.

No warning was waived or classified as harmless. The generated products remain ignored below `build/asic/physical/`.

## Run identity

| Property | Value |
| --- | --- |
| Public platform | Nangate45 |
| Library/corner | Nangate Open Cell Library, typical |
| Macro set | None |
| Container | `docker.io/openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0` |
| Yosys | `0.68+post` |
| OpenROAD | `26Q3-1305-gf552262465` |
| OpenSTA | `3.1.0` |
| Flow variant | `explore_4ns` |
| Clock | Real RTL port `clock`, 4 ns period |
| I/O timing budget | 20% of the clock period for synchronous inputs and outputs |
| Initial core utilization | 50% |
| Placement density lower-bound addition | 0.10 |
| Seed status | ORFS defaults; not yet owned explicitly by the M64K configuration |

The unspecified target-owned seed alone prevents promotion to a reproducible accepted baseline. Future accepted runs must set and report the global-placement, global-routing, and detailed-routing seeds explicitly.

## Preliminary measurements

| Target | Placed design area | Final utilization | Sequential cells | Final WNS | Final TNS | Final worst slack | Reported minimum period | Reported Fmax | Final detailed-route DRC report |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `m64k_scalar_multiply` | 38,330 µm² | 50% | 1,099 | 0.00 ns | 0.00 ns | +1.79 ns | 2.21 ns | 453.25 MHz | Empty |
| `m64k_scalar_divider` | 9,603 µm² | 52% | 466 | 0.00 ns | 0.00 ns | +1.36 ns | 2.64 ns | 378.15 MHz | Canonical report empty, but shard `5_route_drc.rpt-5.rpt` contains 3 metal2 shorts; run rejected |

These historical measurements establish only that the then-current structures traversed a real placement-and-route flow under the exploratory constraints. They do not describe the current RTL and do not establish product frequency, area, power, manufacturability, or sign-off closure. Power numbers are intentionally omitted because the run did not provide reviewed workload-derived switching activity. Fmax is the tool's reported minimum-period estimate at this public typical corner, not an M64K frequency commitment.

## Root-cause result for `RSZ-0104`

The original multiplier log contained 981 `RSZ-0104` diagnostics and the original divider log contained 332. A read-only traversal of each pre-global-route `4_cts.odb` found exactly 981 and 332 one-pin signal nets, respectively. Every such net met all of these structural properties:

- its only terminal was an output pin of a standard-cell instance;
- the instance had a second output connected to a net with at least one load;
- no one-pin net terminated at a block port, input, or inout;
- the cells were mapped multi-output cells such as complementary-output flops and half adders, rather than first-party RTL primitives.

The cause was therefore mapped-library database residue: OpenDB retained a net for the unused output of a cell selected for its other output. Such a driver-only connection cannot transmit information and should not enter routing repair.

`remove_unused_cell_output_nets.tcl` now runs through the documented ORFS `PRE_GLOBAL_ROUTE_TCL` hook. It disconnects and destroys only the proven class above and aborts on every other one-pin topology. This is a connectivity correction, not a diagnostic suppression. Repeating global route removed all 981 and 332 `RSZ-0104` messages, and a post-route read-only traversal reported zero one-pin nets for both targets. RTL and SDC constraints were unchanged.

These reruns validate the connectivity correction only. Their PPA is stale because the execution tag contract changed concurrently, and the physical targets remain rejected due to the independent diagnostics listed below.

## Remaining fatal diagnostic evidence

The original multiplier audit detected 997 diagnostics and the divider audit detected 347 diagnostics. The `RSZ-0104` class has now been corrected at its root as described above; it is no longer part of the remaining inventory.

The exact original non-`RSZ-0104` inventory was:

| Rule | Tool/stage | Multiplier | Divider | Root-cause status |
| --- | --- | ---: | ---: | --- |
| `IFP-0028` | OpenROAD floorplan | 1 | 1 | Corrected by target-owned core margins aligned to the 0.19 µm placement-site width and 1.40 µm row height. A focused current-source divider floorplan emitted no snapping diagnostic. |
| `EST-0027` | OpenROAD floorplan timing repair | 1 | 1 | Unresolved pinned-flow behavior. ORFS invokes timing repair before placement parasitics exist and deliberately falls back to the Liberty wire-load model. Inventing placement parasitics for unplaced cells would create false precision. |
| `PDN-1051` | OpenROAD PDN generation | 2 | 2 | Corrected by a target-owned macro-free PDN recipe retaining the platform standard-cell M1/M4/M7 grid. A focused current-source divider PDN run emitted no empty-grid diagnostic. |
| `GRT-0281` | OpenROAD pre-CTS global placement | 1 | 0 | Unresolved. This is the real 1,100-terminal clock net before clock-tree synthesis; it is not evidence of the post-CTS clock topology and has not been suppressed. |
| `DRT-0120` | OpenROAD pin access in global and detailed route | 6 | 6 | Unresolved real high-fanout topology: three nets per design, reported in two stages. Each is driven by `BUF_X8` and has 121–147 loads. Liberty defines no maximum fanout, final STA reports zero slew, capacitance, and fanout violations, and `BUF_X8/Z` is characterized through 484.009 fF. No arbitrary fanout constraint has been introduced; distribution or logic replication requires a current-source physical comparison. |
| `GRT-0246` | OpenROAD antenna repair in global and detailed route | 2 | 2 | The public library contains no `ANTENNACELL`-class diode, so repair cannot be performed. The configuration now skips the impossible repair invocation, while the independent acceptance gate requires both the final detailed-route antenna report and DRC report to exist and be empty. This change has not yet been validated in a clean current-source route. |
| `RCX-0514` | OpenRCX final extraction | 1 | 1 | Unresolved pinned ORFS API use. `final_outputs.tcl` calls the deprecated `extract_parasitics -ext_model_file` form. Disabling extraction or falling back to estimated parasitics is not acceptable. |
| KLayout DEF/reader DBU mismatch | KLayout stream merge | 1 | 1 | Corrected in a generated target-owned technology file. The pinned template's technology DBU and OpenDB DEF DBU are 0.0005 µm, but its LEF/DEF reader override was 0.0001 µm. The generator validates both pinned values and changes only the reader override. A focused merge emitted no DBU diagnostic. |
| `GUI-0076` | Qt during final image generation | 1 | 1 | Corrected by creating a private mode-0700 runtime directory and setting `XDG_RUNTIME_DIR` in the ephemeral physical-flow container. A focused KLayout/Qt invocation emitted no runtime-directory diagnostic. |

Counts after the focused corrections cannot be presented as a new run inventory because routing and final extraction have intentionally not been rerun after the shared execution-tag contract changed. The acceptance target remains fail-closed against all existing logs and also fails if the final detailed-route antenna or DRC reports are absent or non-empty.

The unresolved diagnostic classes are:

- `DRT-0120` high-fanout routed nets;
- `EST-0027` wire-load fallback before estimated parasitics exist;
- `GRT-0281` high clock fanout before clock-tree synthesis in the multiplier flow;
- `RCX-0514` use of a deprecated extraction option by the pinned ORFS flow.

Each issue requires either a root-cause correction or the exact independent structural proof required by the repository rules. The current audit contains no allowlist, so none of these findings can be hidden by the flow returning success.

## Reproduction and acceptance behavior

The raw ORFS runs, useful only while investigating rejected diagnostics, are:

```sh
make -f asic/physical/Makefile nangate45-native-multiply-orfs
make -f asic/physical/Makefile nangate45-native-divider-orfs
```

The public acceptance targets run ORFS and then enforce the fatal diagnostic audit:

```sh
make -f asic/physical/Makefile nangate45-native-multiply
make -f asic/physical/Makefile nangate45-native-divider
```

At the state recorded here, both public targets must fail. A passing public target is meaningful only after the generated logs contain no warning or error diagnostics.
