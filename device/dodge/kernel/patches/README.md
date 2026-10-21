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
  region at `0xd7c00000` for the modem. It was booted twice with `fastboot boot`
  and is not flashed yet: one of those boots had display kickoff timeouts and the
  other was clean (see `dev-docs/2026-10-21-modem.md`). It applies on top of `0050`.

## Config

- `../config-6.16.0-gb3ee311dab85-running`: `/proc/config.gz` of the Image on
  the phone (built 2026-10-16 at `b3ee311da`).
- `../config-6.16.0-gb3ee311dab85-modules`: the current `out-dodge/.config`. It is
  the running config plus four options added later as modules
  (`ATH12K_COREDUMP`, `DRM_PANEL_ONEPLUS_DODGE`, `SND_SOC_AW882308`,
  `TOUCHSCREEN_SYNA_TCM2`). Use this one for a new build.

## Build

The phone still runs the Oct 16 Image. The later patches are loaded as modules
that were built against it, so builds pin the release string:

```sh
cp ../config-6.16.0-gb3ee311dab85-modules out-dodge/.config
make O=out-dodge ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gb3ee311dab85 olddefconfig
make O=out-dodge ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gb3ee311dab85 \
     Image modules qcom/sm8750-oneplus-dodge.dtb
```

The boot image is put together as in [../../dev-docs/](../../dev-docs/)
(`2026-10-16-flash-boot-a.md`). Flash rules are in [../../AGENTS.md](../../AGENTS.md).

## Workarounds, not fixes

- `0050` drm/msm/mdss: keep `MDSS_GDSC` on across runtime suspend (local
  `31453abbe`). Works around the first enable after a GDSC collapse failing
  (`cmd dma tx failed -110`); costs about 1 mA. Root cause still open.
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
