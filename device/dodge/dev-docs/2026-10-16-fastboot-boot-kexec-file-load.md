<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — stage 2 was running on stock's DTB: kexec_file_load

**Goal.** Find why stage 2 registers no USB device controller, with a
timing-coded probe that does reset. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 1 the chain-loader in `out-dodge-rdinit`. Stage 2 the
`out-dodge` image, `6.16.0` on `f71c365a8`, then `02a028467` (below).
**Result.** Found. kexec-tools 2.0.32 tries `kexec_file_load` first,
and on arm64 that call ignores `--dtb`: stage 2 inherited the running
FDT, which is stock's. Every chain boot before this one ran stage 2 on
stock's DTB. Stage 1 now passes `-c` (`kexec_load`).

## Corrections to 2026-10-15

- The two probes that never reset
  ([2026-10-15-fastboot-boot-kexec-probe.md](2026-10-15-fastboot-boot-kexec-probe.md),
  [probe2](2026-10-15-fastboot-boot-kexec-probe2.md)) had cpio
  archives with `init`, `bin/busybox` and `bin/sh` only. With no `/proc`
  directory, `mount -t proc` failed and every write to
  `/proc/sysrq-trigger` went nowhere; PID 1 slept forever. Statting USB
  sysfs was not the cause, and
  [2026-10-15-no-unattended-boot.md](2026-10-15-no-unattended-boot.md)'s
  rule against it is withdrawn.
- The `ramoops`, `fb`, `peripheral` and `hs` tries changed a DTB that
  stage 2 never used. They tested nothing about our devicetree.
- `CONFIG_SM_TCSRCC_8750` was `=m`. Both USB PHYs (and UFS) take their
  reference clock from `tcsrcc`, so with our DTB they would have
  deferred forever. The fragment now builds it in and `tools/dodge-try`
  requires it.

## What we did

`device/dodge/chainload/probe-init` is a stage 2 init whose cpio has
`/proc`, `/sys` and `/dev`. It waits 40 s, evaluates up to five tests
(path exists, `eq:` file value, `kmsg:` text in the log, `deferred:`
name), and holds `10 + 8 × v` s before `sysrq b`, with a panic at
320 s as backup. `tools/dodge-chain probe` packs it. On stock's DTB,
adb landed at `72 + 8 × v` s (±1 s). Every probe boot reset on its own.

| Boot (Booting OKAY) | Stage 2 | adb | v | Read |
| --- | --- | --- | --- | --- |
| 09:53:50 | `TCSRCC=y`, `peripheral`, dodge-try | 137 s | – | no UDC, as before |
| 09:58:29 | probe: tcsrcc, HS PHY, QMP PHY, glue, UDC bound | 71 s | 0 | nothing bound |
| 10:00:39 | probe: control, RSC, RPMh clk, GCC, rpmhpd | 80 s | 1 | only the control |
| 10:03:27 | probe: RSC deferred, `psci` bound, genpd, RSC device, GCC deferred | 135 s | 8 | RSC device exists, nothing else |
| 10:07:24 | `rscpd`, probe: RSC, RPMh clk, GCC, tcsrcc, UDC | 71 s | 0 | still nothing |
| 10:10:12 | probe: cmd-db debugfs, cmd-db device, RSC deferred, RSC waiting, `rpmh` driver | 207 s | 17 | cmd-db up, RSC neither deferred nor waiting |
| 10:15:21 | probe: `kmsg:` RSC probe errors | 127 s | 7 | `probe with driver rpmh failed with error -22` |
| 10:20:01 | RSC v4 commit and probe-site markers, probe | 71 s | 0 | no marker at all: fails before the TCS read |
| 10:22:17 | probe: `soc@0`, `soc`, our RSC's `qcom,drv-id`, marker, model | 87 s | 2 | `/soc` exists, `/soc@0` does not: **stock's DTB** |

The -22 was `of_property_read_u32(dn, "qcom,drv-id")`: stock's RSC node
keeps that property in a `drv@2` child. The `psci` and `*cmd-db*`
misses had the same cause (stock names them `soc:psci` and
`aop_cmd_db_region`). Under `qemu-aarch64-static -strace`, the Alpine
`kexec -l --dtb=…` issues syscall 294 (`kexec_file_load`) first.

Two of the `stage2-dtb.py` options added on the way stay for later use:
`rscpd` drops `power-domains` from the RSC, and `hs` drops the dwc3
`iommus` entry as well as the SuperSpeed PHY (do not use `hs` with
`ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT`). Neither is needed on our DTB.
The kernel keeps upstream `84684c57c9cd` ("soc: qcom: rpmh-rsc: Add
RSC version 4 support") as `02a028467`; this RSC reports 3.8, so it was
not the fix.

## Learning

When a tool can pick between two syscalls, pin the one whose semantics
we rely on, and give the first boot of any chain a probe that reads
back an identity (here `/sys/firmware/devicetree/base/soc@0` and the
`Machine model:` line) before reading anything else. A day of DTB
changes went to a DTB that was never loaded.
