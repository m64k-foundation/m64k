# Scalar multiply implementation

Status: implementation baseline for the normative-draft `M64K-v1.scalar-multiply-divide` semantic contract. This document describes microarchitecture, not instruction encoding or ABI.

## Organization

`m64k_scalar_multiply` is a four-register throughput-one execution pipeline. Request capture truncates B, W, and L operands to their selected width and carries Q operands unchanged. The partial-product stage computes four unsigned 32-by-32 products. The reduction stage combines both cross products and applies the Q-form two's-complement high-half corrections. The merge stage reconstructs the 128-bit product, performs the width-specific signed correction for sub-Q operations, selects narrow or widening results, and computes optional `NZCV`.

Every request and response carries the exact private backend tag: execution context, ROB index, ROB generation, allocation sequence, and uop index. The allocator must not reuse a complete tag while any execution unit can still hold work or a response for that tag. This is a microarchitectural lifetime rule and is not part of the ISA or ABI.

The output register holds an atomic response bundle under backpressure. A widening Q response contains both `LOW` and `HIGH` result roles in the same handshake. Exact-tag squash can remove work from any unpublished pipeline stage, but it cannot retract or alter a response once `response_valid` is observable. The completion collector remains responsible for validating the returned tag against the live ROB allocation before wakeup or physical writeback.

## Silicon status

The current pipeline is a correct throughput-one baseline, not the final multiplier topology. With the required 64-bit allocation-lifetime sequence in every in-flight tag, its four parallel 32-by-32 products synthesize to 30,795 generic primitive cells and 1,291 enabled flip-flops in the pinned ORFS/Yosys environment. B/W/L operand preparation drives unused upper and cross lanes to zero, allowing structural operand isolation; this does not generate or imply a gated clock.

The next physical comparison must evaluate this tiled implementation against staged radix-4 Booth recoding with a compressor tree and registered final addition. Both alternatives must use the same library, SDC, physical utilization, activity, and placement seed. A production choice requires mapped timing, placed area, fan-out, congestion, clock load, and activity-based power. Generic cell counts alone do not establish frequency, area in square micrometres, or energy.

## Verification evidence

The warning-fatal RTL test covers all 262,144 B-width signed/unsigned narrow/widening operand combinations, directed W/L/Q boundaries, one-request-per-cycle throughput, blocked-response stability, atomic Q results, exact-tag squash at every unpublished stage, and selective squash of one operation among multiple in-flight operations. The silicon frontend independently elaborates the source with Slang, runs Yosys structural checks, proves that at least 1,000 sequential cells survive synthesis, and records hashed generic QoR inputs and outputs.

No M64K opcode is allocated by this implementation. No operating-system behavior, process identity, syscall convention, or software-specific shortcut exists in the datapath.
