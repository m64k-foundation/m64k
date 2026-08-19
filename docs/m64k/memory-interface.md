# M64K internal memory interface v0

The first implemented M64K block is a board-neutral, decoupled memory
request/response channel. It is not AXI and does not expose DDR timing. Board
adapters translate this protocol to AXI, Avalon or vendor-native controllers.

## Fixed v0 geometry

| Property | Value |
|---|---|
| Address | 32-bit byte address |
| Transfer payload | 128 bits / 16 physical byte lanes |
| Transaction ID | 4 bits |
| Source ID | 4 bits |
| Channels | Independent ready/valid request and response |
| Outstanding policy | Defined by endpoints; the first bridge allows one |

Lane `n` always contains the physical byte at aligned line base plus `n`:

```text
line_base = address & 0xfffffff0
rdata[8*n +: 8] <-> physical byte line_base+n
```

This convention is endian-neutral. Big/little assembly occurs in CPU frontend
and LSU logic.

## Request

The packed request contains:

- command and architectural access size;
- byte address;
- write data and compare data;
- one write strobe per physical byte lane;
- transaction/source identity;
- instruction/data, supervisor, cacheable, ordered and lock attributes;
- reserved atomic operation selector.

Reads return the entire aligned line. Writes update only asserted strobes.
Address low bits identify the architectural first byte and aid MMIO adapters;
strobes are always relative to the aligned line.

The M00 LSU preserves the CPU's word-alignment rule independently of this line
transport. A long at offset 14 is therefore legal and becomes two ordered word
transactions, one in each adjacent line. Only the final response enables
architectural writeback/retirement; a fault reports the individual beat that
failed, while an already accepted external write is not rolled back.

## Response

The response returns line data, matching IDs, a structured fault code and an
atomic-success bit. A responder must hold response fields stable while valid is
asserted and ready is low.

## Ready/valid rules

- A transfer occurs only on a rising edge with both valid and ready high.
- A producer must hold payload stable while valid is high and ready is low.
- A consumer may apply backpressure indefinitely.
- Request and response have no combinational requirement on each other's ready.
- Reset withdraws valid state; memory contents are not architecturally reset.

## Faults

v0 defines none, access, page, alignment, bus, timeout, ECC and unsupported.
The fabric transports faults; the CPU profile decides which exception/frame
they generate. This separation permits M00 and M40 to share the same memory
backend without sharing fault semantics.

## Ordering

Normal requests are ordered per source in v0. `ordered` requests and fences
cannot pass older requests. An accepted `M64K_MEM_ATOMIC` request is one
indivisible endpoint transaction and returns the pre-update line;
`atomic_success` confirms that the update occurred. `lock` marks the request
for future arbitration/coherence adapters. Unsupported atomic commands return
an explicit fault rather than silently degrading to read/write. Any faulting
atomic response has `atomic_success` clear and MUST leave endpoint storage
unchanged; fault injection and normal access faults obey the same rule.

## First integration

`fx68k_mem_bridge` converts a selected classic 68000 cycle into one fabric
transaction. It maps UDS to the even-address byte and LDS to the following
byte, reconstructs big-endian read words, waits for the response and converts
fabric faults to BERR. It deliberately supports only one outstanding request.

This bridge proves the fabric while retaining the existing CPU. It is not the
memory interface of the future pipelined core.

## Implemented fabric endpoints

`m64k_router_3` decodes three non-overlapping, prefix-masked regions. It allows
one routed transaction in flight, preserves IDs and backpressure, statically
rejects malformed/overlapping maps, and returns `M64K_FAULT_ACCESS` for an
unmapped address.

`m64k_fetch_frontend` is the first native master. It performs cache-line reads,
keeps a two-line prefetch buffer and discards redirected responses by internal
epoch while still completing the ready/valid transaction correctly.
