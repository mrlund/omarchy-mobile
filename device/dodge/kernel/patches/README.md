<!-- SPDX-License-Identifier: MIT -->
# dodge kernel patches (local series, 6.16)

A durable copy of the local kernel branch `omamobile-dodge`, which lives only on
the Omarchy machine (`~/android/mainline/wt-dodge`). Nothing here has been sent
to any maintainer. Exported 2026-10-21.

## Base

- Repo: https://github.com/sm8750-mainline/linux.git, branch `v6.16`
- Base commit: `16cf517b278155b0b8b5df6d876f840e5e9885f6` ("Very important fix",
  2025-09-15)

## Apply

```sh
git clone -b v6.16 https://github.com/sm8750-mainline/linux.git && cd linux
git checkout 16cf517b278155b0b8b5df6d876f840e5e9885f6
git am /path/to/device/dodge/kernel/patches/0*.patch   # 0001 .. 0050, in order
```

Applying `0001`-`0050` on the base gives exactly the tree of local commit
`31453abbe` (checked with `git am` plus `git diff`, 2026-10-21).

Left out of the series:

- `034552311` (ath12k REO register dump, diagnostic) and its revert
  `662f16ae6`. They cancel out.
- `17f3dac8e` (SMMU ACTLR data for SM8650/SM8750 MDSS) is in
  [not-applied/](not-applied/). **It is not boot-proven and not a fix**: with
  the GDSC collapsing, off/on still fails (NOTES 2026-10-21). It is a copy of
  upstream data and can go in later, but nothing depends on it.
- `not-applied/0002` (local `bd9587d65`, 2026-10-21) adds the 4 MiB `rmtfs_mem`
  region at `0xd7c00000` for the modem. **Flashed to boot_a on 2026-10-21** after
  5 boots with the node (4 clean, one unexplained display kickoff failure). It is
  kept here and applies on top of `0050` (or `0052`).

## Config

- `../config-6.16.0-gb3ee311dab85-running`: `/proc/config.gz` of the Image on
  the phone (built 2026-10-16 at `b3ee311da`).
- `../config-6.16.0-gb3ee311dab85-modules`: the current `out-dodge/.config`. It is
  the running config plus four options added later as modules
  (`ATH12K_COREDUMP`, `DRM_PANEL_ONEPLUS_DODGE`, `SND_SOC_AW882308`,
  `TOUCHSCREEN_SYNA_TCM2`). Use this one for a new build.
- `../generic-2026-10-21.config`: slice 1 of the move toward Derek's
  `omamobile.config`. It holds the generic options that exist on 6.16
  (Landlock, binder/binderfs, nftables, PSI, dmabuf heaps, built-in IPv6,
  socinfo and device-mapper). The header lists what was left out and why.
- `../config-6.16.0-gbd9587d65`: the `-modules` config plus that fragment.
  **Flashed to boot_a on 2026-10-21** after a clean one-shot test
  (`boot-chain-avb.img` sha256 `9940497e…`; fallback
  `out-dodge-chain/images/boot-chain-avb.before-cfg1.img`, `5ab5829f…`).

## Build

The phone still runs the Oct 16 Image. The later patches are loaded as modules
that were built against it, so builds pin the release string:

```sh
cp ../config-6.16.0-gb3ee311dab85-modules out-dodge/.config
make O=out-dodge ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gb3ee311dab85 olddefconfig
make O=out-dodge ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gb3ee311dab85 \
     Image modules qcom/sm8750-oneplus-dodge.dtb
```

Slice 1 (the fragment) uses a **new** release string, so its modules sit
next to the old ones and the flashed kernel never sees them:

