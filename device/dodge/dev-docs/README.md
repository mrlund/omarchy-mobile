<!-- SPDX-License-Identifier: MIT -->
# dodge lab notes

Running log for the OnePlus 13 port. The plan is
[../PLAN.md](../PLAN.md). This directory is for attempts: what we tried,
what the phone did, and what we learned, including the tries that failed.

A fact that later boots will trip over gets promoted into
`device/dodge/NOTES.md` (newest first, same as cheetah) or into a
subsystem plan. A safety rule does not live only here.

## How to add an entry

One file per attempt or session:

```
YYYY-MM-DD-short-slug.md
```

Use the day the attempt happened. If a day has two, add a suffix
(`-2`, or a more specific slug). Start the file with:

```markdown
<!-- SPDX-License-Identifier: MIT -->
# YYYY-MM-DD — title

**Goal.** One or two sentences.
**Phone.** Model and build id if we already know them. No serial, IMEI or MAC.
**Kernel.** `uname -r`, or "no kernel of ours" if we had not booted one.
**Result.** Pass, fail, or stopped. One sentence.
```

Then three sections:

- **What we did.** The commands and the order. Quote the lines that
  matter. Leave out `getprop` dumps, partition images and anything that
  identifies the phone.
- **What happened.** Include the failure mode. "It hung" is less useful
  than the last kmsg line that made it to the laptop.
- **Learning.** What the next attempt will do differently. Name the plan
  section this confirms or contradicts.

Add a row to the index below in the same change. Keep the newest row at
the top.

Do not put captures here. They go in `~/android/reference/dodge-cph2653/`
and stay out of git.

## Index

