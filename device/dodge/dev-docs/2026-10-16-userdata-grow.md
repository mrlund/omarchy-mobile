<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — userdata grown, UFS quiet

**Goal.** On the running Arch root, grow the 2880 MiB file system to
the partition, and read back the UFS link. No reboot, no flash.
**Phone.** Arch Linux ARM on `/dev/sda15`. Kernel
`6.16.0-gb3ee311dab85` #8.
**Result.** The file system is 453 GiB. No `ufshcd` error lines.

## What we did

`resize2fs /dev/sda15` while it was mounted on `/`. Then read
`reference_clock_frequency` and the `ufshcd` log.

## What happened

`resize2fs` reported the file system is now 120554767 blocks of 4 KiB,
which is the whole partition (`493792325632` bytes). `df` shows 453G,
1.9G used. Reserved GDT blocks were 359, so the grow fit.

`ufshcd-qcom 1d84000.ufs` still warns about a missing `freq-table-hz`,
missing `vdd-hba-supply` and `vccq2-supply`, a missing `ufs_mem`
resource, and MCQ disabled. `reference_clock_frequency` reads `0x2`
(the UFS code for 38.4 MHz). `dmesg` has no `ufshcd` error line.
`systemctl --failed` was empty before the grow. Every partition other
than `sda15` was still read-only, and `/dev/sda` was still absent.

## Learning

The root can use the rest of `userdata`. The UFS link that carried
the image write and this grow did not log an error. `boot_a` is still
not flashed. The chain image that actually switches to Arch is
`out-dodge-chain/images/boot-chain.img` (sha256 `fe1334e5…`), not the
older file under `out-dodge-rdinit`.