```sh
cp ../config-6.16.0-gb3ee311dab85-modules out-dodge-cfg1/.config
scripts/kconfig/merge_config.sh -m -O out-dodge-cfg1 out-dodge-cfg1/.config \
    ../generic-2026-10-21.config
make O=out-dodge-cfg1 ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gbd9587d65 olddefconfig
make O=out-dodge-cfg1 ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gbd9587d65 \
     Image modules qcom/sm8750-oneplus-dodge.dtb
make O=out-dodge-cfg1 ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gbd9587d65 \
     INSTALL_MOD_PATH=stage INSTALL_MOD_STRIP=1 modules_install
# on the phone: stage/lib/modules/6.16.0-gbd9587d65 -> /usr/lib/modules/6.16.0-gbd9587d65.held
```

The loaders still insmod from `/usr/lib/modules/6.16.0-gb3ee311dab85.held` and
`/usr/local/lib/omamobile`. `../omamobile-kmod-overlay(.service)` runs before
`sysinit.target`. With any other `uname -r` it bind-mounts
`/usr/lib/modules/<R>.held` and `/usr/local/lib/omamobile.<R>` over those two
paths. `omamobile.<R>` is a copy of `/usr/local/lib/omamobile` with each `.ko`
replaced by the new build's module of the same name. The unused
`dodge-wlan-*.ko` have no source and are left out, and `qcom_rmtfs_mem.ko` comes
from `rmtfs_mem.ko`. With the pinned kernel the unit does nothing.
`tools/dodge-kmod-overlay-tree` builds that copy, and `tools/dodge-battcheck` is
the battery gate to run before a reboot or flash.

The boot image is put together as in [../../dev-docs/](../../dev-docs/)
(`2026-10-16-flash-boot-a.md`). Flash rules are in [../../AGENTS.md](../../AGENTS.md).

## Module-only patches on top of `0050` (2026-10-22)

`0051` and `0052` sit on local `bd9587d65` (the flashed kernel, which also
has `not-applied/0001`-`0002`) as `02a123bae` and `4485c548f`. They change
only `panel-aa569-p-3-a0019-dsc.ko` and `msm.ko`. Both are installed in
`/usr/local/lib/omamobile.6.16.0-gbd9587d65/display/`; nothing is flashed.

- `0051` drm/panel: oneplus-dodge: the panel takes its `vddio`/`vdd`/`vci`
  supplies (L12B/L11B/L13B, existing DT names; no DT change, and it never
  sets a voltage). It enables them before the reset pulse. On unprepare,
  failed init and `.shutdown`, it asserts reset, turns off vci, vdd, vddio
  and waits 200 ms. This is a test for the warm-reboot display drop
  (dev-docs/2026-10-21-display-drop.md, Round 7); not boot-proven yet.
- `0053` drm/panel: oneplus-dodge: v2. The rails are taken at probe and stay on
  across unprepare/prepare; they are cut only at shutdown and remove. Local
  `7327948f9`. Installed (`dda4e21c`, v1 kept on the phone as
  `*.ko.rails1`). Warm series: 6 of 8 clean, not a fix (Round 8).
- `0052` DIAG drm/msm/dsi: on `cmd dma tx failed` it logs `STATUS0`,
  `LANE_STATUS` (0x0a4), `LANE_CTRL`, `CLK_STATUS` and `DLN0_PHY_ERR`.
- Fallback: `../fallback/panel-aa569-p-3-a0019-dsc.ko.pre-rails` (md5
  `463dd36b`, stripped `0050`-era build); on the phone as `*.ko.pre-rails`
  and `msm.ko.pre-lanediag` next to the live modules.

## Display fix: `0054` (2026-10-23)

- `0054` drm/msm/mdss: sm8750: read the display QTB once on every MDSS enable
  (local `12048bd2c`, branch `dodge-qtbfix` = `bd9587d65` + this patch only;
  no DIAG, no `0052`). Root fix for the warm-boot display drop (the third
  DSI command DMA fetch hangs after a warm reset); evidence in the commit
  message and dev-docs/2026-10-21-display-drop.md Rounds 20-28.
- The QTB address (`0x017d0000`, mdp_hf_qtb) is hard-coded per-SoC match
  data for now: mainline sm8750.dtsi has no TBU nodes, so there is nothing to
  reference from DT. Upstream form: a DT phandle to the TBU or an
  arm-smmu-qcom hook.
