<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — reboot bootloader uses reboot-to

**Goal.** `reboot bootloader` on the Arch root enters fastboot.
**Result.** Fastboot in about 6 s (`product: sun`, slot `a`).
`fastboot reboot` came back to Arch on `/dev/sda15`. Nothing flashed.

## What we did

`/usr/bin/reboot` is `systemctl`. `reboot bootloader` is systemd's EFI
firmware path, so it was not passing `LINUX_REBOOT_CMD_RESTART2`.
`/usr/local/bin` is ahead of `/usr/bin` on `PATH`. A wrapper there
execs `/usr/local/bin/reboot-to bootloader` when the argument is
`bootloader`, and `systemctl reboot` otherwise. The source is
`device/dodge/reboot`.

## What happened

`reboot bootloader` at 15:01:04. Fastboot at 15:01:10. `fastboot
reboot` then reached Arch Linux ARM, `/` on `/dev/sda15`.

`systemctl reboot bootloader` still calls systemd directly and does
not use the wrapper.

## Learning

The installed system can reach fastboot with `reboot bootloader`.
`boot_a` is our image, so `fastboot reboot` returns to Arch.
