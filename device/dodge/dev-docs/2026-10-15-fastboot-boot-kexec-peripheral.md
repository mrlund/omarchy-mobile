<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — stage 2 USB as a peripheral: still no controller

**Goal.** One change in stage 2's devicetree: `dr_mode = "peripheral"`
and no `usb-role-switch`. The role otherwise comes from `pmic_glink`,
which this initramfs does not load. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 1 the chain-loader in `out-dodge-rdinit`. Stage 2
the `out-dodge` image and `dodge-try` initramfs.
**Result.** Fail. No USB gadget. OxygenOS back at 125 s, the no-UDC band.

## What we did

`device/dodge/chainload/stage2-dtb.py` grew a `peripheral` option. It
refuses to run unless the built DTB has exactly one `dr_mode = "otg"`
and one `usb-role-switch`. `DTB_OPTS=peripheral tools/dodge-chain pack`
with `CHAIN_OUT=~/android/mainline/out-dodge-rdinit` wrote
`images/boot-v4-kexec-peripheral.img`, 58339328 bytes, sha256
`d8e1e244d4a80eabe8495861fa2c990170549dec620dcd0b34bca60eafbd070c`.
A decompile of the stage 2 DTB before packing showed
`dr_mode = "peripheral"` and no `usb-role-switch`.

`adb reboot bootloader`, slot `a`, product `sun`, `fastboot boot`.

## What happened

`Booting OKAY` in 1.7 s. USB left fastboot within a second. `1d6b:0104`
never appeared, and SSH did not answer. adb was back as `22d9:2769` at
125 s. OxygenOS: slot `_a`, same build, `ro.boot.flash.locked=0`,
`magiskd`, uptime 32 s.

125 s is the band where stage 2's init finds no USB device controller
in 30 s and then takes its panic fallback
([2026-10-15-fastboot-boot-kexec-ssh.md](2026-10-15-fastboot-boot-kexec-ssh.md)
saw that at about 137 s). It is not the band where a controller
registered and the host never configured it.

## Learning

Forcing peripheral mode was not enough. The controller is still not
registering a gadget. The timing-coded probe in
[../chainload/README.md](../chainload/README.md) is the next boot: it
says whether the glue probed, whether dwc3 bound, and whether a UDC
exists, without a log.
