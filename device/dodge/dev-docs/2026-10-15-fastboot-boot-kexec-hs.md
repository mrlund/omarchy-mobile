<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — stage 2 HS-only peripheral: still no controller

**Goal.** Stop dwc3 waiting on the combo PHY and on a role switch.
Use the init that resets on its own. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** Stage 1 chain-loader. Stage 2 `out-dodge` image and the
`dodge-try` initramfs.
**Result.** Fail. No gadget. OxygenOS back at 137 s, the no-UDC band.

## What we did

`stage2-dtb.py hs` sets `dr_mode = "peripheral"`, removes
`usb-role-switch`, and leaves only `usb2-phy`. Image
`out-dodge-rdinit/images/boot-v4-kexec-hs.img`, sha256
`caa6f0c70b88e8bd83c3cb3252b5d084032baf465a9ad328eda2079060b48643`.
`Booting OKAY` at 09:32:33.

## What happened

`1d6b:0104` never appeared. adb was back as `22d9:2769` at 137 s.
OxygenOS: slot `_a`, same build, `ro.boot.flash.locked=0`, uptime 30 s.

## Learning

Dropping the SuperSpeed PHY and the role switch together still does
not register a gadget. The same init was booted again with the dwc3
`iommus` entry removed as well
(`boot-v4-kexec-hs-noiommu.img`, sha256
`2fcb3f0ccb7ea53d009c1a88bf8af7dfbf61d0842e4937a3895cf693fa123716`).
`Booting OKAY` at 09:36:29. Again no `1d6b:0104`. adb at 137 s.
OxygenOS came back on slot `_a` with the same build. Neither wait
was the whole holdup. This init does return, so these two boots did
not need the three-key reset.
