<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — Arch Linux ARM is the root on userdata

**Goal.** Phase 4a: a Linux userspace on `userdata`, reached by
`fastboot boot`, with every other disk still read-only. No flash.
**Phone.** CPH2653, slot `_a`. `boot_a` is still OxygenOS's boot image.
**Kernel.** `6.16.0-gb3ee311dab85` #8. `DTB_OPTS='splash fb'`. Cmdline
includes `omamobile.userdata-rw`.
**Result.** Pass for a base Arch root. SSH is Arch Linux ARM, mounted
on `/dev/sda15`. This is not the Omarchy image.

## What we did

`tools/build-rootfs` needs the signing key in `keys/`, which is not
on this machine. `tools/dodge-alarm-root` builds a base Arch Linux ARM
root instead: sshd, password login locked, `usb0` at `172.16.42.1`.
The image is ext4, label `omamobile-root`, 2880 MiB, at
`out/dodge-alarm-root.img` (not committed).

It was written only to `/dev/sda15` while that partition was already
the one writable device. The ext4 magic on the partition matched the
image. Then `reboot-to bootloader` and `fastboot boot`.

The first of those boots stayed in the ramdisk. `tools/dodge-chain
pack` had reused the previous stage 2 initramfs, which opens
`userdata` and does not switch. `tools/dodge-try pack` rebuilt the
initramfs, and the second boot switched.

## What happened

```
omamobile: ufs-ro: allow sda15 (userdata) writable; /dev/sda node removed
omamobile: arch: switching to Arch Linux on /dev/sda15
```

SSH at about 27 s. `/etc/os-release` is Arch Linux ARM. `/` is
`/dev/sda15` ext4, read-write. `/dev/sda` does not exist. Every other
partition is read-only. `sshd` and `systemd-networkd` are active.
`systemctl --failed` is empty. `soc@0` is present.

The file system is 2880 MiB at the start of a much larger partition.
It was not grown. OxygenOS's data partition was replaced by this
write. A reboot without `fastboot boot` still uses `boot_a`, which
was not written.

## Learning

Phase 4a can run a userspace from `userdata` without flashing. The
signed Omarchy root is still waiting on `keys/`. The stage 2
initramfs has to be rebuilt with `tools/dodge-try pack` before
`tools/dodge-chain pack` when `device/dodge/initramfs/init` changes.
