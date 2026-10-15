<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — header v2 image of stock pieces

**Goal.** See whether this ABL starts any header v2 image under
`fastboot boot`. The pieces are ones this phone has already run. Do
not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 remains in `init_boot_a`.
**Kernel.** The OTA kernel, not ours.
**Result.** Fail. `Booting OKAY`, then 60 s in fastboot. `fastboot
reboot` restored OxygenOS. Header v2 does not start on this ABL.

## What we did

`mkbootimg --header_version 2` with:

- kernel from the OTA `boot.img` (36731392 bytes)
- ramdisk from the OTA `init_boot.img` (2720723 bytes, LZ4 legacy), not
  the Magisk ramdisk now on the partition
- `--dtb` the live FDT from the rooted capture (1638203 bytes, model
  "Sun MTP,dodge", `qcom,board-id` `<0x40008 0x00>`)
- page 4096, kernel offset `0x8000`, ramdisk `0x01000000`, tags `0x100`,
  dtb `0x01f00000`, `--base 0`
- an empty command line

The image is
`~/android/mainline/out-dodge/images/boot-v2-stock.img`, 41099264
bytes, sha256
`3252d19f0947d9da7347485d4f64d0866258bdb0284ad8d93d8a24d358953783`.
`adb reboot bootloader`. Fastboot in 10 s, slot `a`, product `sun`.
`fastboot boot`.

## What happened

```text
Sending 'boot.img' (40136 KB)                      OKAY [  0.916s]
Booting                                            OKAY [  0.308s]
```

`18d1:d00d` was the only phone USB device at every check to 60 s. No
adb. `fastboot reboot` brought OxygenOS back in 20 s: slot `_a`, same
build, `ro.boot.flash.locked=0`, `magiskd` running.

## Learning

The same bootloader starts the stock header v4 `boot.img` and does not
start a header v2 image packed from that kernel, the stock init
ramdisk, and the live devicetree. The v2 failures with our kernel were
not specific to our kernel, ramdisk, ids, or dtbo. Changing the command
line on another v2 image would not show whether ABL appends one,
because the kernel would not run.

A self-contained image has to be something other than header v2, or
`vendor_boot` has to be flashed so a header v4 boot can carry our DTB.
That flash is a separate decision. It was not done.
