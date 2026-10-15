<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — Magisk 30.7 installed, init_boot not flashed

**Goal.** Install the Magisk app and put the OTA's stock `init_boot` on
the phone so it can be patched. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
verified boot `orange`, `ro.boot.flash.locked=0`.
**Kernel.** No kernel of ours.
**Result.** The app installed, the image was patched in the app, and the
patched file checks out. It has not been flashed.

## What we did

`adb install -r` of
`~/android/reference/dodge-cph2653/root/Magisk-v30.7.apk`. The package
reports `versionName=30.7`, `versionCode=30700`. Then `adb push` of the
OTA `init_boot.img` to `/sdcard/Download/init_boot.img`.

## What happened

The install returned `Success`. The file on the phone is 8388608 bytes,
sha256
`612d604e894c477e4980d03b31ea1ecb0d9eee21f78473a15b22a3dfbcd10b29`.
`unpack_bootimg` of the laptop copy: header version 4, kernel size 0,
ramdisk 2720723 bytes, os version 15.0.0, patch level 2026-08. That is
the same header recorded in phase 0b.

## Learning

The patch was done in the app with Select and Patch a File. The output
`magisk_patched-30700_KE4JS.img` was pulled to
`~/android/reference/dodge-cph2653/root/`. It is 8388608 bytes, the same
padded size as stock, sha256
`161e4178fddfefd6b61b0d6011df9372806d6739cbd3cce42049816aa577a981`.
`unpack_bootimg` still reads header version 4, kernel size 0, os version
15.0.0, patch level 2026-08. The ramdisk is LZ4 legacy, as stock was,
and is smaller (2409501 bytes against stock's 2720723) because Magisk
recompressed it. The cpio contains `.backup/.magisk` and
`overlay.d/sbin/magisk.xz`. That is a Magisk init ramdisk, not a format
change. The file stays out of git.

The flash, when it happens, names `init_boot_a` and then reboots. Stock
`init_boot.img` is the rollback.
