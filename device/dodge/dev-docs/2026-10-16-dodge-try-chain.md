<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — dodge-try chain boots in one command

**Goal.** `tools/dodge-try chain` packs stage 2 and `fastboot boot`s the
kexec chain, with the splash reservation, and nothing flashed.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** `6.16.0-g02a028467db0` #4, built 2026-10-16 10:54 CEST.
Stage 1 `kexec -c`. `CONFIG_SM_TCSRCC_8750=y`. `DTB_OPTS=splash`.
**Result.** SSH at 27 s. `soc@0` is present. The splash identity map is
installed. Ten early SMMU faults, then silence.

## What we did

`tools/dodge-try chain` with the defaults
(`DTB_OPTS=splash`, `CHAIN_OUT=~/android/mainline/out-dodge-rdinit`).
It rebuilt stage 2, sysrq-rebooted the splash SSH session, waited for
OxygenOS adb, and `adb reboot bootloader`. Then `tools/dodge-chain boot`.

Image `out-dodge-rdinit/images/boot-chain.img`, sha256
`b066b46a693ef5a8491a3dc93a28e710639daa5f2d88d0d3ac301e2c9e4ba5a3`.
`Booting OKAY` at 10:56:09. `dmesg` is
`logs/dodge-chain-20261016-105609.kmsg` (not committed).

## What happened

The gadget enumerated at 27 s (`1d6b:0104`). SSH answered.
`/sys/firmware/devicetree/base` contains `soc@0` (`simple-bus`).
The model is `OnePlus 13`. UDC `a600000.usb` is `configured`.
`/proc/partitions` is empty: the UFS host is still a module.

The splash reservation is in the log:
`OF: reserved mem: 0xfc800000..0xff2fffff (44032 KiB) nomap splash@fc800000`.
The same warning as the first splash boot is there, at 0.129 s:
`IOMMU driver was not able to establish FW requested direct mapping.`
Group 5 is `ae00000.display-subsystem`, type DMA, and its
`reserved_regions` includes `0xfc800000 0xff2fffff direct`.

Ten `Unhandled context fault` lines, all at 0.130 s, SID 0x800, IOVAs
`0xfc862a00` through `0xfc8e8000` (inside the splash). No
"callbacks suppressed" line. At uptime 88 s the count was still 10.
The read-only guard logged `ufs-ro: guard running, no writable partitions`.

## Learning

`tools/dodge-try chain` is the loop. The direct-map warning is the
attempt before the SMMU domain is attached; the retry installs the
region. The fault count in that gap is not fixed (4 on the first splash
boot, 10 on this rebuild). The storm stays stopped.

Next boot: build `SCSI_UFS_QCOM` and `PHY_QCOM_QMP_UFS` in, and add
`omamobile.ufs-probe` to the stage 2 cmdline. The init already forces
every disk read-only and the probe only prints `PARTNAME`. It does not
mount. PLAN.md phase 3.