- Installed as the persistent `msm.ko` (`a153ae874f75`, stripped) in
  `/usr/local/lib/omamobile.6.16.0-gbd9587d65/display/`; the previous live
  module (`2c86adc467db`, `0052` lanediag build) is kept beside it as
  `msm.ko.pre-qtbfix`.
- Rollback (on the phone, then a gated reboot):
  `cd /usr/local/lib/omamobile/display && cp msm.ko.pre-qtbfix msm.ko && sync`
- `0055` Revert "drm/msm/mdss: keep MDSS_GDSC on across runtime suspend on
  SM8750" (local `44f4c9050`, branch `dodge-qtbfix` = `bd9587d65` + `0054` +
  `0055`). The GDSC off/on failure that `0050` worked around has the same
  cause, and the `0054` read on every enable fixes it; the domain collapses in
  screen-off again (saves about 1 mA). Tested as diag build `r29g` (`0054` with
  `keep_gdsc_on = false`, `6069cfcd6516`), now the persistent `msm.ko`; the
  `0054`-only module is kept as `msm.ko.qtbfix-gdscon` (`a153ae874f75`), and
  `msm.ko.pre-qtbfix` stays. Rollback to GDSC-on:
  `cd /usr/local/lib/omamobile/display && cp msm.ko.qtbfix-gdscon msm.ko && sync`

## Workarounds, not fixes

- `0050` drm/msm/mdss: keep `MDSS_GDSC` on across runtime suspend (local
  `31453abbe`). Works around the first enable after a GDSC collapse failing
  (`cmd dma tx failed -110`); costs about 1 mA. Root-caused and reverted by
  `0055` (the `0054` QTB read); still in the flashed kernel source, module
  only.
- `0022` remoteproc: qcom: pas: `only_adsp`, a bring-up switch so the modem and
  CDSP are not probed. Not upstreamable as is.
- `0047`-`0049` DSI byte-clock rounding and the `dev_pm_opp_set_rate(0)` drop,
  needed for the AA569 bring-up. Review against newer msm before upstreaming.
- ath12k peach / WCN7860 (`0006`-`0020`, `0035`-`0042`): working bring-up on the
  QCC2072 HAL, but needs a proper review against current ath12k.
- Picked from the lists, authors kept: `0002` (Maulik Shah), `0047` (Kavan Smith),
  `0048` (Dmitry Baryshkov), `0049` (Konrad Dybcio).

## Series

