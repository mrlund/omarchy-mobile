<!-- SPDX-License-Identifier: MIT -->
# 2026-10-24: flash 7.3.0-rc6-dodge-gpu1 (Adreno 830) as the default

Martin approved it at 18:42 CEST, after the candidate soak in
[2026-10-24-gpu-a830.md](2026-10-24-gpu-a830.md).

## Before the flash (read-only)

- On the flashed s1, I read back `boot_a` (`/dev/sde12`, 100663296 bytes):
  `dd if=$(readlink -f /dev/disk/by-partlabel/boot_a) bs=1M | sha256sum`
  gave `483cc7478a14e68246615566d3f843f21fd0a18faa5f63bb12e2f4d4c47998dd`.
  That equals `DEFAULT-7.3-boot_a-483cc747.img`, so the s1 rollback image is
  exact.
- I checked the candidate `CANDIDATE-7.3-gpu1-boot_a.img`: sha256
  `64a754b70c2cf6aef71cd95fc31a1a9a8d108cbd2faf321fa42df45fb12ae120`, 60305408
  bytes. Its chain cmdline is the same as the s1 default's, including
  `dodge.flashed`.
- **Deadline logic:** `dodge-deadline-arm.sh` sets `TRIAL=1` only for 7.x
  without `dodge.flashed`. So the flashed gpu1 gets `trial=0`, a 220 s
  graceful deadline and an 80 s clean check that cancels it. There was no
  soak flag left on the phone.
- **Boot-success marker:** `dodge-boot-success` in the gpu1 overlay is the
  same file as s1's (sha `c00f7247...`). Its unit conditions (sshd, ADSP
  battery, audio) are the same.
- **New tool:** `tools/dodge-restore-73s1 [flash|once|print]` puts the s1
  image back on `boot_a`. It checks the sha and the 96 MiB size, writes
  `boot_a` only, then runs `set_active a` and reboots.

## Flash (18:44-18:45 CEST)

- `tools/dodge-gate` passed (100 %).
- Ran `reboot-to bootloader`. Fastboot reported `current-slot: a` and
  `slot-successful:a: yes`.
- Ran `fastboot flash boot_a CANDIDATE-7.3-gpu1-boot_a.img` and then
  `fastboot set_active a`; the retry count read 7. Then `fastboot reboot`.
- SSH was up on gpu1 33 s later. A read-back of the first 60305408 bytes of
  `boot_a` gave `64a754b7...e120`. The rest of the partition still holds the
  tail of the old image; the boot image header ignores it.

## First boot and warm reboot

| | first boot (18:45) | gated warm reboot (18:51) |
|---|---|---|
| uname / cmdline | 7.3.0-rc6-dodge-gpu1, `dodge.flashed` | same |
| deadline | trial=0, clean (dpms On) cancelled at 81 s | trial=0, cancelled at 80 s |
| display | txfail 0, panel init 0, frame-done timeouts 0, Hyprland up | same |
| GPU | bound, GMU fw v5.1.25, runtime suspended (active 3.8 s of 274 s) | same, active 4.4 s |
| eglinfo (wayland) | Adreno (TM) 830, freedreno | same |
| Hyprland | `hyprctl systeminfo`: `qcom,adreno-44050000`; renderD128 GPU time 0.31 s | same |
| touch / USB | touchpanel / configured, usb0 | same |
| Wi-Fi | connected, ping 3/3 | connected, ping 1/3 (known 7.3 Wi-Fi loss) |
| BT / audio / sensors | powered / speaker sink + ALSA card / accelerometer | same |
| slot | boot_a 0x77 marked successful (retry 6) | already successful |
| oops / hangcheck | 0 | 0 |
| failed units | `systemd-backlight@backlight:ae94000.dsi.0` | same |

- The `systemd-backlight@` failure is not new: the s1 boot before the flash
  has it too.
- At 270 s, DSI shows `Off` both times. That is the normal idle screen-off;
  `idle-off` is running (not stopped), as normal.

## Phone state

- `boot_a` = gpu1, slot a active and successful.
- Release `7.3.0-rc6-dodge-gpu1` with its own module tree
  (`/usr/lib/modules/7.3.0-rc6-dodge-gpu1.held` plus
  `/usr/local/lib/omamobile.7.3.0-rc6-dodge-gpu1`).
- The s1 and 6.16 trees stay installed.

## Rollback chain: gpu1 -> s1 -> 6.16

All from fastboot:
1. `tools/dodge-restore-73s1` restores `DEFAULT-7.3-boot_a-483cc747.img`.
2. `tools/dodge-restore-616` restores `FALLBACK-6.16-boot_a-9940497e.img`.

Both only write `boot_a`, then run `set_active a`. For a one-shot boot that
writes nothing, use the `once` mode.

Host scripts (not in the repo): `logs/p73-flashgpu.sh`, `logs/p73-gpucheck.sh`
and `logs/p73-gwarm.sh`. The checks are in `logs/p73-gflash1-check.txt` and
`logs/p73-gwarm1-check.txt`.

## Martin's check (19:02 CEST)

The cable-out cold start plus idle/wake on the flashed gpu1 were both fine.

He glimpsed "USB never configured, panicking in 20 s" on the console. That
comes from the stage-2 initramfs USB rescue watchdog; analysis is in NOTES
open items (parked, about 5 s margin before the panic on that boot).

## Not covered yet

- A soak longer than 15 min.
- Vulkan.
