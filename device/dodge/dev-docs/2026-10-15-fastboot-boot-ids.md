<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — board ids packed, boot not sent

**Goal.** Put the live FDT's eight msm-id pairs and board-id `0x40008`
into the dodge DTB and pack a header v2 image. Boot it only while the
phone is on the cable.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked.
**Kernel.** `omamobile-dodge` `f71c365a8`, on top of `16cf517b2781`.
**Result.** Booted. ABL stayed in fastboot. OxygenOS was restored.

## What we did

`qcom,msm-id` and `qcom,board-id` were added to
`sm8750-oneplus-dodge.dts` in the live order. Only the DTB was rebuilt.
`mkbootimg` packed `~/android/mainline/out-dodge/images/boot-ids.img`
with the same geometry and cmdline as the phase 0d image.

## What happened

The built DTB is 87599 bytes and decompiles to the same cell list as
the live FDT. The boot image is 45481984 bytes, header v2, sha256
`1e68b0b85b085a85230fc561b8b3e14c8840a251051c87639dfe14eeb8ec746f`.
The first boot attempt found no USB device and sent nothing.

After the cable was reseated, adb showed product `CPH2653EEA` on slot
`_a`. Fastboot was up in 10 s, `current-slot` `a`, `product` `sun`.
`fastboot boot` returned `Booting OKAY` in 1.3 s. `18d1:d00d` was still
the only USB device 60 s later. No SSH. `fastboot reboot` reached
OxygenOS in 18 s, same build, `magiskd` running.

## Learning

Adding the live ids did not get ABL to leave fastboot. The header v2
image is still not started. The stock image that did boot was header
v4. Flashing `vendor_boot` is still not the next step; the next change
is one thing about the image ABL actually starts, recorded on its own.
