# OnePlus 13 vs Omarchy Mobile — initial assessment

> **2026-10-15:** Kept as the snapshot from the day the repo was cloned.
> The working plan is [device/dodge/PLAN.md](device/dodge/PLAN.md). The
> running log of attempts and what they taught us is
> [device/dodge/dev-docs/](device/dodge/dev-docs/).

Parked 2026-10-14. Repo cloned to `~/Repos/omarchy-mobile` from
https://github.com/derekross/omarchy-mobile (upstream tip around 2026-10-13).

## What Omarchy Mobile is today

Native Arch Linux ARM + Hyprland + Omarchy packages on the phone, mainline-ish
kernel, Android kept on slot A as the way back. Status: a pocket computer, not
yet a phone (modem SIM path still WIP).

**Only supported device:** Pixel 7 Pro (`cheetah`), Google Tensor G2 (`gs201`).
The multi-device track in `docs/RELEASES.md` is about more **Pixels** sharing one
kernel with per-board DTBs — not about Qualcomm SoCs.

## Target: OnePlus 13

| | |
|---|---|
| Codename | `dodge` (community / XDA) |
| SoC | Qualcomm Snapdragon 8 Elite (`SM8750` / `sun`) |
| Bootloader | Unlockable (`fastboot flashing unlock`; wipes data) |
| Stock | OxygenOS 15+, A/B slots, `init_boot` |

## Feasibility: hard / long haul

This is **not** "add another Pixel" (board DTS + device.conf). It is a **new
SoC platform** under Omarchy Mobile's model.

| Area | Pixel 7 Pro (today) | OnePlus 13 |
|---|---|---|
| SoC / DT | Google Tensor gs201, Exynos-derived DTIs | Snapdragon 8 Elite — different clocks, interconnect, GPU, modem |
| GPU stack | Mali-G710 + Panthor + Mesa patch | Adreno (different Mesa path) |
| Display | Custom gs-decon KMS | Qualcomm MDSS / DSI path |
| Boot / slots | Pixel bootloader quirks (`soc_id`, dtbo, dpm) | Qualcomm + OPlus boot chain |
| Installer safety model | Slot B + userdata only; never touch radio/abl | Needs a OnePlus-specific partition allowlist and flash map |
| Upstream Linux | Mature Tensor path in this project | SM8750 mainline is early; community experiments exist (Mu-Silicium UEFI, postmarketOS threads, vendor kernel trees) |

Likely effort: months of bring-up if pursued seriously, with display/GPU/Wi-Fi/modem each a project. Not a weekend port.

## Realistic approaches (when unparked)

### A. Watch upstream Omarchy Mobile (passive)
Stay on stock Android on the OnePlus 13. Revisit when/if the project announces
non-Pixel SoCs. Lowest risk.

### B. Community Linux footholds first (recommended next experiment)
Before touching Omarchy Mobile packaging:
1. Unlock bootloader on a secondary / spare OnePlus 13 only (never the daily driver first).
2. Capture stock facts (partition map, live DT, `fastboot getvar all`) — same spirit as `bin/omamobile capture`.
3. Try existing SM8750 / `dodge` paths: Mu-Silicium UEFI boot experiments, any postmarketOS / mainline kernel work, OnePlusOSS `sm8750` kernel trees as **reference only**.
4. Goal: SSH or a serial/USB console + framebuffer — prove the SoC can run a non-Android userspace.

Only then decide whether to graft that into Omarchy Mobile's `device/<codename>/` + `device.conf` model.

### C. Full Omarchy Mobile port (later)
Follow CONTRIBUTING §5 bring-up order, but rewrite every Tensor-specific stage
(clocks, display, GPU, ACPM/AoC equivalents, modem). Add
`omamobile-device-dodge` and never reuse cheetah `devmem` / DECON quirks.
Expect to contribute to `linux-omarchy-mobile` with a new SoC DT family, not just
a board file.

### D. Soft alternatives if the goal is "Omarchy-like phone UI"
- Keep OxygenOS; remote into Omarchy desktop.
- Wait for Waydroid-on-Omarchy-Mobile maturity on Pixel, then revisit whether a
  Qualcomm path appears.
- Dual-boot experiments only on a spare device.

## Suggested parked plan

1. Keep this clone; do not flash the daily OnePlus 13.
2. When ready: spare device + capture + community UEFI/mainline boot only.
3. Re-assess after first boot to a shell; only then scope an Omarchy Mobile `device/dodge` tree.
4. Decision gate: if SM8750 mainline still can't do display+GPU+Wi-Fi, stop or stay on B.

## References in this repo

- `README.md`, `docs/DEVICES.md`, `docs/ROADMAP.md`, `docs/RELEASES.md`
- `CONTRIBUTING.md` §5 (bring-up), §6.4 (matrix)
- Device work today: `device/cheetah/`
