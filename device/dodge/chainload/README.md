<!-- SPDX-License-Identifier: MIT -->
# dodge kexec chain-loader

How we start our own kernel, DTB and initramfs on the OnePlus 13 with
one `fastboot boot` and no flash. The why is in
[../PLAN.md](../PLAN.md) §5.3 and the dev-docs of 2026-10-15.

## How it boots

1. ABL starts a kernel-only header v4 `boot.img` (it refuses header v2,
   and it ignores a ramdisk in the uploaded v4 image). It hands that
   kernel stock's DTB from the flashed `vendor_boot` and unpacks
   `vendor_boot`'s and Magisk's `init_boot` ramdisks.
2. Stage 1 is our kernel with `CONFIG_CMDLINE_FORCE`
   `rdinit=/omamobile/init panic=10` and a built-in initramfs. The
   kernel unpacks the built-in one first and ABL's over it, so
   everything of ours lives under `/omamobile/`.
3. [init](init) runs `kexec -c -l --dtb` and `kexec -e`. `-c` forces
   `kexec_load`: kexec-tools 2.0.32 otherwise tries `kexec_file_load`
   first, which on arm64 ignores `--dtb` and hands stage 2 stock's FDT.
   Until 2026-10-16 every stage 2 ran on stock's DTB because of this.
4. Stage 2 is our kernel on our DTB with our initramfs, by default
   `tools/dodge-try`'s.

[stage2-dtb.py](stage2-dtb.py) makes stage 2's DTB: the dodge DTB with
the phone's own memory map in `memory` (ABL fills that node, kexec does
not), plus `ramoops`, `fb`, or `peripheral` if asked. `peripheral` sets
the dwc3 node to `dr_mode = "peripheral"` and drops `usb-role-switch`.

```sh
tools/dodge-try pack                    # stage 2: Image, DTB, initramfs in out-dodge
tools/dodge-chain pack                  # out-dodge-chain/images/boot-chain.img
# phone in fastboot, human's go:
tools/dodge-chain boot                  # pack, fastboot boot, timeline
```

With the default stage 2 this ends in SSH at about 27 s
([../dev-docs/2026-10-16-fastboot-boot-kexec-ssh-up.md](../dev-docs/2026-10-16-fastboot-boot-kexec-ssh-up.md)).

Variables: `STAGE2_INITRD`, `STAGE2_CMDLINE`, `DTB_OPTS`, `CHAIN_OUT`,
`LIVE_DTB` (the rooted capture's live FDT, never committed). The first
`pack` in a fresh `CHAIN_OUT` builds a whole kernel.

## Reading the result without SSH

When SSH does not come up, the time from `Booting OKAY` to adb says
where it stopped. OxygenOS takes about 13 s from a reset to adb.
Measured on 2026-10-15 (stage 2 then ran on stock's DTB; on our DTB
stage 2 reaches its init a few seconds later):

| adb after `Booting OKAY` | Meaning |
| --- | --- |
| stays in fastboot | ABL refused the image (header v2, or something new) |
| about 12 s | ABL ran the stock kernel or ignored ours |
| about 23 s | our kernel started without our init and panicked |
| about 35 s | stage 2 panicked before its init |
| 63 / 82 / 108 s | a stage 1 or 2 hold of 45 / 60 / 90 s ran out (tries passed) |
| about 108 s | dodge-try init: a UDC bound, the host never configured it |
| **136-137 s** | dodge-try init: **no UDC in 30 s**, its panic fallback (seen 3 times) |
| about 218 s | stage 1: `kexec -e` returned |
| about 248 s | stage 1: `kexec -l` failed |
| never | a hang without panic: the human holds Power about 30 s |

A new stage 2 init must keep its own bands clear of these, and its
cpio must carry `/proc`, `/sys` and `/dev`, or its reset never happens.

For more than one fact per boot, [probe-init](probe-init) is a stage 2
init that encodes up to five yes/no tests in its hold time (adb near
`72 + 8 × v` s on stock's DTB; calibrate on ours with a known bit).
`PROBE_PATHS=file tools/dodge-chain probe` packs it, then boot with
`STAGE2_INITRD=$CHAIN_OUT/probe.cpio`. Put an identity test first
(`/sys/firmware/devicetree/base/soc@0`).

## Next steps (2026-10-16)

SSH works. The 2026-10-15 handoff is superseded: its USB theories were
tested against stock's DTB (see the file-load dev-doc).

1. The splash reservation is in
   [../dev-docs/2026-10-16-fastboot-boot-kexec-splash.md](../dev-docs/2026-10-16-fastboot-boot-kexec-splash.md).
   SID 0x800 is `mdss` (`iommus = <&apps_smmu 0x800 0x2>`). Reserving
   `0xfc800000` and requesting the identity map stopped the storm (4
   faults at 0.130 s, none after). The kernel still says it could not
   establish that direct mapping. Next change: why
   `iommu_create_device_direct_mappings()` failed. SSH on that boot is
   still up.

Working notes for these steps:

- Use `CHAIN_OUT=~/android/mainline/out-dodge-rdinit`. That build is
  current. The default `out-dodge-chain` builds a whole kernel first.
- Order: `tools/dodge-try pack` (stage 2), then `tools/dodge-chain boot`.
  Before trusting a DTB change, confirm stage 2 runs it:
  `ssh root@172.16.42.1 'ls /sys/firmware/devicetree/base'` must show
  `soc@0`.
- Back to OxygenOS from an SSH session:
  `ssh root@172.16.42.1 'echo b > /proc/sysrq-trigger'`. OxygenOS
  answers on adb about 15 s later. Then `adb reboot bootloader` for the
  next try.
- Save `dmesg` into `logs/` right after SSH comes up. The fault storm
  can push the boot lines out of the 128 KiB log buffer.
2. Let `tools/dodge-try` build and boot the chain image, so phase 3's
   loop is one command, and add `rscpd`/`hs` to its docs only if needed.
3. Phase 3's storage step: UFS with the read-only guard (PLAN.md).
