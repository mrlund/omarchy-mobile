<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — a ramdisk in an uploaded v4 boot.img did not run

**Goal.** Find out whether ABL uses a ramdisk carried inside an uploaded
header v4 `boot.img`, or always takes `init_boot_a`'s. A yes would let
one v4 image chain-load our kernel and DTB with `kexec`, with no flash.
Test it with the stock kernel, so our kernel is not a variable.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a` (ramdisk 2409501 bytes in its
header).
**Kernel.** The OTA kernel, not ours.
**Result.** Fail. OxygenOS with `magiskd` was on adb 12 s after
`Booting OKAY`. Our `/init` did not run.

## What we did

The ramdisk is the Alpine staging from `tools/dodge-try`, with
`/root/.ssh` removed and `/init` replaced by:

```sh
#!/bin/sh
mount -t proc proc /proc 2>/dev/null
sleep 90
echo b > /proc/sysrq-trigger
while :; do sleep 60; done
```

cpio newc, `lz4 -l` (legacy, `02 21 4c 18`, the same as stock's
ramdisks), 5004574 bytes. `mkbootimg --header_version 4` with the OTA
`boot.img` kernel and that ramdisk, no cmdline:
`~/android/mainline/out-dodge/images/boot-v4-rdprobe.img`, 41742336
bytes, sha256
`7f04d26c66098f915c009a0b2faeb22bdab0ae05c17e4a234ae2a47da70cb07a`.
`unpack_bootimg`: header 4, ramdisk 5004574, cmdline empty, signature
0, kernel byte-identical to the OTA kernel.

`adb reboot bootloader`, fastboot in 12 s, slot `a`, product `sun`,
`fastboot boot`.

## What happened

```text
Sending 'boot.img' (40764 KB)                      OKAY [  0.929s]
Booting                                            OKAY [  0.406s]
```

| t after `Booting OKAY` | USB |
| --- | --- |
| 0 s | `18d1:d00d` (fastboot) |
| 2 s | nothing |
| 12 s | `22d9:2769`, adb |

OxygenOS: slot `_a`, same build, `ro.boot.flash.locked=0`, `magiskd`
running, uptime 14 s. Our `/init` would have held the phone for 90 s.

As root, `dmesg` already started at 1.6 s (`modprobe` lines), so the
`Freeing initrd memory` line that gives the initrd size was gone. It
cannot tell us whether ABL dropped our ramdisk, or appended
`init_boot`'s after it so that Magisk's `/init` replaced ours.

## Learning

Either way, a `/init` in the uploaded v4 `boot.img` does not run. The
`boot.img` ramdisk cannot carry a kexec chain-loader on this ABL.

Timing, [I]: the stock kernel on this path reaches adb 12 s after
`Booting OKAY`. Our kernel on the same path
([2026-10-15-fastboot-boot-v4.md](2026-10-15-fastboot-boot-v4.md)) took
about 23 s. Our config has `CONFIG_PANIC_TIMEOUT=10`, and an early
panic, a 10 s wait and a reset would add about that much. That is a
hint that our kernel ran on stock's DTB, not proof.
