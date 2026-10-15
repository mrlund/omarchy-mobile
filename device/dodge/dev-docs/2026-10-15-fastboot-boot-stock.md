<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — fastboot boot of the stock boot image

**Goal.** Prove `fastboot boot` of this build's own `boot.img` is
temporary: OxygenOS boots, and the next cold boot is a normal OxygenOS
boot. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk is installed in `init_boot_a`.
**Kernel.** The OTA's stock kernel, for one boot. No kernel of ours.
**Result.** Pass. `boot_a` was not written.

## What we did

`boot_a` and the OTA `boot.img` were both 100663296 bytes and the same
sha256 before the try. `adb reboot bootloader`. Fastboot was up in 10 s.
`current-slot` was `a`, `product` was `sun`. `fastboot boot` of
`~/android/reference/dodge-cph2653/ota/images/boot.img` (header v4,
kernel 36731392, ramdisk 0). Then one `adb reboot` with no `fastboot
boot`.

## What happened

`fastboot boot` sent 98304 KB and returned `Booting OKAY` in 2.7 s.
OxygenOS came back: slot `_a`, display id
`CPH2653_16.0.10.501(EX01)`, `ro.boot.flash.locked=0`, `magiskd`
running. `boot_a` sha256 was unchanged. The following cold boot reached
`sys.boot_completed` in 28 s with the same id, slot, lock bit and
`magiskd`, and `boot_a` was still unchanged.

## Learning

On this August 2026 firmware, `fastboot boot` of the stock image does
not replace `boot_a`. The next boot is the slot's own image. The packed
mainline image has not been tried.
