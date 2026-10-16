<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — Omarchy is on the screen, SSH is not

**Goal.** Get the Omarchy root on `sda15` to a usable boot.
**Result.** The human sees an Omarchy screen. SSH to `172.16.42.1`
port 22 is still refused. `boot_a` is the footered chain image again.

## What we did

The first Omarchy boots loaded the 1360 kernel modules. The journal
shows `msm` loading, a kernel trace, Plymouth starting, and no
`sshd` entries. The boot reached local file systems and the USB
gadget, not "multi-user".

`fastboot boot` of every image, including the footered `boot_a`
image, returned `Failed to load/authenticate boot image: Load Error`.
A footered ramdisk image was flashed to `boot_a` long enough to mount
`sda15`. The module directory was renamed to
`6.16.0-gb3ee311dab85.held`. SSH host keys and
`/root/.ssh/authorized_keys` were set to owner root, mode 600. The
default target is multi-user. `plymouth-start` is masked. The
Omarchy boot image was flashed back to `boot_a`.

## What happened

After that reboot the USB gadget is up and port 22 is connection
refused. The screen, which had been black, now shows Omarchy.

## Learning

Autoloading the full module tree is what took the display. Holding
the modules back is what brought a screen. sshd still does not
listen, so the reason is not only the host-key owner. The journal
from the boots before the hold never recorded an sshd start.
