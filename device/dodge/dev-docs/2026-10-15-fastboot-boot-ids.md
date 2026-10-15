<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — board ids packed, boot not sent

**Goal.** Put the live FDT's eight msm-id pairs and board-id `0x40008`
into the dodge DTB and pack a header v2 image. Boot it only while the
phone is on the cable.
**Phone.** Not on USB when the boot was attempted. Last seen in
OxygenOS, slot `_a`, build `CPH2653_16.0.10.501(EX01)`.
**Kernel.** `omamobile-dodge` `f71c365a8`, on top of `16cf517b2781`.
**Result.** The image is packed. It has not been booted.

## What we did

`qcom,msm-id` and `qcom,board-id` were added to
`sm8750-oneplus-dodge.dts` in the live order. Only the DTB was rebuilt.
`mkbootimg` packed `~/android/mainline/out-dodge/images/boot-ids.img`
with the same geometry and cmdline as the phase 0d image.

## What happened

The built DTB is 87599 bytes and decompiles to the same cell list as
the live FDT. The boot image is 45481984 bytes, header v2, sha256
`1e68b0b85b085a85230fc561b8b3e14c8840a251051c87639dfe14eeb8ec746f`.
`adb reboot bootloader` failed with no device. USB had no OnePlus and
no fastboot device for the next 30 s. No boot command was sent.

## Learning

The boot waits until the cable enumerates again. The image to send is
`boot-ids.img`, not the earlier image with no ids.
