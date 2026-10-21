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
- **Loaded at boot since 19:23 CEST** by `display/omamobile-display-msm`
  (installed with `display/install`). Hyprland comes up on `card1` DSI-1.
  Off switch: `touch /etc/omamobile/display-msm.disable` and reboot.

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

27. **x, 19:23, worked.** Load at boot. `omamobile-display-msm.service`
    (once per boot, `Before=omamobile-hyprland.service`, no `Requires`, so
    Hyprland starts whatever happens) loads dispcc, the deps, the panel and
    `msm`, then waits up to 20 s for `card*-DSI-1` to be connected. The
    script always exits 0. Journal: bound at 7.1 s, Hyprland started at
    7.1 s. `/dev/dri` has only `card1` and `renderD128`; DSI-1
    1440x3168@120, scale 2, transform 0. The plane scans out a 1440x3168
    framebuffer, plus the 512x512 cursor plane. No failed units. 5 Hyprland
    DPMS cycles with exact brightness, no `tx failed`. The only display
    noise is the known `DSI PLL(0) lock failed` twice at probe.
28. **Omarchy controls, 19:28, work unchanged.** `brightnessctl -l` sees
    `ae94000.dsi.0` (max 3502). Run inside the Hyprland session (`hyprctl
    dispatch 'hl.dsp.exec_cmd("...")'`), `omarchy-brightness-display`
    30 %, +5 %, 5 %-, 80 % and 50 % gave 1051, 1226, 1051, 2802 and 1751,
    each read back exactly from the panel. `off` sets CRTC `active=0` and
    `bl_power` 4; `on` brings it back with the brightness kept. From a
    plain `su ml` shell `brightnessctl set` gets EPERM: that shell has no
    logind session, and the sysfs file is root-only. The brightness keys
    are bound in Omarchy's `media.lua`, so they should work as-is. Idle is
    not wired: `hypridle` is not installed on the phone.

29. **Martin's eyes, 20:18, worked.** Desktop upright, colours correct.
    The parent ran sysfs brightness 700 (dim), then 2802 (bright),
    Hyprland DPMS off for 5 s (fully dark), on, then 1751. 0 `tx failed`.
30. **Hand wake, 20:20, worked; input unknown.** `dpms off` at 20:20:33.
    Martin tapped, then short-pressed the power key if needed, and the
    screen came back. omarchy-shell logged `screensaver-wake: user
    returned` at 20:20:44. Nothing records which device it was:
    `HandlePowerKey=ignore`, and Hyprland doesn't log input.
31. **Idle, 20:25, not wired, needs Martin.** Omarchy 4.0.4 has no
    hypridle: omarchy-shell's idle service runs the screensaver at 150 s
    and locks at 300 s, and the lock blanks the display 5-10 s later. The
    lock is denied for missing PAM (`/etc/pam.d/omarchy-lock-password`,
    `omarchy-apply-lock`), and `ml` has no password. So: Martin sets a PIN
    (`omamobile-set-pin`), then `omarchy-apply-lock`.

32. **Power A/B, 20:2x-20:34, done.** Battery `current_now`, 2 s samples,
    on USB, with idle set to stay-awake during each run (restored after).
    GDSC kept on: screen on -74 mA, off -161 mA (a drop of 87 mA). With the
    `d17` module (GDSC collapses), on +15 mA, off -73 mA (a drop of 88 mA),
    and the re-enable failed again (`tx failed` 2), as expected. Keeping the
    GDSC on costs about 1 mA or less, within the noise. Boot 20:32: the
    fixed module is back, 5 DPMS cycles are clean, and the Hyprland unit
    shows its new description.

33. **Idle off, 20:38-20:41, worked.** `omamobile-idle-off` (Quickshell
    `IdleMonitor`): 20 s test, off then back on by a synthetic key; then
    the 150 s default turned the screen off at 20:41:04. Screensaver off
    through Omarchy's toggle; no lock.
34. **Hyprland CPU, 20:40.** DPMS off: 0 %; screen on and idle: 13 %;
    screensaver: 685 %, with about 19 `initMgpu: no renderer` errors a
    second. The errors come only with rendering.
35. **ACTLR prep, not booted.** Kernel `17f3dac8e`. No boot-chain change
    with the battery at 20 %.

36. **ACTLR, 2026-10-21 09:12, failed.** Image built from `17f3dac8e`
    (`KERNELRELEASE=6.16.0-gb3ee311dab85`), started once with `fastboot
    boot` (nothing flashed), with the `d17` `msm.ko` (GDSC collapses).
    The first enable after a session and a collapse: `Failed to initialize
    panel: -110`, `cmd dma tx failed` 3, kickoff timeouts. The ACTLR entry
    alone does not fix it.
37. **VBIF AXI halt, 09:17, failed.** Diag `msm.ko` (`d17` basis plus
    `patches-dodge/diag-vbif-axi-halt-2026-10-21.diff`, not committed): in
    `dpu_runtime_suspend`, write `VBIF_AXI_HALT_CTRL0` (0x208) = 1 and poll
    `CTRL1` (0x20c) bit 0 for 4 ms; clear it on resume. On the flashed
    Oct 16 Image. Before the first modeset the halt acks (`CTRL1` 0x31, all
    XIN halted). After a session it times out (`CTRL1` 0x30) although
    `XIN_HALT_CTRL1` reads ffffffff, then the collapse and the same
    enable failure. So an AXI transaction is still outstanding below the
    XIN clients when the DPU suspends, and halting cannot drain it.
38. **Control, 09:20, worked.** Back to `31453abbe` (`msm.ko` restored), 5
    enable cycles, 0 `tx failed`. Root fix not found; `31453abbe` stays.

Test note: on this Hyprland, `hyprctl dispatch 'hl.dsp.dpms("off")'` and
`("on")` both toggle; check `bl_power` and the MDSS runtime status rather
than trusting the argument. Logs: `logs/display-2026-10-21-{actlr,vbif,fixed}.log`.

Battery sign: `current_now` is positive when discharging and negative when
charging; `status` is unreliable (`Discharging` at -167 mA). The A/B
numbers in 32 are net of the USB input (an SDP, 500 mA).

The fallback has a limit. If `msm` binds and then fails after it has
taken the framebuffer over from simpledrm, there is no DRM device left,
Hyprland fails, and `getty@tty1` starts (its `OnFailure`). SSH is
unaffected; recover with the off switch and a reboot.

Readback quirk: the first brightness readback right after the first
off/on cycle is sometimes wrong (900 → 1007 or 2100); every later one is
exact. Not investigated.

Logs: `logs/display-2026-10-20-{f..w}.log` on the laptop (not committed).

## Next

- Idle: Martin sets a PIN (`omamobile-set-pin`), then `omarchy-apply-lock`;
  verify that the lock blanks, and which input wakes it
  (`libinput debug-events`).
- Root fix: the ACTLR entry and a VBIF AXI halt both failed (36, 37). The
  halt timing out after a session points at an outstanding AXI read at
  suspend, possibly the DSI command DMA or the SMMU/TBU path. Next
  candidates: check whether DSI suspends after the DPU and halt there, or
  compare downstream SDE's suspend order. `31453abbe` stays until then.
- CPU: try 60 Hz on msm (llvmpipe is the cost); a GPU waits for A830.
