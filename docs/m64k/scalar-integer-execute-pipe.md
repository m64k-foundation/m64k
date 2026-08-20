# Scalar integer execution pipe

| Field | Value |
|---|---|
| Status | Implementation contract for the current execution-unit baseline |
| Version | 0.1-development |
| Scope | Tagged single-stage wrapper around the scalar integer ALU |
| Architectural effect | None beyond the operations defined by the scalar integer ALU contract |

## Purpose

The scalar integer ALU is a combinational semantic primitive. The production out-of-order backend cannot issue directly into an untagged primitive because backpressure, ROB-slot reuse, selective recovery, and simultaneous hardware threads require an exact execution lifetime. The scalar integer execution pipe adds that lifetime without allocating an instruction encoding or embedding decoder, operating-system, privilege, or memory behavior.

Each accepted request carries the complete private execution tag defined by `m64k_execute_backend_pkg`: execution context, ROB index, ROB generation, allocation sequence, and micro-operation index. The allocator MUST NOT reuse a complete tag until all units that accepted it have either completed or acknowledged cancellation.

## Handshake and cancellation

Request and response channels use independent ready/valid handshakes. A request is accepted only when `request_valid && request_ready`. The pipe sustains one accepted operation per cycle when the response consumer remains ready.

The response is a registered atomic bundle. While `response_valid && !response_ready`, its tag, result, flags, and extend state remain stable. Once a response becomes observable, squash cannot retract or alter it; the completion collector validates the tag against the live ROB allocation and drains stale responses. An exact-tag squash may discard a request accepted in the same cycle before publication. A nonmatching squash has no effect.

The response contains zero results for `CMP` and `TST`, and one result with role `LOW` for every other scalar integer operation. NZCV validity and values, and persistent-X validity and value, are published in the same response. No physical-register or architectural state is written by this unit; publication remains a retirement responsibility.

The four unallocated internal operation values are implementation-integrity failures, not architectural illegal-instruction traps. The ALU marks their result and condition outputs invalid. The registered wrapper deasserts request readiness, asserts `integrity_error`, and publishes no response. Decode and dispatch must never generate these values; the core integrity controller owns escalation if malformed internal work appears.

## Verification and silicon intent

The underlying ALU remains the independently tested semantic reference. Wrapper verification MUST additionally cover request throughput, output backpressure, exact and nonmatching squash, held-response irreversibility, simultaneous identities from different cores and hardware threads, and the zero-result compare/test forms. Externally bound assertions MUST prove blocked-response stability and that a published response is not retracted by squash. Production RTL contains no compile-time switch that changes these functional paths; verification targets compile and execute the bound properties explicitly.

This baseline adds one output register around the ALU to break the issue-to-completion combinational path. It does not establish the final issue, bypass, wakeup, or physical-register topology. Those choices require technology-mapped timing, area, power, and fan-out evidence within the complete backend.

Reset clears only response validity. The response payload is retained while invalid and is fully overwritten before validity is asserted; idle cycles do not zero or toggle the complete tag/result/condition bundle merely for simulation convenience.
