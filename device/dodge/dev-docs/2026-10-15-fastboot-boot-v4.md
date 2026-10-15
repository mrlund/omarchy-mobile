<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — header v4 kernel-only fastboot boot

**Goal.** One change from the stock `boot.img` that ABL does start:
replace the kernel with ours. Header version 4, ramdisk size 0, no
cmdline, no DTB in the boot image. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** The same `Image` as the header v2 tries, built 2026-10-15
15:37 from `sm8750-mainline` `v6.16` (`16cf517b2781`) plus the board-id
commit `f71c365a8`. The DTB is not inside this image.
**Result.** ABL left fastboot. OxygenOS was back in about 23 s. No SSH.
pstore was empty.

## What we did

`mkbootimg --header_version 4 --kernel Image` wrote
`~/android/mainline/out-dodge/images/boot-v4-kernel.img`, 40382464
bytes, sha256
`52d4638e69809b44fb3c752d991b8e7b8f55cee8af2f9f3f14b4238b218d2263`.
`unpack_bootimg`: header 4, kernel 40376832, ramdisk 0, cmdline empty,
signature 0. `adb reboot bootloader`, slot `a`, product `sun`, then
`fastboot boot`.

## What happened

`Sending` and `Booting` both returned `OKAY` in 1.3 s. USB was already
gone on the first check. There was no `18d1:d00d` and no SSH. At 23 s
adb was back as `22d9:2769`. OxygenOS: slot `_a`, display id
`CPH2653_16.0.10.501(EX01)`, `ro.boot.flash.locked=0`, `magiskd`
running, uptime 31 s. `/sys/fs/pstore` was empty. `boot_a` was not
read again; the stock try already showed `fastboot boot` does not
write it.

## The three tries

| Image | Header | What else it carried | What ABL did |
| --- | --- | --- | --- |
| OTA `boot.img` | 4 | stock kernel, ramdisk 0 | OxygenOS booted. `boot_a` unchanged. Next cold boot normal. |
| `images/boot.img` | 2 | our kernel, our ramdisk, dodge DTB with no ids, cmdline `clk_ignore_unused pd_ignore_unused panic=10 console=tty0` | `Booting OKAY`, stayed on `18d1:d00d`. Screen: OnePlus logo and "fastboot mode". |
| `images/boot-ids.img` | 2 | same, DTB with all eight msm-id pairs and board-id `0x40008` | Same. Stayed in fastboot 60 s. |
| `images/boot-v4-kernel.img` | 4 | our kernel only | Left fastboot at once. OxygenOS back, empty pstore, no SSH. |

Stock geometry used for the v2 images, from the OTA `vendor_boot`:
page 4096, kernel offset `0x8000`, ramdisk `0x01000000`, tags `0x100`,
dtb `0x01f00000`, `--base 0`. Live FDT: model "Qualcomm Technologies,
Inc. Sun MTP,dodge", `qcom,board-id` `<0x40008 0x00>`, `qcom,msm-id`
eight sun/sunp pairs in the order recorded in
[2026-10-15-rooted-on.md](2026-10-15-rooted-on.md). Slot B is
unbootable. `version-bootloader` is empty. No `vendor_kernel_boot`.
`recovery_a` and `recovery_b` exist.

## Learning

Header v2, with or without the live ids, never leaves fastboot.
Header v4 with our kernel does leave fastboot, and the slot's
OxygenOS is what comes back. A v4 `fastboot boot` is not a test of our
DTB or our initramfs: ABL uses the flashed `init_boot` and
`vendor_boot` for those (PLAN.md §5.3). Magisk's ramdisk and stock's
DTB are what this kernel would have had if ABL entered it. Nothing in
pstore shows that it did.

Flashing `vendor_boot` is still a separate decision. It was not done.
