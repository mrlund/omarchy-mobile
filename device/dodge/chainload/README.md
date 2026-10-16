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
not), plus `ramoops`, `splash`, `fb`, or `peripheral` if asked. `peripheral` sets
the dwc3 node to `dr_mode = "peripheral"` and drops `usb-role-switch`.

```sh
tools/dodge-try chain                   # pack stage 2, then dodge-chain boot
# or, with the phone already in fastboot:
tools/dodge-try pack                    # stage 2: Image, DTB, initramfs in out-dodge
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

SSH works, including through `tools/dodge-try chain`. The 2026-10-15
handoff is superseded: its USB theories were tested against stock's DTB
(see the file-load dev-doc).

1. Splash reservation: done
   ([../dev-docs/2026-10-16-fastboot-boot-kexec-splash.md](../dev-docs/2026-10-16-fastboot-boot-kexec-splash.md),
   confirmed again by
   [../dev-docs/2026-10-16-dodge-try-chain.md](../dev-docs/2026-10-16-dodge-try-chain.md)).
   SID 0x800 is `mdss`. Reserving `0xfc800000` and requesting the
   identity map stopped the storm. The "could not establish direct
   mapping" line is the attempt before the domain is attached. After
   attach, group 5's reserved region is `0xfc800000-0xff2fffff direct`.
   The faults in the gap before that retry were 4 on the first splash
   boot and 10 on the chain rebuild, all at 0.130 s, and then none.

2. `tools/dodge-try chain` is the one command
   ([../dev-docs/2026-10-16-dodge-try-chain.md](../dev-docs/2026-10-16-dodge-try-chain.md)).
   It packs stage 2, returns a live SSH or OxygenOS session to fastboot,
   and boots the chain. Defaults: `DTB_OPTS=splash`,
   `CHAIN_OUT=~/android/mainline/out-dodge-rdinit`. SSH at 27 s,
   `soc@0` present. Do not pass `DTB_OPTS=hs`: that option drops the
   dwc3 `iommus` entry.

3. UFS read-only probe: done
   ([../dev-docs/2026-10-16-ufs-probe.md](../dev-docs/2026-10-16-ufs-probe.md)).
   `SCSI_UFS_QCOM` and `PHY_QCOM_QMP_UFS` are built in. With
   `omamobile.ufs-probe` on the stage 2 cmdline the init listed six
   disks and 139 partitions, set every one read-only, and mounted
   nothing. `modemst1`, `modemst2`, `fsg` and `fsc` are on `sdf`.

4. Framebuffer console, kernel side: done
   ([../dev-docs/2026-10-16-framebuffer.md](../dev-docs/2026-10-16-framebuffer.md)).
   `DTB_OPTS='splash fb'` binds `simpledrm` on the splash buffer.
   The panel shows a row of Tux logos and the 180×198 kernel log.
   Phase 3's pass line is met. A flash is phase 4 and waits for an
   explicit yes.

5. Phase 3.5 in [../PLAN.md](../PLAN.md). Gate 1 is met:
   `reboot-to bootloader` from stage 2 lands in fastboot
   ([../dev-docs/2026-10-16-reboot-bootloader.md](../dev-docs/2026-10-16-reboot-bootloader.md)).
   Gate 2 is met: Volume Down held through power-off, then Power,
   reaches fastboot
   ([../dev-docs/2026-10-16-fastboot-buttons.md](../dev-docs/2026-10-16-fastboot-buttons.md)).
   Gate 3 is met: `would allow sda15 (userdata)`, every disk
   read-only
   ([../dev-docs/2026-10-16-userdata-allowlist.md](../dev-docs/2026-10-16-userdata-allowlist.md)).
   Phase 3.5 is met. With `omamobile.userdata-rw`, only `sda15` is
   writable and nothing is mounted
   ([../dev-docs/2026-10-16-userdata-rw.md](../dev-docs/2026-10-16-userdata-rw.md)).
   Base Arch Linux ARM is now `/` on `sda15`, reached by `fastboot
   boot`, not flashed
   ([../dev-docs/2026-10-16-arch-userdata.md](../dev-docs/2026-10-16-arch-userdata.md)).
   Rebuild the stage 2 initramfs with `tools/dodge-try pack` before
   `tools/dodge-chain pack` when the init changes. ramoops, the
   watchdog and UFS
   load checks run alongside phase 4. Nothing is flashed.

`tools/dodge-chain boot` now saves `dmesg` to `logs/` and checks
`soc@0` as soon as SSH answers.

Working notes:

- `tools/dodge-try chain` uses `CHAIN_OUT=~/android/mainline/out-dodge-rdinit`.
  A fresh `out-dodge-chain` builds a whole kernel first.
- Before trusting a DTB change, confirm stage 2 runs it:
  `ssh root@172.16.42.1 'ls /sys/firmware/devicetree/base'` must show
  `soc@0`.
- Back to OxygenOS from an SSH session:
  `ssh root@172.16.42.1 'echo b > /proc/sysrq-trigger'`. OxygenOS
  answers on adb about 15 s later. `tools/dodge-try chain` does that
  reboot itself when a session is already up.
- Save `dmesg` into `logs/` right after SSH comes up. A fault storm can
  push the boot lines out of the log buffer.
