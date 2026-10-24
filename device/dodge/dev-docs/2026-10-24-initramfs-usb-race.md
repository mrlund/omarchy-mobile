<!-- SPDX-License-Identifier: MIT -->
# 2026-10-24: stage-2 initramfs USB race (cable-out boots waited ~60 s and raced a panic)

Martin saw "USB never configured, panicking in 20 s" on a cable-out cold
start at 19:00 CEST. He asked for it to be fixed after the wrap-up.

## Cause

In `device/dodge/initramfs/init`:
- A backgrounded watchdog panicked (`sysrq c`) if no UDC reached
  `configured` within 45 s, after a 20 s warning.
- The main loop only ran `boot_arch` once userdata was ready AND USB was
  configured, waiting up to 60 s.

Without a host, the boot sat about 60 s in the initramfs. On the 19:00
boot the warning came at 46.7 s and switch_root at 61.7 s, about 5 s before
the panic.

## Change (init only)

- Main loop: `boot_arch` as soon as `/run/omamobile-userdata-ready` exists.
  The configfs gadget (NCM+ACM) and the `usb0` address are set before this
  and stay across `switch_root`. Arch has no gadget service of its own and
  still gets USB networking (verified with ssh).
- Rescue timer: it exits once the UDC is configured. It fires only when
  there is no Arch root and no USB: 45 s (90 s with
  `omamobile.userdata-rw` and no `omamobile.initramfs`). While a root mount
  is in progress (`/run/omamobile-root-pending`) it allows 120 s. It
  re-checks USB after the 20 s warning, and `boot_arch`'s `kill -9 -1` ends
  it.
- `omamobile.test-nousb` (test cmdline only): the gadget is left unbound.

## Build

The stage-2 initramfs was repacked reproducibly (mtime 0, sorted, newc,
owner 0:0, `lz4 -l -9`). Repacking the unchanged tree gives the old
`401bedce...` exactly. The new one is
`b10dc1dcb235b114051d746a157f43b5ef8a85eadd7b9a60c023e897b1cc45c9`.

The chain was rebuilt from a copy of the gpu1 flash build. Only `initrd`
differs in the embedded cpio; the Image, dtb and cmdline (`dodge.flashed`)
are unchanged. The boot image is
`ef049091d515cf953f6c3cf79420b41a2588ed05a0a553f64b4bf455c22653af`
(60305408 bytes).

## Tests (CEST)

| Test | switch_root | Result |
|---|---|---|
| before, cabled (gpu1) | 3.69-3.75 s | - |
| before, cable-out (Martin 19:00) | 61.7 s | panic warning at 46.7 s, ~5 s margin |
| usbfix1 cabled one-shot 19:11 | 3.65 s | usb0/ssh, DSI 0 tx failed, Hyprland, GPU, Wi-Fi 0 % loss |
| test-nousb one-shot 19:14 | 13.6 s | no rescue/panic message; display, GPU, Wi-Fi up; trial deadline hard-rebooted to boot_a at 220 s as designed |
| flashed boot_a 19:21 | 3.60 s | deadline cancelled at 80 s, UDC configured |
| gated warm reboot 19:24 | 3.61 s | no rescue message, deadline cancelled at 80.7 s, usb0, Hyprland, GPU, Wi-Fi |

The test-nousb 13.6 s is the existing 10 s wait for `usb0`. With the
gadget unbound there is no NCM interface. In a real cable-out boot the
gadget is bound, so about 3.6 s is expected. Pending: one cable-out cold
start by Martin.

Rollback: `tools/dodge-restore-73gpu1` (64a754b7), then
`dodge-restore-73s1`, then `dodge-restore-616`.

## Verified (19:46 CEST)

Martin did a cable-out cold start of usbfix1 (boot at 19:42). It switched
root at 3.586 s with no rescue, "USB never configured" or panic message, and
the deadline was cancelled at 80.4 s.
