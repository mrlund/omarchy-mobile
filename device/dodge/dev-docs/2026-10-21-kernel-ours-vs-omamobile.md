<!-- SPDX-License-Identifier: MIT -->
# 2026-10-21: our dodge kernel vs Derek's `omamobile` (7.3-rc6)

Read-only research. No phone changes. Times are CEST.

| | ours | Derek |
|---|---|---|
| tree | sm8750-mainline `v6.16`, base `16cf517b`, + 50 patches (`kernel/patches/`) | github.com/derekross/linux-omarchy-mobile `omamobile` @ `2a7b29c24` (2026-10-20 20:31) |
| base | 6.16.0 + sm8750-mainline board work (dodge DTS, AA569 panel, syna_tcm2, `sm8750.config`) | Linux **7.3-rc6** (`62b3c799e`) + **152 commits** |
| Qualcomm commits on top | 50 | **0**: all 152 are Google gs101/gs201 (Pixel 7 Pro/Fold): 52 arm64 DTS, 39 bindings, clk/drm/media/mfd/phy/power for Tensor |

So "SM8750 in Derek's tree" means **SM8750 in mainline 7.3-rc6**. Derek has no
dodge or OnePlus code. The repo's CONTRIBUTING sends kernel PRs to his
`omamobile` branch, one subsystem per topic branch. `omamobile-int` is his
integrated snapshot.

Worktree: `~/android/mainline/wt-omamobile` (shallow, shares `wt-dodge`'s object
store). The trial results are on the local branch `trial/omamobile-dodge-port`,
which is never pushed. `wt-dodge` was not touched.

## 1. SM8750 support in 7.3-rc6 vs our 6.16 base

`sm8750.dtsi`: 7129 lines in 7.3-rc6 vs 4702 lines in our base.

| Area | 7.3-rc6 | our base |
|---|---|---|
| MDSS / DPU / DSI ctrl + 3nm PHY | yes | yes |
| ADSP / CDSP / MPSS PAS remoteprocs, SoCCP | yes | yes |
| ADSP FastRPC with remote heap + LPASS/ADSP_HEAP vmids | **yes** (= our 0023/0024) | via our patches |
| AudioReach (GPR/q6apm/q6prm), LPASS, SoundWire | yes | yes |
| UFS, USB (now **flattened dwc3**: `&usb`, `usb_dwc3_hs`, `usb_hsphy`) | yes | yes (old `usb_1*` labels) |
| PCIe (one controller) | yes | yes |
| tsens | **yes** (55 refs) | no |
| Iris video (`qcom,sm8750-iris`, `iris_platform_sm8750.h`) | **yes** | no |
| CPU OPP tables | 9 | 6 |
| GPU: Adreno 830 in `a6xx_catalog` (chip 0x44050a01, ADRENO_8XX_GEN1), `gpucc-sm8750` | **driver + clocks yes, no GPU/GMU DT node** | no |
| camcc / videocc / cambistmclkcc for SM8750 | yes | no |
| IPA | no (v5.5 data only; SM8750 is v5.5.2) | no |
| rmtfs_mem, pmic-glink/battmgr, WCN/BT nodes | no (board-level) | no (ours in dodge DTS) |
| SM8750 boards | MTP, QRD | MTP, QRD, **dodge** |
| pd-mapper `qcom,sm8750` | yes (= our 0021) | via our patch |
| RSC v4 | yes (= our 0002) | via our patch |

Drivers mentioning sm8750 (7.3-rc6): interconnect, eusb2/qmp-combo/qmp-pcie/qmp-ufs
PHYs, PAS remoteproc, llcc, pd_mapper, socinfo, ubwc_config, msm/adreno, iris,
and clocks (gcc, tcsrcc, dispcc, gpucc, camcc, videocc, cambistmclkcc).

**ath12k:** 7.3 has the `wifi7/` split and native **QCC2072**
(PCI 0x1112): `hal_qcc2072.c`, window register `0x3278`, `download_aux_ucode`,
`rfkill_pin = 0`, QDSS-cfg-miss feature bit, single pdev. **WCN7860/peach
(0x110e) and the MHI TME two-ELF load are absent.** hci_qca has no WCN7860 either.

## 2. Our 50 patches on 7.3-rc6

