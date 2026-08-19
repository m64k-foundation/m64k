# Firmware and software stack

## Reset and C runtime

`vectors.s` places SSP=`0x00800000` and reset PC=`_start` at the beginning of
the ROM image. The linker places ROM at `0xFF0000`, initialized data/BSS in
BSRAM, and relies on the RTL shadow to present those first eight bytes at zero.

ROM startup:

1. masks CPU interrupts at level 7;
2. writes exception handlers into the SDRAM vector table at physical zero;
3. copies initialized data from ROM to BSRAM;
4. initializes the polling UART;
5. clears BSS and initializes one global newlib reentrancy object;
6. calls the bootloader.

The installed handlers leave several vector ranges untouched, including
vectors that become important for later processor generations and FPU state.
All vector dispatch assumes VBR=0.

RAM programs use a smaller startup that clears BSS and calls `main`. They
inherit stack, vectors, device state and most CPU state from the bootloader.

## Firmware memory view

| Region | Software use |
|---|---|
| `000000-0003FF` | 256-entry vector table after shadow |
| `000400-79FFFF` | Kernel, RAM diagnostics and heap |
| `7A0000...` | Space reserved around appended Linux ROMfs/image |
| near `800000` | Descending bootloader stack |
| `FF0000-FFBFFF` | Bootloader code/rodata/init image |
| `FFC000-FFF7FF` | Bootloader data and BSS |
| `FFF800+` | MMIO |

The ROM linker calls BSRAM the bootloader's RAM, but the initial stack is in
SDRAM. Code loaded at `0x400` must not overwrite the live vector table.

## Image boot paths

### SD/FAT16

The bootloader initializes SD in SPI mode, reads a FAT16 boot sector at fixed
LBA 2048, searches the first 16 root entries for `IMAGE   .BIN`, loads it at
`0x400` and enters it with JSR. The appended ROMfs is expected inside the same
flat image.

The loader does not establish a formal kernel ABI: no new stack, CPU descriptor,
device tree, VBR, cache state or MMU state is passed. This must become a defined
boot contract before supporting multiple CPU profiles.

### UART/YMODEM

The receiver supports 128/1024-byte blocks and CRC16. Its advertised 8 MiB
buffer starts at `0x400`, allowing a maximum transfer to overrun physical RAM
by `0x400`. Interrupt state is not restored, and malformed/repeated transfers
have weak limits.

### W5500 netboot

Socket 0 receives `[big-endian u32 length][image bytes]` into `0x400`. Network
configuration is compiled in. Length is not bounded against RAM, and there is
no hash, signature, authentication or receive timeout.

## MMIO software contract

- UART uses even offsets with two-byte stride and 16550 semantics.
- SPI uses four-byte stride.
- Timer CTRL is `+0`; STATUS/ACK is `+2`.
- WS2812 G/R/B are `+0/+2/+4`.
- All drivers use raw volatile pointer accesses.

Timer is autovector level 6 and UART level 5. The timer ISR clears its pending
bit; the UART ISR drains RBR. Firmware defines an INTC base but does not use it.

## Runtime limitations

- Console and device drivers are polling and blocking except for diagnostics.
- newlib has one global `_reent`, unsuitable for concurrent threads.
- `_sbrk` does not enforce heap end or stack collision.
- `read()` returns EOF instead of console data.
- FAT16 is read-only, searches a small root subset and mishandles parts of the
  legal FAT16 EOC range.
- Packed FAT structures make strict 68000 alignment especially important.
- SD does not verify block CRC and does not use native multiblock transfers.

These are firmware quality issues, not CPU architectural blockers, but they
must not be mistaken for an OS-grade runtime.

## Current toolchain profiles

Bare metal uses `m68k-mackerel-elf-`, `-m68000`, soft-float, newlib and raw
binary output. ROM hex is one big-endian 16-bit word per line.

The Linux profile is deliberately:

- m68k/68000;
- NOMMU;
- binfmt FLAT with separate data;
- uClibc, no threads, no shared libraries;
- soft-float;
- strict alignment.

Local GCC and uClibc patches preserve strict 68000 alignment and prevent bFLT
startup from parsing a nonexistent ELF auxiliary vector.

No code currently configures VBR, control registers, caches, MMU or FPU.

## Required future build profiles

Keep independently reproducible profiles rather than silently changing the
meaning of the existing one:

| Profile | Intended use |
|---|---|
| `m68000-nommu-soft` | Current compatibility and differential baseline |
| `m68020-nommu-soft` | New ISA/addressing bring-up before virtual memory |
| `m68040-mmu-soft` | MMU/cache/kernel bring-up before hardware FPU |
| `m68040-mmu-hard` | Full FPU ABI and floating-point userspace |

The boot ROM may remain compiled for the 68000 common subset and detect/configure
the new CPU. Kernel/userspace should be explicit per profile.

## Software implications of MMU and multitasking

NOMMU Linux can schedule multiple tasks today; an MMU adds isolation, per-task
virtual address spaces, demand paging and conventional fork/COW semantics.
Hardware requirements include user/supervisor translations, precise page
faults, restart, accessed/modified state, TLB invalidation and safe context
switching of URP/SRP and related registers.

Each process can receive a 4 GiB virtual address space with a 32-bit MMU. The
shared physical address space is also 4 GiB total. RAM, ROM, MMIO and reserved
regions must all fit inside it.

## Software implications of FPU

Full 68040 compatibility needs eight 80-bit FP registers plus FPCR, FPSR and
FPIAR, user access, context-switch save/restore, rounding modes, status and
exceptions. The real 68040 implements a hardware subset and relies on a
software support package for other 68881/68882 operations. Supporting that
model is more accurate than claiming every transcendental instruction must be
hardwired in the first FPU milestone.

## Software implications of SMP

No local software supports secondary-core reset, CPU IDs, IPI, affinity,
per-CPU timers, TLB shootdown or coherent atomics. Hardware SMP therefore needs
a platform port as well as caches/interconnect. Support in the chosen Linux
m68k tree must be audited separately; it is not present in this repository.
