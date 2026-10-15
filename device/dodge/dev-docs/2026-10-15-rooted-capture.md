<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — a rooted capture instead of a downstream-kernel track

**Goal.** Decide whether to run Omarchy on OnePlus's own kernel first,
as a shortcut, and how to get a running reference system for mainline.
**Phone.** Not attached. CPH2653, as in the plan.
**Kernel.** None of ours.
**Result.** No downstream-kernel track. Phase 1 ends with OxygenOS rooted
through Magisk and a read-only capture of the running phone
([../PLAN.md](../PLAN.md) §6, phase 1, "The rooted capture").

## What we considered

**The shortcut.** Arch and Omarchy on OnePlusOSS's 6.6 kernel, with the
vendor modules from `vendor_dlkm`. Display, Wi-Fi and charging would
likely come sooner, and the GPU would go through Qualcomm's KGSL driver
(Mesa's Turnip has a KGSL mode, and Zink could carry GL on top) [I].

What it would carry over to mainline:

- A known-good running system to compare against: the live DT, the
  memory map, which regulators and clocks are on, pin settings, I2C
  addresses, firmware load order. This is most of its value.
- Wiring facts: panel power-on commands and timings, touch GPIOs, rail
  voltages. Knowledge, not code.
- All of the userspace work (root image, device package, Hyprland
  scaling, install tools), because Omarchy is the same either way.

What it would throw away: every kernel line. Downstream display (SDE),
GPU (KGSL) and audio are different frameworks from mainline's (DPU,
`drm/msm`, AudioReach), and none of it is upstreamable. Plus a second
kernel to maintain, and the risk that "good enough on 6.6" stalls the
mainline port. That runs against the project's own rule:
[CONTRIBUTING.md](../../../CONTRIBUTING.md) §1, mainline and
upstream-ready commits; Google's GPL tree on the Pixel is reference only.

**What we need from it is root on a working system, once.** The wiring
facts mostly come offline from OnePlusOSS's DT and the OTA's `dtbo`
(phase 0b), and the userspace work can start as soon as mainline reaches
the bootloader's framebuffer.

## Magisk or LineageOS

Two ways to root a working system:

| | Magisk on OxygenOS | LineageOS "Rooted debugging" |
| --- | --- | --- |
| What is flashed | `init_boot` on the active slot | `boot`, `dtbo`, `init_boot`, `vendor_boot`, `recovery`, and `vbmeta` |
| Stock copy to restore from | The OTA's `init_boot.img` (§3.2) | Several partitions, and the install may ask to copy firmware between slots |
| Fits §3.1 and §3.3 | Yes | `vbmeta` and the slot copy are exactly what those sections hold back |
| Reference fidelity | The firmware and kernel we extracted from the OTA | Lineage's 6.6 kernel and its own DT |
| Root over adb | `su -c`, granted once on the screen | `adb root` |

Magisk wins on every row that matters: one partition, a stock copy to put
back, nothing the safety sections forbid, and a capture of the firmware
the phone actually runs. Lineage's only advantage is `adb root`, which a
small `su -c` path in `bin/omamobile capture` replaces (phase 0e).

## Learning

- The question to ask of a shortcut is which of its outputs mainline
  needs. Here only one did, and it has a cheaper source.
- Magisk stays installed. A rooted OxygenOS is still the loop's way back
  (§5.2), and the capture can be repeated whenever a mainline driver
  needs a fresh comparison.
- The capture holds identifiers (serial, MACs, IMEI in properties). It
  lives in `~/android/reference/dodge-cph2653/rooted-<date>/` and is
  quoted in the plan only after a check for them.
- Still [I]: that ABL boots a Magisk-patched `init_boot` on an unlocked
  phone without a `vbmeta` change, as Magisk's documentation describes
  for unlocked devices. Phase 1's rollback covers it if not.
