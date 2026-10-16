<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — desk check: panel, touch, GPU, Hyprland without a GPU

**Goal.** Before phase 4 reaches Hyprland, find out what is already in
our kernel tree and upstream for the panel, touch and GPU, and whether
Omarchy's Hyprland can draw on `simpledrm` with software rendering. No
phone.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`. Stock facts from
the rooted capture of 2026-10-15 (`~/android/reference`, not committed).
**Kernel.** No boot. The worktree `wt-dodge` (`omamobile-dodge`, 6.16)
and its `out-dodge` config.
**Result.** Panel and touch drivers are in our tree but not enabled.
The GPU is not. Hyprland on `simpledrm` plus llvmpipe has one reported
working setup. One DTS bug: the panel's VCI rail is held at 1.8 V.

## What we did

Read the dodge DTS and its drivers in `wt-dodge`, matched them against
stock's `dmesg` and live FDT, and searched upstream and Hyprland's
trackers.

## What happened

**Panel.** Stock's `dmesg` names `AA569_P_3_A0019_dsc_cmd` ("AA569 P 3
A0019 dsc cmd mode panel"), one of the five command-mode panels in the
OTA's list (PLAN §6, phase 0b). Our tree has
`drivers/gpu/drm/panel/panel-aa569-p-3-a0019-dsc.c` (1440×3168, 120 Hz,
DSC, compatible `oneplus,dodge-panel`, marked FIXME), and the DTS has
the panel on `mdss_dsi0`. `CONFIG_DRM_PANEL_ONEPLUS_DODGE` is not set.
DPU (`dpu_12_0_sm8750.h`), MDSS and the 3 nm DSI PHY for SM8750 are in
the tree. `DRM_MSM` is `=m`.

**Panel rail.** The DTS gives the panel `vci-supply = <&vreg_l13b_3p0>`
and constrains that LDO to 1.8 V–1.8 V. Every stage 2 log shows
`vreg_l13b_3p0: Setting 1800000-1800000uV` at about 0.18 s. Stock's
panel node asks for VCI 3.0–3.3 V
(`qcom,panel_voltage_vddr = <0x01 0x2dc6c0 0x30d400 0x325aa0>`), the
stock regulator summary shows `pm_humu_l13` at 3000 mV, and the upstream
MTP and QRD boards set `vreg_l13b_3p0` to 3.0 V. That `pm_humu_l13` is
our `l13b` is [I]. The console still showed on the panel with the rail
at 1.8 V, so either the panel tolerates it while ABL's scanout runs, or
VCI comes from somewhere else.

**Touch.** Stock probes a Synaptics S3910 (`synaptics_tcm_hbp`,
`syna_dev_probe`). Our tree has `syna_tcm2.c` and `syna_tcm2_spi.c`
(compatible `synaptics,tcm-spi-hbp`), and the DTS has the node on
`spi4`. The driver reads the chip's own firmware and does not request a
file. `CONFIG_TOUCHSCREEN_SYNA_TCM2` is not set. Its Kconfig says
`depends on I2C` for an SPI driver, and its Makefile builds a composite
`syna_tcm2.o` that lists `syna_tcm2.o` as a member, which kbuild treats
as a circular dependency. It has never been built in our config.

**Buttons.** Power (`pon_pwrkey`), Volume Up (`pon_resin`) and Volume
Down (`gpio-keys`) are all in the DTS.

**GPU.** The Adreno 830 is not in our tree: no catalog entry and no GPU
node in `sm8750.dtsi`. Upstream, "drm/msm: Support for Adreno 830 GPU"
(6 patches, with DT and bindings) was on the list and in review in
August 2026. The cover letter says the firmware is in linux-firmware and
Mesa needs a chip-id fix that is only in Mesa main.

**Hyprland without a GPU.** Omarchy's `hyprland 0.56.2-4` (aarch64,
omarchy-pkgs PR 649, merged 2026-09-27) backports a fix that detects
software rendering from the GL renderer string, written for
`simpledrm` plus llvmpipe. Its author reports a working desktop on an
M3 Air with `simpledrm` and llvmpipe, at about 15 fps by eye. Aquamarine
issue 425 (open) describes a hot loop when the only DRM device is
`simpledrm`: renderer setup fails and is retried on every commit,
several CPU cores busy and the log growing without bound. Aquamarine
PR 406 (a GBM fallback) was closed unmerged and lists `simpledrm` as a
device it does not cover.

## Learning

- Phase 4's "Hyprland up, software rendering" is plausible on
  `simpledrm` with Omarchy's own Hyprland, but watch for the aquamarine
  retry loop (CPU and log size) on the first start. If it loops, the
  next step is the real display driver, not a different compositor.
- The real display is closer than the GPU: driver, DPU and DSI are in
  the tree. Before enabling `DRM_MSM` and the panel driver, fix the
  VCI constraint to stock's 3.0 V, as its own boot.
- Touch needs its Kconfig and Makefile fixed before it builds.
- GPU work waits on the upstream A830 series and Mesa main. Software
  rendering stays the fallback (PLAN phase 5, row 5).
- Neither the panel nor the touch driver has been reviewed beyond these
  points. The postmarketOS page reports screen and touch working, which
  is someone else's result.

Sources: [drm/msm Adreno 830 series](https://ratatoskr.run/linux-arm-msm/2026/08/17387303/t),
[omarchy-pkgs PR 649](https://github.com/omacom/omarchy-pkgs/pull/649),
[aquamarine issue 425](https://github.com/hyprwm/aquamarine/issues/425),
[aquamarine PR 406](https://github.com/hyprwm/aquamarine/pull/406).
