<!-- SPDX-License-Identifier: MIT -->
# 2026-10-17 — Omarchy root grown to userdata

**Goal.** Grow the Omarchy root to the rest of `userdata`. No reboot,
no flash.
**Phone.** OnePlus 13 CPH2653. Omarchy 4.0.4 on `/dev/sda15`.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Pass. The file system is 453 GiB. No `ufshcd` error.

## What we did

The image written earlier was still 2818048 blocks of 4 KiB (about
10.5 GiB) on a partition of 493792325632 bytes. `tune2fs` showed
`resize_inode`, 1024 reserved GDT blocks, and a clean state. `persist`,
`super` and `boot_a` were read-only, and `/dev/sda` was absent.
`resize2fs /dev/sda15` ran while the file system was mounted on `/`.

## What happened

`resize2fs` 1.47.4 reported `old_desc_blocks = 2, new_desc_blocks = 58`
and 120554767 blocks of 4 KiB, the whole partition. `df` shows 453G,
8.1G used, 445G free. Reserved GDT blocks went from 1024 to 968.
`dmesg` has no `ufshcd` error line. `systemctl --failed` is empty.
The other partitions stayed read-only.

## Learning

The Omarchy image can use the rest of `userdata` the same way the
earlier Arch root did. The earlier grow was overwritten when that
image was written. Kernel modules stay held. Hyprland is the next
piece of phase 4, on `simpledrm`, not a restore of the module tree.
