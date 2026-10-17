<!-- SPDX-License-Identifier: MIT -->
# 2026-10-17 — Hyprland on simpledrm

**Goal.** Put Hyprland on the splash framebuffer without loading the
held kernel modules.
**Phone.** OnePlus 13 CPH2653. Omarchy 4.0.4. User `ml`.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Hyprland 0.56.2 is running and owns the panel. The human
has not yet said what the glass shows.

## What we did

A one-shot unit `omamobile-hyprland.service` logs `ml` in on tty1 and
runs `uwsm start -e -D Hyprland hyprland.desktop`, with
`LIBGL_ALWAYS_SOFTWARE=1`. It conflicts with `getty@tty1` and is not
enabled, so a reboot returns to the console. The module directory
stayed held.

## What happened

Aquamarine opened `/dev/dri/card0` as `simpledrm` through logind.
`hyprctl monitors` shows `Unknown-1`, 1440×3168 at 60 Hz, format
`XRGB8888`, workspace 1, DPMS on, scale 1. The EDID parse failed,
which this framebuffer has no EDID to give. Quickshell is running.
`hyprctl clients` lists no windows. Hyprland's CPU fell from about
94% at startup to about 37%. The log was 51 KiB and still growing
slowly, not the unbounded aquamarine retry. No coredump was recorded.

## Learning

Software rendering on this panel is a live session, not only a
reported one. Scale landed on 1, so the UI may be small on
1440×3168. Leave the unit disabled until the picture is confirmed.
The real panel driver is still the later step, and it still wants
the VCI rail at 3.0 V before `DRM_MSM` is enabled.
