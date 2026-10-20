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
  DCS writes read back exactly from the panel.
- **Off/on works now (19:06 CEST), with `31453abbe`** (keep `MDSS_GDSC` on
  while MDSS is runtime suspended, SM8750 only). Verified with no device
  held on: 5 + 3 fb blank/unblank cycles (test v) and 5 Hyprland
  `dpms off`/`on` cycles on `card1` (test w), no `tx failed`, brightness
  read back exactly after every cycle but one (see the readback quirk
  below). While off, MDSS, DPU, DSI and PHY all runtime-suspend and the GDSC
  stays on (0 collapses).
- **Cause, as far as it is pinned down:** a display session followed by a
  collapse of `MDSS_GDSC` leaves the DSI command DMA stalled on the next
  enable. A collapse before the first modeset is harmless, and so is a
  session without a collapse. Every visible DSI, PHY, MDSS-top, DPU and
  dispcc config register is identical in the working and failed states;
  only status differs (`STATUS0` 0x3, `CLK_STATUS` 0x2343 → 0x8037c3,
  VBIF `XIN_HALT_CTRL1` ffff0000 → fffe0000). So the lost state is outside
  the registers msm programs: best candidates are the display SMMU/TBU
  (our tree lacks the `qcom,sm8750-mdss` ACTLR entry upstream has) or the
  VBIF/AXI halt handshake (downstream SDE halts VBIF AXI before collapse;
  upstream DPU does not). `31453abbe` is a workaround with a FIXME, not the
  root fix.
- **CPU: no drop.** Screensaver load, 30 s: simpledrm 633 % total (Hyprland
  584 %), msm 690 % (Hyprland 648 %). Rendering is llvmpipe either way;
  the scanout path was never the cost. The win is a real screen off and
  brightness. Idle (static desktop) is about 2 % on both.
- **Not loaded at boot yet.** A reboot still comes back to simpledrm.

## Kernel (wt-dodge, `omamobile-dodge`, local only)

| Commit | What |
|---|---|
| `db69e9ca6` | DT: panel VCI (`vreg_l13b_3p0`) 1.8 V → 3.0 V. Stock's DT has `pm_humu_l13` (L13B) at min = max = init 3.0 V, and the panel node asks 3.0–3.3 V; SM8750 MTP/QRD also 3.0 V. Booted 17:04 CEST, regulator reads 3000 mV, desktop unchanged. |
| `a2b6a28a0` | Panel: command mode (stock: `dsi_cmd_mode`, TE on gpio86 `mdp_vsync`, already in the DT pinctrl). Video burst gave frame done timeouts. |
| `34467b564` | Upstream `6cd33b6f4155` drm/msm/dsi: round 6G byte clock rate (backport, clean). |
| `d7eb3a44e` | Upstream `2028280686f4` drm/msm/dsi: round the byte clock after reparenting (backport, clean). |
| `d86d5f0b2` | Upstream `06b7ba206561` drm/msm/dsi: drop `dev_pm_opp_set_rate(0)` (backport; correct, did not fix off/on on its own). |
| `31453abbe` | drm/msm/mdss: keep `MDSS_GDSC` on across runtime suspend on SM8750 (`dev_pm_genpd_rpm_always_on()` from a per-SoC `keep_gdsc_on` flag, FIXME in the comment). The off/on fix. Clocks and interconnect votes still drop. |

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

13. **d-10..d-13, 17:40-18:00, read-only plus one hold.** Full 4 KiB DSI,
    PHY/PLL/lane, MDSS-top and DPU snapshot dumps, working vs failed:
    config identical, only `STATUS0` (0x3, DMA busy), `CLK_STATUS` and VBIF
    `XIN_HALT_CTRL1` differ. Holding `ae94000.dsi` `power/control=on`
    makes 5/5 off/on cycles work. Claude consult 4.
14. **d-14, failed.** Holding dispcc on (MMCX stays on, GDSC collapses):
    fails. dispcc PLL/RCG registers identical. So it is the GDSC.
15. **d-15, failed.** No `BLOCK_DMA_WITHIN_FRAME`: same stall, so the DMA
    fetch itself hangs. Claude consult 5.
16. **d-16, failed.** `DISP_CC_MDSS_CORE_BCR` reset on every MDSS resume.
17. **d-17, failed.** Backport of `06b7ba206561` (kept as `d86d5f0b2`).
    Claude consult 6 (advised against the DPU opp backport `811c38907eab`
    as a test; it is stashed, not committed).
18. **n, about 18:30, worked.** Hold only MDSS (`ae00000`) on, DPU/DSI/PHY
    runtime-suspend: 5/5 cycles, brightness exact.
19. **o, p, failed.** Diag `msm.ko` (e1) keeping MDSS clocks and ICC
    (o), then ICC only (p), across suspend: both fail. e1 still dropped
    the clocks briefly on resume, hence q.
20. **q, failed.** Diag `msm.ko` keeping MDSS clocks and ICC on while the
    GDSC still collapses: fails. The collapse itself is the trigger.
21. **r, failed.** dispcc diag without `RETAIN_FF_ENABLE` (GDSCR
    0xfa22f002): fails. Also counted: the GDSC had collapsed 4 times before
    bind and the first enable still worked.
22. **s, failed.** A 0.05 s collapse after a session fails too; duration
    does not matter.
23. **t, about 19:00, worked.** Collapse after bind (about 8 s), then the
    first enable: fine. So only session-then-collapse breaks it. Claude
    consult 7 ranked VBIF state, then the SMMU/TBU path; accepted keeping
    the GDSC on as an interim with a FIXME.
24. **u, 19:03, worked.** Diag: GDSC kept on via
    `dev_pm_genpd_rpm_always_on()`, clocks and ICC dropped: 5 cycles, no
    `tx failed`, 0 collapses.
25. **v, 19:06, worked.** Clean `31453abbe`, no hold: 5 + 3 cycles, no
    `tx failed`, brightness exact except cycle 1.
26. **w, 19:10, worked.** Hyprland restarted on `card1` (msm): runs,
    DSI-1 1440x3168@120. 5 cycles of `hyprctl dispatch
    'hl.dsp.dpms("off")'` / `"on"` (Hyprland 0.56 Lua syntax): CRTC
    `active=0`, MDSS and DSI suspended while off, brightness exact, no
    `tx failed`. CPU measured as above (msm 19:16, simpledrm 19:20 CEST).

Readback quirk: the first brightness readback right after the first
off/on cycle is sometimes wrong (900 → 1007 or 2100); every later one is
exact. Not investigated.

Logs: `logs/display-2026-10-20-{f..w}.log` on the laptop (not committed).

## Next

- Load at boot: a once-per-boot unit before `omamobile-hyprland.service`
  that loads dispcc first, then the deps, the panel and `msm`, with a flag
  file to turn it off; then Hyprland on `card1` from the start.
- Hook Omarchy's idle/DPMS and brightness keys to the backlight.
- Root fix candidates, one per boot: backport the upstream
  `qcom,sm8750-mdss` SMMU ACTLR entry (`PREFETCH_DEFAULT | CMTLB`), or halt
  the VBIF AXI port before MDSS suspend as downstream SDE does; if either
  fixes it with the GDSC collapsing, drop `31453abbe`.
- Measure the screen-off power cost of the GDSC staying on.
- CPU: try 60 Hz on msm (llvmpipe is the cost); a GPU waits for A830.