Method:
1. Committed a **prereq** carrying the base's board files: dodge DTS, AA569 panel,
   syna_tcm2, `sm8750.config`, plus their Kconfig/Makefile lines.
2. Ran `git am --3way` over the series in order (a failed patch is skipped).
3. Ran each conflicting patch on its own against the prereq to count conflict hunks.

Raw result: **17 apply, 3 "no changes" (already in), 30 conflict.**

| # | patch | git am | class |
|---|---|---|---|
| 0001 | dodge: ABL board ids | applies | applies |
| 0002 | rpmh-rsc v4 | no change | **present** |
| 0003 | nvmem-reboot-mode 1-byte cell | 2 hunks | **obsolete** (7.3 writes `buf_len` bytes; only our `!buf_len` guard is extra) |
| 0004 | build syna_tcm2 SPI | 1 hunk (Makefile) | conflicts (trivial; prereq overlap) |
| 0005 | dodge: WCN PMU | applies | applies |
| 0006 | ath12k: PCI id 0x110e | 2 | conflicts (port to `wifi7/pci.c`) |
| 0007 | ath12k: window reg 0x3278 | 6 | **obsolete** (QCC2072 path already uses 0x3278; just map 0x110e onto it) |
| 0008 | mhi: two-ELF TME image | 2 (boot.c, pm.c) | conflicts (not upstream) |
| 0009 | ath12k: 0x110e TME flag | applies | applies (needs 0008) |
| 0010 | peach TME-Lite patch | 8 | conflicts (252+ lines) |
| 0011 | peach host DMA window | 1 | conflicts |
| 0012 | no full DMA aperture | 2 | conflicts |
| 0013 | DMA in low 256 MiB | applies | applies |
| 0014 | ddr_range unset | 2 | conflicts |
| 0015 | skip TME-Lite download | 2 | conflicts |
| 0016 | PHY + aux ucode | 6 | conflicts (aux part now upstream; PHY ucode remains) |
| 0017 | aux ucode only when advertised | 3 | conflicts / mostly obsolete (upstream `download_aux_ucode`) |
| 0018 | QDSS trace config | 1 | conflicts |
| 0019 | record fw crash | 1 | conflicts |
| 0020 | mission mode | 1 | conflicts |
| 0021 | pd-mapper SM8750 | no change | **present** |
| 0022 | pas only_adsp | 1 | conflicts (small; no `only_adsp` upstream) |
| 0023 | ADSP FastRPC DT | conflict | **obsolete** (in 7.3 dtsi) |
| 0024 | fastrpc audio-PD remote heap | conflict | **obsolete** (7.3 allocates, SCM-assigns and passes the heap; verify on boot) |
| 0025 | q6apm I2S set_fmt | 1 | **obsolete** (7.3 has `q6i2s_set_fmt` on the I2S DAIs) |
| 0026 | dodge: enable speaker | applies | applies |
| 0027 | dodge: add speaker | applies | applies |
| 0028 | sc8280xp: I2S fmt on MI2S | applies | applies |
| 0029 | dodge: sound card | applies | applies |
| 0030 | Awinic aw882308 codec | 1 (Makefile) | conflicts (trivial) |
| 0031 | sc8280xp: no jack on MI2S | applies | applies |
| 0032 | dodge: WCD939x | applies | applies |
| 0033 | dodge: USB-C headset | applies | applies |
| 0034 | aw882308 receiver profile | fails (needs 0030) | conflicts (cascade) |
| 0035 | peach QDSS not missing | 1 | conflicts (overlaps upstream QDSS-cfg-miss bit) |
| 0036 | peach no rfkill | applies | applies, **obsolete** if WCN7860 clones QCC2072 params (`rfkill_pin = 0`) |
| 0037 | single-phy hw mode/channel list | 1 (wmi.c) | conflicts |
| 0038 | WCN7860 register table | conflict | **obsolete** (QCC2072 HAL upstream) |
| 0039 | QCC2072 RX descriptor | conflict | **obsolete** |
| 0040 | 32-bit TLV REO rings | conflict | **obsolete** |
| 0041 | QCC2072 RX DMA ring config | conflict | **obsolete** |
| 0042 | WCN7860 hw params | 1 | conflicts → becomes a small `wifi7/hw.c` entry cloned from QCC2072 |
| 0043 | BT qca WCN7860 | 5 | conflicts |
| 0044 | dodge: Bluetooth | applies | applies |
| 0045 | dodge: panel VCI | applies | applies |
| 0046 | AA569 panel cmd mode | applies | applies |
| 0047 | dsi: round 6G byte clock | applies | **present** (7.3 `dsi_link_clk_set_rate_6g` already rounds; textual apply would duplicate it) |
| 0048 | dsi: round after reparent | applies | **present** (7.3 has the rounding + `byte_intf_clk_div_2`; drop after review) |
| 0049 | dsi: drop opp_set_rate(0) | no change | **present** |
| 0050 | mdss: keep GDSC on (SM8750) | 1 | conflicts (small; 7.3 uses shared `data_57k`, so SM8750 needs its own entry) |

