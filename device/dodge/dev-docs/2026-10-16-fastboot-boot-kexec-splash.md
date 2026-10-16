<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — splash reservation quiets the SMMU storm

**Goal.** One stage 2 devicetree change: reserve ABL's splash buffer and
ask the SMMU for a one-to-one map of it on `mdss` (SID 0x800).
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** Stage 1 chain-loader with `kexec -c`. Stage 2 the dodge
image and `dodge-try` initramfs. `CONFIG_SM_TCSRCC_8750=y`.
**Result.** SSH at 28 s. `soc@0` is present. The fault storm stopped.
The direct map itself was refused.

## What we did

`stage2-dtb.py splash` adds `splash@fc800000`
(`reg = <0x00 0xfc800000 0x00 0x2b00000>`, `no-map`) and
`iommu-addresses` aimed at `mdss`, and sets `memory-region` on the
mdss node. Image `out-dodge-rdinit/images/boot-v4-kexec-splash.img`,
sha256
`0d5e1a7e16901dad45d801276e93fceedb099b9045c4bad0d11fc1aa8a767355`.
`Booting OKAY` at 10:48:12.

## What happened

SSH at 28 s. `/sys/firmware/devicetree/base` contains `soc@0`.
`dmesg` is `logs/dodge-splash-20261016-104849.kmsg` (not committed).

The reservation is there:
`OF: reserved mem: 0xfc800000..0xff2fffff (44032 KiB) nomap splash@fc800000`.
Then:
`IOMMU driver was not able to establish FW requested direct mapping.`
Four `Unhandled context fault` lines at 0.130 s, SID 0x800, IOVAs
`0xfd92xxxx`–`0xfd95xxxx` (inside the splash). At uptime 38 s the count
is still 4, and there is no "callbacks suppressed" line. The earlier
boot filled the log from about 20 s and suppressed 90263 callbacks.

## Learning

The warning is the first mapping attempt, which arm-smmu cannot do
before the domain is attached. The core retries after attach. On the
live session the display group's reserved region is
`0xfc800000-0xff2fffff direct`. The map is installed. The four faults
are the gap before that retry. At uptime 268 s the fault count was
still 4.
