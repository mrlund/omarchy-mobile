<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20: msm display path (DPU + DSI + AA569 panel), first light

Follows [2026-10-16-desk-check-display-touch-gpu.md](2026-10-16-desk-check-display-touch-gpu.md).
Goal: brightness and a real screen off, instead of simpledrm at a fixed
brightness. Everything here is loaded by hand (`display/display-try`) under a
dead-man reboot; a reboot always comes back to simpledrm and Hyprland.

## Result so far

- **First modeset works.** `msm` binds (DPU `0xc0000000`, `card1`, a
  command-mode encoder), frames go out at 120 Hz (`pp_tx_done` about every
  8 ms), and Martin saw modetest's colour bars on the panel (17:2x CEST).
- **Brightness works.** `/sys/class/backlight/ae94000.dsi.0` (max 3502).
  DCS writes read back exactly from the panel: 600, 3000, 1500, 900.
- **Open blocker: any disable/enable cycle breaks it.** After `fb0` blank
  1 then 0, the panel's on-sequence fails at its second command (`8a 01`,
  sometimes the first) with `cmd dma tx failed -110`, no DSI error IRQ, no
  SMMU fault; then backlight `-110`, frame done and commit timeouts. So DPMS
  and Hyprland on `card1` are not usable yet, and nothing loads at boot.

## Kernel (wt-dodge, `omamobile-dodge`, local only)

| Commit | What |
|---|---|
| `db69e9ca6` | DT: panel VCI (`vreg_l13b_3p0`) 1.8 V → 3.0 V. Stock's DT has `pm_humu_l13` (L13B) at min = max = init 3.0 V, and the panel node asks 3.0–3.3 V; SM8750 MTP/QRD also 3.0 V. Booted 17:04 CEST, regulator reads 3000 mV, desktop unchanged. |
| `a2b6a28a0` | Panel: command mode (stock: `dsi_cmd_mode`, TE on gpio86 `mdp_vsync`, already in the DT pinctrl). Video burst gave frame done timeouts. |
| `34467b564` | Upstream `6cd33b6f4155` drm/msm/dsi: round 6G byte clock rate (backport, clean). |
| `d7eb3a44e` | Upstream `2028280686f4` drm/msm/dsi: round the byte clock after reparenting (backport, clean). |

`CONFIG_DRM_PANEL_ONEPLUS_DODGE` is now `=m` in `out-dodge/.config` (it was
never enabled, which alone explains the black panel when `msm` was loaded
before). The panel module and `msm.ko` (built with `KERNELRELEASE` of the
running Image) live in `/usr/local/lib/omamobile/display/`; the rest comes
from the held module tree. The boot image is unchanged apart from the VCI DT.

## Attempts (CEST)

1. **d-1, 17:04, worked.** VCI 3.0 V boot (stage 2 DTB diff: only that
   regulator). Root, Wi-Fi, BT, Hyprland fine.
2. **d-2, 17:07, failed.** insmod chain without `dispcc-sm8750`:
   `msm-mdss` probe `-110` (supplier `af00000.clock-controller` dormant).
3. **d-3, 17:07, failed.** dispcc loaded, `msm-mdss` bound by hand: DPU and
   backlight up, but panel init `cmd dma tx failed -110` (video mode),
   frame done timeout. Probe prints `DSI PLL(0) lock failed` twice plus
   clk WARNs (`dsi0_phy_pll_out_*clk already disabled`) from the orphan
   reparent in `dsi_phy_driver_probe`; one SMMU fault inside ABL's splash
   buffer (DPU still fetching it).
4. **Claude consult 1, 17:10.** Suggested missing SM8750 PHY fixes. Checked:
   our `dsi_phy_7nm.c` already equals upstream master; dispcc fix present.
5. **d-4, 17:14, partly worked.** Command-mode panel, dispcc loaded first:
   first modeset (modetest, Hyprland stopped) works, 120 Hz, brightness
   readback. Blank/unblank fails as above.
6. **d-5, 17:19, failed.** Byte-clock rounding backports: no change; the
   7nm PLL `determine_rate` only clamps, so rounding returns the same value
   and every transfer still calls `vco_set_rate`.
7. **Claude consult 2, 17:22.** Suggested (3) PLL reprogramming, then (2)
   DSI/PHY rails.
8. **d-6, 17:24, failed.** `vco_set_rate` skipping a running PLL with the
   same dividers (diagnostic, not committed; kept as a patch on the
   laptop). No change.
9. **d-7, 17:28, failed.** Diagnostic `msm.ko` that never disables the DSI
   host and PHY regulators. No change. Not committed.
10. **Claude consult 3, 17:30.** Suggested comparing clock counts.
11. **d-8, 17:32, read-only.** `clk_summary` counts (VCO, byte/pixel/esc
    branches) are identical during the working first modeset and in the
    failed state; after load everything is 0 and the PLL is off. So the
    first enable starts from the same clock state.
12. **d-9, 17:33.** Reloading only the panel module (fresh probe, reset
    asserted) does not recover; `msm` cannot be unloaded while fbcon holds
    it. Points at host state left by the first session, not the panel.

Back on simpledrm by 17:35 CEST (reboot; modules are not loaded at boot).

## Next

- Find what the first DSI session leaves behind: dump DSI ctrl registers
  (`CTRL`, `CMD_DMA_CTRL`, `DMA_*`, lane status) on the first vs the second
  enable; check whether MDSS really runtime-suspends between them.
- Then wire it up: load at boot from the initramfs order (dispcc first),
  Hyprland on `card1`, DPMS through Omarchy's hook, brightness slider.
- A cheap check for Martin, if useful: describe the screen right after a
  test (black, colour bars, garbled, desktop).
