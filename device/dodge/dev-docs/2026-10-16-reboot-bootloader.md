<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — reboot-to bootloader lands in fastboot

**Goal.** Phase 3.5 gate 1: from stage 2, reboot into fastboot with no
OxygenOS boot. Nothing flashed.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** `6.16.0-g02a028467db0` #7, built 2026-10-16 12:13 CEST.
`DTB_OPTS='splash fb'`.
**Result.** Pass. `reboot-to bootloader` answered as fastboot
(`product: sun`, `current-slot: a`) about 12 s later. adb did not
come up.

## What we did

Built in `NVMEM_SPMI_SDAM`, `NVMEM_REBOOT_MODE` and
`POWER_RESET_QCOM_PON`. The ramdisk gained `reboot-to`, the same
`LINUX_REBOOT_CMD_RESTART2` call as cheetah's, built without a libc.
The third boot also carries a one-line change in
`nvmem-reboot-mode`: write the cell's own length, not
`sizeof(unsigned int)`.

Image `out-dodge-rdinit/images/boot-chain.img`, sha256
`5e5d1748f4afa85178ffdc634a414d19ede1af2928b2598fbbdfd1524e62b8d1`.
`dmesg` from the first of these boots is
`logs/dodge-reboot-mode-20261016-120700.kmsg` (not committed).

## What happened

| Try | Kernel | What we sent | Where it came back |
| --- | --- | --- | --- |
| 1 | #6 | `reboot-to bootloader` | OxygenOS, adb, about 60 s. The helper read argv after its C prologue, so the reason was garbage. |
| 2 | #6, helper fixed | the same | OxygenOS, adb, about 15 s. The driver wrote 4 bytes into a 1-byte cell, the write was rejected, and ABL saw a normal reset. |
| 3 | #7 | the same | Fastboot at about 12 s. `product: sun`, slot `a`. No adb. |

On try 3, before the reboot, `nvmem-reboot-mode`, `qcom,spmi-sdam` and
`pm8916-pon` were bound, and `soc@0` was present.

## Learning

The reason byte is `reboot-reason@48` in pmk8550's SDAM, with
`bits = <1 7>` and `mode-bootloader = <0x02>`. The 6.16
`nvmem-reboot-mode` driver writes `sizeof(unsigned int)` and that
cell refuses it. The reboot still happens. ABL then starts OxygenOS.

Busybox cannot pass the reason, and a C `_start` must be `naked` or
it reads the wrong stack slot. The PON driver does not clear the
reason: with no `mode-*` properties its magic is 0 and it does not
write.

The phone was left in fastboot. Gate 2 is the button drill, and that
one needs the human.
