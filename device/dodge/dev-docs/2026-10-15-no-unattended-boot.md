<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — no more unattended boots

**Goal.** Confirm the phone after the three-key power-off, and stop
sending `fastboot boot` while nobody can reset it.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
`ro.boot.flash.locked=0`, `magiskd` running. Uptime was 249 s when
adb came back, so this was the cable-powered boot after the power-off.
**Kernel.** No kernel of ours.
**Result.** Phone is back. Further boots wait for a person.

## What we did

Read-only, on the stock kernel: USB class and platform devices.

## What happened

`/sys/class/udc` is `a600000.dwc3`. The glue is `a600000.ssusb`
(`msm-dwc3`), not `a6f8800.usb`. The PHYs are `88e3000.hsphy` and
`88e8000.ssphy`. Our stage 2 DTB names the same addresses `usb` and
`phy`, so a probe that looks for `a600000.usb` is looking at our
devicetree's name, not stock's.

The two probe inits, which stat those sysfs nodes and then request a
reboot or a panic, did not bring USB back. The earlier stage 2 init
that only sleeps and writes sysrq does return (OxygenOS at 82 s for a
60 s sleep). Walking the USB sysfs from that kernel is the difference.

## Learning

Do not `fastboot boot` a stage 2 that touches the USB device nodes
unless someone is there to do Volume Up + Volume Down + Power. The
next attended boot is the sleep-and-sysrq init, which is known to
reset, with one devicetree change aimed at the glue probe (clocks,
interconnect, or resets in `dwc3-qcom-legacy`), and success seen as
`1d6b:0104` before the sleep ends.
