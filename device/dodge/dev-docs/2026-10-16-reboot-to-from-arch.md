<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — reboot-to from Arch enters fastboot

**Goal.** From the Arch root, run the ramdisk `reboot-to bootloader`
syscall and see if fastboot answers. No flash.
**Phone.** Arch Linux ARM on `/dev/sda15`. Kernel
`6.16.0-gb3ee311dab85`.
**Result.** Fastboot in a few seconds (`product: sun`, slot `a`).
The same chain image then returned to Arch.

## What we did

The static `reboot-to` from `device/dodge/initramfs/reboot-to.c` was
copied to `/usr/local/bin/reboot-to` on the Arch root and run as
`reboot-to bootloader`. USB dropped, and fastboot enumerated. Then
`fastboot boot` of
`out-dodge-chain/images/boot-chain.img` (sha256
`fe1334e569a58a28281325d1658a7ac1185aa92aed870970d844e307a3b57538`).

## What happened

Fastboot was real: `getvar product` returned `sun` and the slot was
`a`. No adb. After the chain boot, the first SSH answer was Alpine
(dropbear, before `switch_root`) and the next was Arch Linux ARM.
`/` is `/dev/sda15`, 452.7 GiB. No failed units. `soc@0` is present.
`/usr/local/bin/reboot-to` is still on the root.

## Learning

The reboot-reason path works from Arch userspace when the syscall is
`LINUX_REBOOT_CMD_RESTART2` with the string `bootloader`. The earlier
failure was Arch's `reboot bootloader`, which started the flashed
`boot_a` and the OxygenOS setup wizard. The screen during that
fastboot was the bootloader, not the frozen ABL frame: the cable was
`18d1` fastboot until `fastboot boot`.
