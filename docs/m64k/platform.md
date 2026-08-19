# M64K reference platform

| Field | Value |
|---|---|
| Status | Draft v0 register blocks implemented; SoC integration and firmware bring-up pending |
| Version | 0.1-development |
| Scope | Board-neutral reset, memory map, UART, timer, and discovery contract |
| Compatibility | M00-visible low-address aperture; extensible to native M64K |

The reference platform is the software-visible boundary between an M64K processor and board-specific memory or I/O adapters. It does not expose FPGA vendor primitives or DDR signaling. The addresses in this draft are reserved for the reference implementation, but the boot map is not an implemented-system claim until a complete SoC top, reset path, interrupt controller, ROM image, and firmware integration test exist.

## M00 boot map

The initial M00 platform keeps all required boot resources inside the 24-bit address aperture.

| Address range | Size | Function |
|---|---:|---|
| `0x00000000–0x0000ffff` | 64 KiB | Boot ROM and reset vectors |
| `0x00800000–0x00bfffff` | 4 MiB | Initial coherent simulation RAM |
| `0x00f00000–0x00f00fff` | 4 KiB | UART |
| `0x00f01000–0x00f01fff` | 4 KiB | Per-core timer |
| `0x00f02000–0x00f02fff` | 4 KiB | Platform discovery registers |

All other accesses return an access fault. Memory capacity is an implementation parameter and not a native M64K architectural limit. Later M20/native platform versions may add RAM above the M00 aperture without changing these boot aliases.

## Byte and register ordering

Memory stores physical bytes in increasing address order. M00 accesses assemble them big-endian. Byte-wide UART registers occupy their listed byte address. Multi-byte discovery and timer registers are stored in big-endian byte order: the most significant byte is at the lowest address.

## UART registers

| Offset | Width | Access | Meaning |
|---|---:|---|---|
| `0x00` | 8 | W | Transmit one byte when `STATUS.TX_READY` is set |
| `0x04` | 8 | R | Receive one byte; reading consumes the pending byte |
| `0x08` | 8 | R | Status: bit 0 `TX_READY`, bit 1 `RX_VALID` |
| `0x0c` | 8 | R/W | Control: bit 0 enables receive interrupt |

Receive interrupt is assigned M00 interrupt level 5 by the future interrupt controller. `TX_READY` is one exactly when the one-byte transmit holding register is empty. A transmit write made while it is full is held at the internal request boundary until the downstream ready/valid consumer accepts the previous byte; no byte is overwritten or dropped. `TX_VALID` and its data remain stable while the downstream consumer applies backpressure. The receive holding register also stores one byte. `RX_VALID` remains set until an accepted read of `RX_DATA`; a simultaneously arriving byte is not erased by a read that began while the holding register was empty.

## Timer registers

| Offset | Width | Access | Meaning |
|---|---:|---|---|
| `0x00` | 32 | R | Free-running cycle counter, low 32 bits |
| `0x04` | 32 | R/W | Compare interval in core clocks; zero disables expiry |
| `0x08` | 8 | R/W | Control: bit 0 enable, bit 1 periodic, bit 2 interrupt enable |
| `0x0c` | 8 | R/W1C | Status: bit 0 expiry pending |

Writing the enable bit loads the current interval. A zero interval never expires. In one-shot mode expiry clears enable. In periodic mode expiry reloads the interval. Timer interrupt is assigned M00 interrupt level 6 by the future interrupt controller and remains asserted while pending and interrupt-enabled; writing one to `STATUS.PENDING` acknowledges it. The free-running counter and interval counter advance in the timer input clock domain. Rewriting `INTERVAL` while enabled restarts the countdown from the new value. Disabling does not clear a pending expiry. A status W1C accepted on the same edge as expiry has priority and leaves pending clear.

## Discovery registers

| Offset | Width | Access | Meaning |
|---|---:|---|---|
| `0x00` | 32 | R | ASCII signature `M64K` (`0x4d36344b`) |
| `0x04` | 16 | R | Platform major version |
| `0x06` | 16 | R | Platform minor version |
| `0x08` | 32 | R | Implemented compatibility-profile bitmap |
| `0x0c` | 32 | R | Core count |
| `0x10` | 32 | R | Current core identifier |
| `0x14` | 32 | R | Current hardware-thread identifier |
| `0x18` | 32 | R | Physical address width |
| `0x1c` | 32 | R | Populated RAM bytes in the M00 aperture |

The initial profile bitmap sets bit 0 for M00. Feature bits advertise implemented contracts only; roadmap features must read zero. Discovery v0 reports a 32-bit physical address width because the implemented memory transport v0 carries 32-bit addresses. The planned 32-through-48-bit parameterization must not be advertised until the transport, routers, endpoints, MMU, and platform descriptors all implement it.

## Access and fault policy

UART and timer registers accept only the width shown in their tables and the naturally addressed byte lanes. Discovery registers accept their listed 16- or 32-bit read width. Writes to discovery registers, reads from write-only registers, writes to read-only registers, malformed strobes, wrong sizes, reserved offsets, and accesses outside a device aperture return `M64K_FAULT_ACCESS` without changing state. Atomic commands return `M64K_FAULT_UNSUPPORTED` without changing state. Fences complete successfully and have no register side effect. Every response preserves the request transaction and source identifiers and remains stable under response backpressure.

## Reset and firmware contract

At reset, ROM longword zero supplies the initial supervisor stack pointer and longword one supplies the initial PC, following the M00 architecture. The initial firmware must validate the platform signature before using optional devices. It may use the UART immediately, configure the timer, discover memory, and transfer control to a payload in RAM.

The future native boot contract will extend discovery with 64-bit memory descriptors, topology, interrupt-controller information, firmware services, and a versioned device description. It will not reinterpret this v0 register map silently.
