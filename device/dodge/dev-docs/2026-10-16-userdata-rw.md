<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — only userdata is writable, and nothing is mounted

**Goal.** Phase 4's guard, before any format: with
`omamobile.userdata-rw`, open the one `userdata` partition and leave
every other disk read-only. A count other than one must not call
`setrw`.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** `6.16.0-g02a028467db0` #8, the same build as the allowlist
log. Only the ramdisk changed.
**Result.** Pass. `sda15` is writable. `/dev/sda` is gone. Every other
block device is read-only. Nothing is mounted, and nothing was
formatted.

## What we did

The init still forces every disk read-only first. After the partition
list settles, `omamobile.userdata-rw` calls `setrw` only when
`ufs_userdata_decision` prints `allow <one device>`. Any other count
logs STOP and returns without `setrw`. The parent disk is made
writable because the kernel will not write a partition whose disk is
read-only, and its device node is removed so nothing can write across
partitions. The guard loop keeps removing that node and does not close
the one allowed partition.

Image `out-dodge-rdinit/images/boot-chain.img`, sha256
`f24fb0dc3b287a90e8bcc564b8fb9381138fc629661a16583e24e79025cbb256`.
SSH at 27 s. `dmesg` is `logs/dodge-userdata-rw-20261016-130800.kmsg`
(not committed).

## What happened

```
omamobile: ufs-ro: allow sda15 (userdata) writable; /dev/sda node removed
```

`/sys/block/sda/sda15/ro` is 0. `/dev/sda` does not exist.
`/sys/block/sda/ro` is 0, which is the parent disk the partition write
needs. Every other `sd*` device, including `sda2` (`persist`),
`sdf10` (`modemst1`), `sdf11` (`modemst2`), `sdf12` (`fsg`) and
`sdf13` (`fsc`), reads `ro=1`. `/proc/mounts` has no `/dev/sd*`.
`soc@0` is present. There is no STOP line.

## Learning

The STOP path blocks `setrw`. This boot did not exercise a bad count
on the phone; the laptop test still does (zero and two). Formatting
`userdata` has not been started. The partition is writable in the
kernel only, and the next boot without `omamobile.userdata-rw` closes
it again.