| Date | Entry | Result |
| --- | --- | --- |
| 2026-10-15 | [fastboot-boot-kexec-fb](2026-10-15-fastboot-boot-kexec-fb.md) | simple-framebuffer on ABL's splash buffer. Command-mode panel did not change; 136 s, no USB. |
| 2026-10-15 | [fastboot-boot-kexec-ramoops](2026-10-15-fastboot-boot-kexec-ramoops.md) | Stage 2 ramoops at OxygenOS's 0x880000000. Same no-USB boot (136 s); OxygenOS pstore empty. |
| 2026-10-15 | [fastboot-boot-kexec-ssh](2026-10-15-fastboot-boot-kexec-ssh.md) | kexec into the dodge-try initramfs. No USB; back at 137 s, the no-UDC panic path. |
| 2026-10-15 | [fastboot-boot-kexec](2026-10-15-fastboot-boot-kexec.md) | Built-in init kexecs our kernel with our DTB. Stage 2 held 60 s; OxygenOS back at 82 s. Self-contained boot, no flash. |
| 2026-10-15 | [fastboot-boot-rdinit](2026-10-15-fastboot-boot-rdinit.md) | Our kernel, built-in `/omamobile/init`, forced `rdinit=`. Holds of 90 s and 45 s: OxygenOS back at 108 s and 63 s. Our userspace ran on the stock DTB. |
| 2026-10-15 | [fastboot-boot-v4-ramdisk](2026-10-15-fastboot-boot-v4-ramdisk.md) | Header v4, stock kernel and our ramdisk. OxygenOS with Magisk in 12 s; our `/init` did not run. |
| 2026-10-15 | [fastboot-boot-sink](2026-10-15-fastboot-boot-sink.md) | v2, DTB takes every stock `dtbo` entry. Still stayed in fastboot for 63 s. |
| 2026-10-15 | [fastboot-boot-v2-stock](2026-10-15-fastboot-boot-v2-stock.md) | Header v2 of stock kernel, stock ramdisk, and the live DTB stayed in fastboot. v2 does not start. |
| 2026-10-15 | [fastboot-boot-v4](2026-10-15-fastboot-boot-v4.md) | Header v4, our kernel only. ABL left fastboot. OxygenOS back, empty pstore, no SSH. |
| 2026-10-15 | [fastboot-boot-ids](2026-10-15-fastboot-boot-ids.md) | Ids added. ABL still stayed in fastboot for 60 s. OxygenOS restored. |
| 2026-10-15 | [fastboot-boot-mainline](2026-10-15-fastboot-boot-mainline.md) | Packed v2 image: ABL said Booting OKAY and stayed in fastboot. Screen showed the OnePlus logo and "fastboot mode". Returned to OxygenOS. |
| 2026-10-15 | [fastboot-boot-stock](2026-10-15-fastboot-boot-stock.md) | `fastboot boot` of stock `boot.img` was temporary. `boot_a` unchanged. Next cold boot normal. |
| 2026-10-15 | [boot-timing](2026-10-15-boot-timing.md) | OxygenOS reboot reached boot_completed in 26 s. Fastboot enumerated in 13 s without reseating. |
| 2026-10-15 | [debugfs-off](2026-10-15-debugfs-off.md) | Same four files with the screen off. Regulator summary identical to the awake copy. |
| 2026-10-15 | [debugfs](2026-10-15-debugfs.md) | debugfs mounted, four summaries saved with the screen awake, then unmounted. |
| 2026-10-15 | [rooted-off](2026-10-15-rooted-off.md) | Screen-off capture saved. Debugfs still not mounted. |
| 2026-10-15 | [rooted-on](2026-10-15-rooted-on.md) | Screen-on capture. Live DTB model is Sun MTP,dodge. Board-id `0x40008`. All eight msm-id pairs. Debugfs not mounted. |
| 2026-10-15 | [magisk-install](2026-10-15-magisk-install.md) | Patched `init_boot` flashed to `init_boot_a`. OxygenOS booted. `magiskd` is running. |
| 2026-10-15 | [unlock](2026-10-15-unlock.md) | Second `fastboot flashing unlock` returned OKAY. Phone rebooted to the OxygenOS welcome slide. |
| 2026-10-15 | [unlock-refused](2026-10-15-unlock-refused.md) | `fastboot flashing unlock` refused. Still locked. Rebooted to OxygenOS. |
| 2026-10-15 | [getvar](2026-10-15-getvar.md) | Fastboot read. Locked, slot A, slot B unbootable. `recovery` is a real partition. Unlock not sent. |
| 2026-10-15 | [magisk-capture](2026-10-15-magisk-capture.md) | Magisk 30.7 downloaded. `capture` can use `su -c`. APK not installed. Phone untouched. |
| 2026-10-15 | [dodge-try](2026-10-15-dodge-try.md) | Header v2 image packed on the laptop. Watchdog feeder cannot reset this DTB. Phone not booted. |
| 2026-10-15 | [mainline-dtb](2026-10-15-mainline-dtb.md) | `sm8750-oneplus-dodge.dtb` builds. No msm-id, board-id or watchdog. USB at `0xa600000` is enabled. Phone untouched. |
| 2026-10-15 | [ota-boot-images](2026-10-15-ota-boot-images.md) | EU full OTA for `CPH2653_16.0.10.501(EX01)` unpacked. Geometry, ids, panel list, Wi-Fi node, splash and ramoops recorded. Phone untouched. |
| 2026-10-15 | [second-review](2026-10-15-second-review.md) | Outside review: self-contained v2 image, full OTA, an armed watchdog, Magisk fallback, stale notes marked. |
| 2026-10-15 | [rooted-capture](2026-10-15-rooted-capture.md) | No downstream-kernel track. Phase 1 roots OxygenOS with Magisk for a live capture. |
| 2026-10-15 | [plan-review](2026-10-15-plan-review.md) | Way back after a kernel hang, OTA as stock-image source, slot rules, host setup. Plan revised. |
| 2026-10-15 | [cable-not-stick](2026-10-15-cable-not-stick.md) | Loop is one USB cable: `fastboot boot`, then SSH. No stick. |
| 2026-10-15 | [oss-landscape](2026-10-15-oss-landscape.md) | Survey of other dodge firmware. Stick path superseded the same day. |
| 2026-10-15 | [assessment-review](2026-10-15-assessment-review.md) | First plan. Goal superseded the same day. |