**Totals by class:**

| class | count | patches |
|---|---|---|
| present | 6 | 0002, 0021, 0047, 0048, 0049, + 0003 effectively |
| obsolete | 11 | 0003, 0007, 0023, 0024, 0025, 0036, 0038–0041, 0017 (mostly) |
| applies and still needed | 14 | 0001, 0005, 0009, 0013, 0026–0029, 0031–0033, 0044–0046 |
| conflicts, needs port | 19 | 0004, 0006, 0008, 0010–0012, 0014–0016, 0018–0020, 0022, 0030, 0034, 0035, 0037, 0042, 0043, 0050 |

Present and obsolete overlap: 0003 and 0017 are counted once, and 0047/0048 are
"present". About **20 of 50 drop** and about 30 carry. **The Wi-Fi port is the bulk:**
13 peach patches with about 37 conflict hunks against the `wifi7/` layout, plus
0043 BT (5 hunks).

**Hidden base delta (not in our 50).** sm8750-mainline also carries:
- the dodge DTS;
- the AA569 panel driver;
- syna_tcm2 (3 files);
- `sm8750.config`;
- at least one DRM core change: `dsc_slice_per_pkt` in `mipi_dsi_device`.

7.3 does the same through `MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT`.
The shallow history means we can't list the whole sm8750-mainline delta against v6.16.

## Build-only tests (done)

- **dodge DTB compiles on 7.3-rc6** with 4 small DTS fixes:
  - `/delete-node/ &{/reserved-memory}`;
  - `&usb_1` + `&usb_1_dwc3` → `&usb`;
  - `usb_1_dwc3_hs`/`usb_1_hsphy` → `usb_dwc3_hs`/`usb_hsphy`;
  - re-add `adsp_rpc_remote_heap_mem` in the dodge reserved-memory, because dodge
    deletes the SoC's reserved-memory and 7.3's fastrpc node references it.
- With the 9 applying DT patches on top it also builds: 124 KiB, 0 errors, 0
  warnings, 32 `okay` nodes.
- **Drivers:**
  - AA569 panel: 1 error (`dsi->dsc_slice_per_pkt` doesn't exist; delete the line,
    since 1 is the 7.3 default).
  - syna_tcm2: 1 error (`linux/of_gpio.h` removed; needs the gpiod API).
  - Both are small fixes.
- No full kernel build and no boot.

## 3. Effort and risk to reach today's dodge feature set on 7.3

| Area | Work | Estimate | Risk |
|---|---|---|---|
| Board DTS + prereq | the 4 fixes above, plus the reserved-memory/USB/remoteproc review | 0.5 d | low–med (USB flattening, reserved-memory overlap with the new SoC nodes) |
| Display | AA569 fix, port 0050, drop 0047–0049; check the DSC/byte clock path on hardware | 0.5–1 d | **med–high**: display took many boots to get stable (PLL lock, GDSC, kickoff timeouts) |
| Touch | syna_tcm2 gpiod conversion, 0004 | 0.25 d | low |
| Wi-Fi (QCC2072 peach) | re-base 13 patches onto `wifi7/`; drop the 4 HAL backports and reuse upstream QCC2072 | 2–3 d | **high**: hard-won bring-up; regressions likely at first (TME, DMA window, mission mode) |
| BT | 0043 onto 7.3 hci_qca (5 hunks), plus 0044 | 0.5 d | med |
| Audio | 0028/0031 apply, port 0030/0034 Makefile, drop 0023–0025; verify the remote heap on 7.3 | 0.5–1 d | med |
| Sensors | userspace only (hexagonrpcd/libssc); needs the 7.3 fastrpc ADSP node (present) | ~0 | low |
| Modem | 0022 only_adsp (1 hunk), rmtfs_mem DT (not-applied/0002) | 0.25 d | low |
| Boot chain | stage 2 Image + DTB from 7.3 via `dodge-chain` (stage 1 stays 6.16); modules for 7.3 in rootfs | 0.5 d | low (one-shot `fastboot boot`, `boot_a` untouched) |

