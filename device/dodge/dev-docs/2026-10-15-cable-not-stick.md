<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — the cable is the loop, not a USB stick

**Goal.** Decide how a kernel built on this machine reaches the phone.
**Phone.** Not attached. CPH2653, as in the plan.
**Kernel.** None of ours.
**Result.** One USB-C cable. `fastboot boot` while the bootloader owns
the bus, SSH to `172.16.42.1` once the gadget is up. No stick, no hub.

## What we had written

The OSS survey copied Daniel Abrecht's desktop boot: `fastboot boot` of
Mu-Silicium, then a kernel loaded from a USB stick on a powered hub. That
is a real thing he did on a CPH2653, in November 2025, without flashing.

## Why that stick was in his setup

Mu-Silicium on dodge does not run as a USB host that can power a disk.
He patched host mode into a UEFI image he *temporarily* booted, and the
hub supplied VBUS. He did that because packing `sm8750-mainline` as an
Android `boot.img` and running `fastboot boot boot.img` hung. The stick
was a second computer to boot from, after the phone had stopped being a
USB device.

## Why we will not start there

The phone will be plugged into this machine the whole time. That cable
already does both jobs:

- While the bootloader is running, `fastboot boot` uploads the image we
  just built. The ramdisk inside that image is the early rootfs. There
  is nowhere a stick would sit.
- When the kernel brings up the DWC3 gadget, the same cable becomes a
  network interface and `tools/phone-ssh` talks to `172.16.42.1`. The
  postmarketOS dodge page already lists USB networking as working for
  someone else's kernel.

A hung `fastboot boot` is cleared from the laptop with `fastboot reboot`,
which he also did. If our image hangs before it can print, the next try
is a different image over the same cable, including `fastboot boot` of
Mu-Silicium as a known console. Turning the phone around into a USB host
is a new pile of hardware for a problem we have not hit yet.

## Learning

`device/dodge/PLAN.md` §5 is the cable loop. The stick remains a note in
the OSS survey, as what one person did when his boot image hung, not as
a step we own.
