<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — second fastboot boot returns to Arch

**Goal.** Boot the same chain image again and see if Arch on `sda15`
comes back. No flash.
**Kernel.** `6.16.0-gb3ee311dab85` #8. Image
`out-dodge-chain/images/boot-chain.img`, sha256
`fe1334e569a58a28281325d1658a7ac1185aa92aed870970d844e307a3b57538`.
**Result.** Arch is back. The file system was not replaced. `reboot
bootloader` from Arch did not enter fastboot.

## What we did

From the running Arch root, `reboot bootloader`. USB dropped at
13:49:27 and nothing enumerated. The screen came up as the OxygenOS
setup wizard, a language list with Chinese entries first. Reseating
the cable did not enumerate USB. The button path did: both volume
keys and Power to power off, then Volume Down held and Power added.
Fastboot answered (`product: sun`, slot `a`). `fastboot boot` of the
same chain image.

## What happened

The first SSH answer was still the ramdisk. A few seconds later the
root was Arch Linux ARM. The kernel log has the same file system
UUID as the image written earlier (`871df2bd-1596-46b1-b53b-b998bea95ddc`),
then `switching to Arch Linux on /dev/sda15`.

`/` is `/dev/sda15` ext4, 452.7 GiB. No failed units. `/dev/sda` is
absent. Every other partition is read-only. `soc@0` is present.

## Learning

Two `fastboot boot`s of this image have reached this Arch root, and
the OxygenOS setup screen in between did not replace it. `reboot
bootloader` from Arch's systemd did not land in fastboot; it started
the flashed `boot_a`. The ramdisk's `reboot-to bootloader` is the
path that has entered fastboot. Dropbear answers before `switch_root`,
so the first SSH of a boot can still be Alpine.
