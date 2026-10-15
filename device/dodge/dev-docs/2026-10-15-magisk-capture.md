<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — Magisk 30.7 and the capture's su path

**Goal.** Download the Magisk APK phase 1 will install, and teach
`bin/omamobile capture` to use Magisk's `su -c` plus the dodge listings.
**Phone.** Not touched. CPH2653, build `CPH2653_16.0.10.501(EX01)`.
**Kernel.** No kernel of ours. The packed image from
[2026-10-15-dodge-try](2026-10-15-dodge-try.md) was not booted.
**Result.** Pass on the laptop. The APK is not installed, and capture
was not run.

## What we did

The latest non-prerelease on `github.com/topjohnwu/Magisk` is tag
`v30.7`, published 2026-02-23, name "Magisk v30.7". Its notes include
Android 16 QPR2 sepolicy support. This phone's security patch is
2026-08-01, so whether that APK patches this `init_boot` stays a phase 1
check. The release also has `app-debug.apk`. That asset was not
downloaded. The installable file is `Magisk-v30.7.apk`.

Saved at `~/android/reference/dodge-cph2653/root/Magisk-v30.7.apk`,
11613864 bytes, sha256
`e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5`,
matching the release asset digest. The file stays out of git.

`bin/omamobile capture` used to treat the phone as rooted only when
`adb shell id -u` was 0. Magisk does not do that: the adb uid stays
`shell`, and root is `su -c`. The cheetah branch is still `adb shell`
for the device tree, dmesg, `/proc` and `/vendor/firmware`, and it runs
only when the adb uid is 0. The comparison now strips the CR adb appends,
which otherwise makes uid 0 fail the test. The Magisk branch uses
`adb exec-out su -c`, so the FDT is not CRLF-mangled, and the probe is
bounded by 10 s. `DEVICE=dodge` then also reads the phase 1 views:
regulator summary, clock summary, pinctrl pinmux, debugfs gpio, the I2C
and platform buses, `/vendor/firmware_mnt`, `/vendor/lib/modules`, and
partition names with sysfs sizes. It does not read regmap registers,
partition contents, or `devmem`. It does not change the panel. Phase 1
runs it twice, screen on and screen off.

No `adb` or `fastboot` command was run.

## What happened

The download and the digest check succeeded. `bash -n bin/omamobile`
succeeded. Capture was not pointed at a phone, so the `su` branch has
not run on a device yet.

## Learning

Phase 1 installs this exact APK and grants `su` on the screen before
the capture. The command is `DEVICE=dodge bin/omamobile capture
dodge-cph2653/rooted-<date>-on`, then the same with `-off`. An ungranted
`su` prompt hits the 10 s bound and the capture records no root files.
That is the stop, not a second attempt with a longer wait.
