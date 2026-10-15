<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — OxygenOS boot time, and fastboot without a reseat

**Goal.** Time one reboot to the home screen, and see whether
`adb reboot bootloader` enumerates with the cable left alone.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk `init_boot_a` is installed.
**Kernel.** No kernel of ours.
**Result.** Boot completed in 26 s. Fastboot appeared in 13 s without
reseating the cable.

## What we did

`adb reboot`, timed from the command until `sys.boot_completed=1` and
until a launcher was the resumed activity. Then `adb reboot bootloader`,
timed until `fastboot devices` showed one device. `getvar` for
`current-slot` and `product` only. `fastboot reboot` back to OxygenOS.

## What happened

`sys.boot_completed` was 1 at 26 s. From then on,
`mFocusedApp` was `com.android.launcher/.Launcher` and
`mCurrentFocus` was `NotificationShade`, so the UI was up on the shade
or the lock screen rather than a still-booting animation. The script
that looked only at `mCurrentFocus` did not call that the home screen.

`adb reboot bootloader` showed `18d1:d00d` at 13 s. No reseat.
`current-slot` was `a`, `product` was `sun`. The earlier flash attempt
had found the boot menu with no USB device; this repeat did not.

## Learning

`tools/dodge-try`'s OxygenOS wait is 120 s: the 26 s measurement plus
margin, replacing the 600 s placeholder. The way back from OxygenOS to
fastboot worked with the cable left plugged in.
