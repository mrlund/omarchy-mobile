<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — fastboot boot of the packed mainline image

**Goal.** `fastboot boot` the header v2 image from phase 0d. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk remains in `init_boot_a`.
**Kernel.** The packed image: `6.16.0-g16cf517b2781`, dodge DTB with no
`qcom,msm-id` or `qcom,board-id`, sha256
`2c1914fa4ebc7dfb1f9169dde9249f4db3f33fef2bdfac95c321f1a951c09f25`.
**Result.** ABL answered `Booting OKAY` and stayed in fastboot. The
phone was rebooted to OxygenOS.

## What we did

`adb reboot bootloader`. Fastboot was up in 10 s. `current-slot` was
`a`, `product` was `sun`. `fastboot boot` of
`~/android/mainline/out-dodge/images/boot.img` (header v2, 45481984
bytes, cmdline `clk_ignore_unused pd_ignore_unused panic=10 console=tty0`).

## What happened

The command sent 44416 KB and returned `Booting OKAY` in 1.3 s.
`18d1:d00d` was still the only USB device 38 s later. No SSH on
`172.16.42.1`. No adb. `fastboot reboot` then reached OxygenOS in 18 s:
slot `_a`, display id `CPH2653_16.0.10.501(EX01)`,
`ro.boot.flash.locked=0`, `magiskd` running. `boot_a` was not written
by this command; the stock try already showed `fastboot boot` does not
replace it.

## Learning

This is §5.3 step 1. ABL accepted the boot command and did not start
the image. The DTB in it has no `qcom,msm-id` or `qcom,board-id`. The
live FDT carries all eight sun/sunp pairs and `qcom,board-id`
`<0x40008 0x00>`, so the next image adds those values and does not
collapse the pairs. Flashing `vendor_boot` is not the next step.