**Total: about 5–8 working days** to match today's features, most of it Wi-Fi and
display validation. It needs about 15–30 test boots, spread over several sessions
because the battery gates every reboot.

**Gains:**
- 7.3 base: tsens and thermal, Iris video, more OPPs, newer DRM/msm.
- Adreno 830 in the driver. The GPU still needs a GPU/GMU DT node and the zap/GMU
  firmware, a separate project of about 2–4 days.
- Upstream QCC2072 Wi-Fi to build on, which cuts our Wi-Fi delta roughly in half.
- Upstream fastrpc heap, pd-mapper and RSC v4.
- A tree Derek accepts PRs against.
- IPA: no gain. SM8750 v5.5.2 is still missing.

**Risks:**
- Wi-Fi and display regressions.
- An unknown remaining sm8750-mainline delta.
- 7.3-rc6 isn't a release, and Derek's branch is Pixel-focused (no Qualcomm CI).
- About a week without new features.

## 4. Configs and boot image

- `kernel/configs/omamobile.config` (Derek's, 219 `CONFIG_` lines): 77 match our
  running 6.16 config and 142 differ. About 34 of the differences are Pixel-only
  (Exynos/Tensor/Trusty/S5100/BCM/Mali). The other ~108 are generic, and can be
  turned on **in our 6.16 build too**, independent of the rebase:
  - **`SECURITY_LANDLOCK`**: n for us. This is why pacman needs `--disable-sandbox`.
  - Binder/binderfs (Waydroid).
  - nftables and xt matches, policy routing.
  - PSI, BOOT_CONFIG, dmabuf heaps, CMA 384 MB.
  - UFS inline crypto, F2FS.
- Our config has `BLK_DEV_DM=m` and `QCOM_SOCINFO=m`, but neither is loaded on the
  phone. That explains the missing `/dev/mapper/control` and `/sys/devices/soc0`.
  `EROFS_FS` isn't set.
- `kernel/configs/omamobile-dodge.config` is ours (88 lines, merged by
  `tools/dodge-try`, `KERNEL_DIR` defaults to `wt-dodge`). Derek's tree carries no
  dodge config. `sm8750.config` exists only in the sm8750-mainline base.
- **Boot image:** Derek's flow produces Pixel images. We don't need his boot.img
  format. Stage 1 (6.16 in `boot_a`, AVB footer) kexecs any arm64 `Image` plus DTB
  plus initramfs, so a 7.3 stage 2 drops into `tools/dodge-chain pack` through
  `STAGE2_IMAGE`/`STAGE2_DTB_IN`. Testing is one `fastboot boot` with no flash.

## Recommendation

**Don't switch wholesale now.** Stay on 6.16 for daily use and run the 7.3 port as a
**parallel, staged track**:

1. **Now, cheap, on 6.16:** enable Landlock and the generic `omamobile.config` items
   in our build, and load `socinfo` and `dm-mod`.
2. **7.3 stage 2, minimal:** board DTS fixes + panel/touch fixes + display (0050) +
   modem (0022). One-shot `fastboot boot`, with the 6.16 stage 1 and fallback kept.
   Prove display, touch and USB first.
3. **Then audio, then BT, then Wi-Fi** (re-base peach onto upstream QCC2072), one
   per session.
4. **Then upstream:** open topic-branch PRs against `omamobile` (dodge DTS, AA569
   panel, ath12k WCN7860, BT, mdss GDSC). Only after
   Martin's explicit go: nothing is pushed to Derek or sm8750-mainline.

Do it once 7.3 is final, or right away if the GPU is the next goal, since Adreno 830
needs the 7.3 driver.
