<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — our kernel ran its built-in init on ABL's stock DTB

**Goal.** A ramdisk in the uploaded `boot.img` does not run
([2026-10-15-fastboot-boot-v4-ramdisk.md](2026-10-15-fastboot-boot-v4-ramdisk.md)).
Put the init inside our kernel instead, at a path ABL's ramdisks do not
use, and force the command line that starts it. Find out whether our
kernel reaches that init on the stock DTB ABL hands it. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** `6.16.0-gf71c365a86e2` (`omamobile-dodge` `f71c365a8`),
the `out-dodge` config plus the built-in initramfs and forced cmdline
below.
**Result.** Pass, from timing. OxygenOS was back 108 s after `Booting
OKAY`, against 12 s for the stock kernel and 23 s for our kernel
without the built-in init.

## What we did

The kernel unpacks its built-in initramfs first and the bootloader's
ramdisks over it, so a built-in `/init` would be replaced by Magisk's.
The probe lives under `/omamobile/` instead. `gen_init_cpio` list:

```text
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
dir /proc 0755 0 0
dir /omamobile 0755 0 0
file /omamobile/busybox <busybox.static> 0755 0 0
file /omamobile/init <init> 0755 0 0
```

`busybox.static` is Alpine 3.24's `busybox-static-1.37.0-r31`
(static-pie). `/omamobile/init`:

```sh
#!/omamobile/busybox sh
/omamobile/busybox mount -t proc proc /proc
/omamobile/busybox sleep 90
echo b > /proc/sysrq-trigger
while :; do /omamobile/busybox sleep 60; done
```

A copy of `out-dodge` became `out-dodge-rdinit`, so `out-dodge` and
the worktree stayed as they were. Config changes, and nothing else in
`.config` differed after `olddefconfig`:

```text
CONFIG_INITRAMFS_SOURCE="<the list above>"
CONFIG_CMDLINE="rdinit=/omamobile/init panic=10"
CONFIG_CMDLINE_FORCE=y
```

`CMDLINE_FORCE` drops the vendor cmdline (`console=ttynull`,
`bootconfig` and the rest). `Image` is 41032192 bytes.
`mkbootimg --header_version 4 --kernel Image`:
`~/android/mainline/out-dodge-rdinit/images/boot-v4-rdinit.img`,
41037824 bytes, sha256
`392065466e658e3d4dfe234f84a6af11eeb6b4ee4c1cce760d6d5ba3b3a862b4`,
ramdisk 0, cmdline empty. The same shape as the kernel-only v4 try.

`adb reboot bootloader`, fastboot in 12 s, slot `a`, product `sun`,
`fastboot boot`.

## What happened

```text
Sending 'boot.img' (40076 KB)                      OKAY [  0.913s]
Booting                                            OKAY [  0.383s]
```

| t after `Booting OKAY` | USB |
| --- | --- |
| 0 s | `18d1:d00d` (fastboot) |
| 2 s | nothing |
| 108 s | `22d9:2769`, adb |

OxygenOS: slot `_a`, same build, `ro.boot.flash.locked=0`, `magiskd`
running, uptime 14 s. So the reset came about 94 s after `Booting
OKAY`. `/sys/fs/pstore` was empty (the stock DTB's ramoops has no
mainline binding). `ro.boot.bootreason` and `sys.boot.reason` both read
`bootloader`; not known what they read after the earlier tries.

## Learning

| Image (all v4, stock DTB from `vendor_boot`) | OxygenOS on adb after `Booting OKAY` |
| --- | --- |
| stock kernel, our ramdisk in `boot.img` | 12 s |
| our kernel only | about 23 s |
| our kernel, built-in `/omamobile/init`, forced `rdinit` | 108 s |

The 90 s hold explains the 108 s: a few seconds of kernel boot, 90 s
of `sleep`, a sysrq reset, and the 12 s OxygenOS boot. So, from timing:
our kernel boots on ABL's stock DTB as far as userspace, runs a static
binary from its built-in initramfs, and `sysrq b` resets the phone
(PSCI from the stock DTB's `arm,psci-1.0` node). A forced cmdline and
an `rdinit` outside `/init` survive ABL's ramdisks.

The one other explanation is a watchdog that ABL leaves running and
that bites about 90 s in. A repeat with a different hold (45 s) tells
the two apart: our init moves the return time by 45 s, a watchdog does
not.

If that holds, the chain-loader is in reach without a flash: the same
built-in init carrying our DTB and a second kernel, and `kexec_file_load`
with `--dtb`. USB never came back after `kexec` on cheetah, so the
kexec'd kernel's first sign of life cannot rely on the cable alone.