- `0001-arm64-dts-qcom-sm8750-oneplus-dodge-add-ABL-board-id.patch`
- `0002-soc-qcom-rpmh-rsc-Add-RSC-version-4-support.patch`
- `0003-power-reset-nvmem-reboot-mode-write-only-the-bytes-a.patch`
- `0004-Input-synaptics-tcm2-build-the-SPI-touchscreen.patch`
- `0005-arm64-dts-qcom-sm8750-oneplus-dodge-enable-the-WCN-P.patch`
- `0006-wifi-ath12k-claim-PCI-id-0x110e.patch`
- `0007-wifi-ath12k-use-window-register-0x3278-for-PCI-id-0x.patch`
- `0008-bus-mhi-host-boot-a-two-ELF-TME-firmware-image.patch`
- `0009-wifi-ath12k-mark-PCI-0x110e-as-a-TME-firmware-image.patch`
- `0010-wifi-ath12k-send-the-peach-TME-Lite-patch-before-boa.patch`
- `0011-wifi-ath12k-send-the-peach-host-DMA-window.patch`
- `0012-wifi-ath12k-do-not-advertise-the-full-peach-DMA-aper.patch`
- `0013-wifi-ath12k-keep-peach-DMA-inside-the-low-256-MiB.patch`
- `0014-wifi-ath12k-leave-peach-ddr_range-unset.patch`
- `0015-wifi-ath12k-allow-skipping-the-peach-TME-Lite-downlo.patch`
- `0016-wifi-ath12k-download-peach-PHY-and-aux-ucode.patch`
- `0017-wifi-ath12k-send-peach-aux-ucode-only-when-advertise.patch`
- `0018-wifi-ath12k-download-the-peach-QDSS-trace-config.patch`
- `0019-wifi-ath12k-record-the-peach-firmware-crash.patch`
- `0020-wifi-ath12k-bring-peach-up-in-mission-mode.patch`
- `0021-soc-qcom-pd-mapper-list-the-SM8750-domains.patch`
- `0022-remoteproc-qcom-pas-let-only_adsp-skip-the-modem-and.patch`
- `0023-arm64-dts-qcom-sm8750-describe-the-ADSP-FastRPC-chan.patch`
- `0024-misc-fastrpc-hand-the-audio-PD-its-remote-heap.patch`
- `0025-ASoC-qcom-q6apm-lpass-dais-let-the-I2S-DAIs-take-a-f.patch`
- `0026-arm64-dts-qcom-sm8750-oneplus-dodge-enable-the-speak.patch`
- `0027-arm64-dts-qcom-sm8750-oneplus-dodge-add-the-speaker-.patch`
- `0028-ASoC-qcom-sc8280xp-set-the-I2S-format-on-MI2S-back-e.patch`
- `0029-arm64-dts-qcom-sm8750-oneplus-dodge-add-the-sound-ca.patch`
- `0030-ASoC-codecs-add-a-bring-up-driver-for-Awinic-0x2308-.patch`
- `0031-ASoC-qcom-sc8280xp-no-headset-jack-on-MI2S-links.patch`
- `0032-arm64-dts-qcom-sm8750-oneplus-dodge-add-the-WCD939x-.patch`
- `0033-arm64-dts-qcom-sm8750-oneplus-dodge-add-the-USB-C-he.patch`
- `0034-ASoC-codecs-aw882308-add-the-Receiver-profile.patch`
- `0035-wifi-ath12k-do-not-tell-peach-the-QDSS-config-is-mis.patch`
- `0036-wifi-ath12k-no-rfkill-GPIO-on-peach.patch`
- `0037-wifi-ath12k-single-phy-hw-mode-and-channel-list-fixe.patch`
- `0038-wifi-ath12k-add-the-WCN7860-register-table.patch`
- `0039-wifi-ath12k-add-the-QCC2072-RX-descriptor-and-its-ac.patch`
- `0040-wifi-ath12k-support-32-bit-TLV-REO-command-and-statu.patch`
- `0041-wifi-ath12k-add-the-QCC2072-RX-DMA-ring-selection-co.patch`
- `0042-wifi-ath12k-add-WCN7860-hw-params-using-the-QCC2072-.patch`
- `0043-Bluetooth-qca-add-WCN7860-support.patch`
- `0044-arm64-dts-qcom-sm8750-oneplus-dodge-enable-Bluetooth.patch`
- `0045-arm64-dts-qcom-sm8750-oneplus-dodge-set-the-panel-VC.patch`
- `0046-drm-panel-oneplus-dodge-drive-the-AA569-panel-in-com.patch`
- `0047-drm-msm-dsi-round-6G-byte-clock-rate-to-the-PLL-achi.patch`
- `0048-drm-msm-dsi-round-the-byte-clock-rate-after-reparent.patch`
- `0049-drm-msm-dsi-Drop-dev_pm_opp_set_rate-0.patch`
- `0050-drm-msm-mdss-keep-MDSS_GDSC-on-across-runtime-suspen.patch`
- `0051-drm-panel-oneplus-dodge-own-the-panel-supplies-and-p.patch`
- `0052-DIAG-drm-msm-dsi-dump-STATUS0-LANE_STATUS-LANE_CTRL-.patch`
- `0053-drm-panel-oneplus-dodge-keep-the-supplies-on-across-.patch`
- `0054-drm-msm-mdss-sm8750-read-the-display-QTB-once-on-eve.patch`
- `0055-Revert-drm-msm-mdss-keep-MDSS_GDSC-on-across-runtime.patch`
