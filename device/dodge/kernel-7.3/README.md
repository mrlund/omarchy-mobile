<!-- SPDX-License-Identifier: MIT -->
# dodge on Linux 7.3 (staged port, local only)

A backup of the local branch `trial/omamobile-dodge-port` in
`~/android/mainline/wt-omamobile`. It is based on Derek's `omamobile` @
`2a7b29c24` (7.3-rc6). Nothing is pushed to any kernel remote.

**Full export (2026-10-24 19:03 CEST):** `0001`-`0066` is
`git format-patch --zero-commit 2a7b29c24..f08f72d3e`, the whole branch
with no gaps.
- Verified: `git am` of all 66 onto a clean `2a7b29c24` worktree gives tree
  `7c17c0d04d40`, the same as `f08f72d3e`; `git diff` is empty.
- A host bundle is in `~/android/mainline/backups/`.

The re-export renumbers the tail. The older numbers in NOTES and the
dev-docs map like this:
- **Old 0052 is new 0060:** pcie-qcom, 2-cell iommu-map.
- **Old 0053 is new 0061:** ath12k regd completion.
- **Old 0054-0058 are new 0062-0066:** the GPU.
- **New 0052-0059:** four trial or debug commits (pcie Gen2 limit, iATU dump,
  config_sid debug), each followed by its revert. They net to zero.

- `0001` PREREQ: the sm8750-mainline 6.16 board files (dodge DTS with the four
  7.3 DTS fixes, AA569 panel, syna_tcm2, `sm8750.config`).
- `0002`-`0016`: the dodge patches that applied as is (the git am trial in
  `dev-docs/2026-10-21-kernel-ours-vs-omamobile.md`).
- `0017`-`0021`: the stage 1 ports. syna_tcm2 builds as an SPI driver and
  uses a gpiod lookup. The panel drops `dsc_slice_per_pkt`. 0050 (MDSS GDSC)
  and 0022 (only_adsp) are ported. `rmtfs_mem` is added. The DSI RGB888
  command format is a workaround.
- `0022`-`0024` (stage 2): the aw882308 bring-up driver and its Receiver
  profile, and a fastrpc log line that `rootfs/audio-bringup.sh` waits for.

- `0029`-`0030` (2026-10-24): drop the 0050 GDSC keep-on, port the 0054 QTB read.
- `0031`-`0034` (2026-10-24): revert the DIAG commits (0025, 0027, 0028) and 0026 (splash identity map); none is needed.
- `0035` (2026-10-24): aw882308 unmutes from trigger; on 7.3 AudioReach starts the BE graph (BCLK) in trigger, not prepare.
- `0036`-`0050` (2026-10-24): Wi-Fi (peach, WCN7860, PCI 0x110e). 0036 adds WCN7860 to the 7.3 wifi7 driver as a clone of the native QCC2072 entry (replaces 6.16 0006/0007/0038-0042). 0037 reworks the MHI lost-EE fix onto 7.3's two-ELF boot.c. 0038 and 0050 revert two older commits that 7.3 makes obsolete (the TME flag, and the rfkill skip). 0039-0049 are the 6.16 QMI bring-up, with the 6.16 aux-ucode code replaced by upstream's. Not boot-tested yet.
- `0051` (2026-10-24): Bluetooth qca WCN7860 (hci_uart, built in). Not boot-tested yet.
- `0052`-`0059`: trial/debug commits and their reverts (net zero).
- `0060` (was 0052, 2026-10-24): pcie-qcom config_sid parses the 2-cell `iommu-map` (sm8750 `#iommu-cells = <2>`). Without it, the endpoint MSIs carry the root port's ITS DeviceID and Wi-Fi BHI times out. Boot-tested: Wi-Fi connects.
- `0061` (was 0053, 2026-10-24): ath12k signals `regd_update_completed` on the rejected-country (DROP) path of `ath12k_reg_chan_list_event()`; before, `pdev_idx` stayed 255 there, so `ath12k_regd_update()` waited the full timeout and logged "Timeout while waiting for regulatory update". Boot-tested (regfix1): the timeout line is gone, Wi-Fi connects. Upstream candidate (not sent).
- `0062`-`0066` (was 0054-0058, 2026-10-24): Adreno 830 (gpucc/gxclkctl/SMMU, GPU/GMU nodes, a8xx catalog, dodge enable, RSCC reg range). Flashed default since 18:44.
- `0025`-`0028`: display-drop work. 0025, 0027 and 0028 are DIAG (not for
  upstream); 0026 keeps the splash identity-mapped in msm's IOMMU domain.
  See `dev-docs/2026-10-21-display-drop.md`.

`rootfs/omamobile-display-diag` and `rootfs/omamobile-kmsg-sync` (plus
`.service`) are 7.3-only diagnostics (`ConditionKernelVersion=7.3*`).

`rootfs/audio-bringup.sh` is the 7.3 copy in `/usr/local/lib/omamobile.<R>/`:
no `audio_heap_vmids` parameter (7.3 assigns the heap itself) and
`snd-soc-wcd-common` added.

Config: `config-7.3.0-rc6-dodge-s1` = `../kernel/config-6.16.0-gbd9587d65`
→ olddefconfig on 7.3, then `omamobile-generic-73.config` (the generic part
of `kernel/configs/omamobile.config`), then `../kernel/generic-2026-10-21.config`,
then `dodge-73-extra.config` (Gunyah watchdog, panic on lockup, legacy
iptables, ATH12K=m).

```sh
make O=../out-omamobile-73 ARCH=arm64 LLVM=1 KERNELRELEASE=7.3.0-rc6-dodge-s1 \
     Image modules qcom/sm8750-oneplus-dodge.dtb
# modules_install INSTALL_MOD_STRIP=1 → phone /usr/lib/modules/<R>.held;
# tools/dodge-kmod-overlay-tree → /usr/local/lib/omamobile.<R>, plus
# skip-units-<R> as its skip-units file.
```

GPU kernel `7.3.0-rc6-dodge-gpu1` (2026-10-24, flashed default since 18:44 CEST):
the same tree as s1 plus patches 0062-0066 (formerly 0054-0058). Its config is `config-7.3.0-rc6-dodge-gpu1`, which is
`config-7.3.0-rc6-dodge-s1` plus `dodge-73-gpu.config` (`CONFIG_SM_GPUCC_8750=y`;
that is the only diff). The skip-units file is `skip-units-7.3.0-rc6-dodge-gpu1`,
a copy of the s1 one. It is built in `out-omamobile-73-gpu` with
`KERNELRELEASE=7.3.0-rc6-dodge-gpu1`. It has its own release and module tree
(`/usr/lib/modules/7.3.0-rc6-dodge-gpu1.held` and
`/usr/local/lib/omamobile.7.3.0-rc6-dodge-gpu1`), so the s1 tree that the
current flashed default uses stays untouched.

Boot (one-shot, never flashed), with the 6.16 stage 1 unchanged:

```sh
CHAIN_OUT=~/android/mainline/out-dodge-chain-73 STAGE2_OUT=~/android/mainline/out-dodge \
STAGE2_IMAGE=.../out-omamobile-73/arch/arm64/boot/Image \
STAGE2_DTB_IN=.../out-omamobile-73/arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dtb \
DTB_OPTS='splash fb' STAGE2_CMDLINE="<same as 6.16>" tools/dodge-chain pack
fastboot boot ~/android/mainline/out-dodge-chain-73/images/boot-chain.img
```

Results: `../dev-docs/2026-10-21-kernel-7.3-stage1.md`.

## PR branch omamobile-dodge (2026-10-25)

Local branch `omamobile-dodge` in `wt-omamobile` (not pushed anywhere), the
clean form of `trial/omamobile-dodge-port` (f08f72d3e, kept untouched) for a
later PR to Derek. Patches: [../kernel-7.3-pr/](../kernel-7.3-pr/).

- Base: Derek's `omamobile` at `97a6b87a8` ("Input: synaptics-tcm: Enable
  analog supply before digital supply"), 41 commits past 2a7b29c24. All 41 are
  Google Tensor/Samsung (gs101/gs201/zuma: clk, pinctrl, UFS, PMIC, SPI,
  watchdog, panthor, synaptics_tcm). Nothing we carry is in it (no SM8750 GPU
  nodes, no A830 catalog, no PCIe iommu-map fix, no ath12k, no sm8750 dts).
  Replay had zero conflicts.
- HEAD: `fa412839e`, 41 commits. Author and Signed-off-by: Martin Lund.
- Classification: (a) generic upstream-Linux candidates, self-contained and
  first; (b) dodge for Derek, on top of (a).

| # | class | subject | from trial |
|---|---|---|---|
| 1 `8b1ad529d` | a | PCI: qcom: parse iommu-map with a 2-cell IOMMU specifier in config_sid | 0060 |
| 2 `5ae997e76` | a | wifi: ath12k: complete regd_update_completed when a country change is rejected | 0061 |
| 3 `79cd16072` | a | arm64: dts: qcom: sm8750: add gpucc/gxclkctl/adreno-smmu | 0062 |
| 4 `5e0b51c2a` | a | arm64: dts: qcom: sm8750: add Adreno 830 GPU and GMU nodes | 0063+0066 |
| 5 `a3c3519ba` | a | drm/msm/adreno: add the Adreno 830 catalog entry | 0064 |
| 6 `59c6441a1` | b | arm64: dts: qcom: add the OnePlus 13 | 0001 (dts) |
| 7 `145846799` | b | arm64: configs: add an sm8750.config fragment for the OnePlus 13 | 0001 (config) |
| 8 `1ee19e5f2` | b | drm/panel: add the AA569 DSC command-mode panel of the OnePlus 13 | 0001 (panel)+0018+0016 |
| 9 `1c1546f28` | b | Input: add a Synaptics TCM2 SPI touchscreen driver | 0001 (touch)+0017 |
| 10 `0df813618` | b | arm64: dts: qcom: sm8750-oneplus-dodge: add ABL board ids | 0002 |
| 11 `bdbf39920` | b | arm64: dts: qcom: sm8750-oneplus-dodge: enable the WCN PMU | 0003 |
| 12 `d78ccb11e` | b | wifi: ath12k: keep peach DMA inside the low 256 MiB | 0005 |
| 13 `39bda7042` | b | arm64: dts: qcom: sm8750-oneplus-dodge: enable the speaker amplifier bus | 0006 |
| 14 `86e4875b6` | b | arm64: dts: qcom: sm8750-oneplus-dodge: add the speaker amplifiers | 0007 |
| 15 `d7696fbf2` | b | ASoC: qcom: sc8280xp: set the I2S format on MI2S back ends | 0008 |
| 16 `8e4b6238e` | b | arm64: dts: qcom: sm8750-oneplus-dodge: add the sound card | 0009 |
| 17 `7501dfb00` | b | ASoC: qcom: sc8280xp: no headset jack on MI2S links | 0010 |
| 18 `196a4328d` | b | arm64: dts: qcom: sm8750-oneplus-dodge: add the WCD939x and microphones | 0011 |
| 19 `8df57b7c3` | b | arm64: dts: qcom: sm8750-oneplus-dodge: add the USB-C headset path | 0012 |
| 20 `b1748d623` | b | arm64: dts: qcom: sm8750-oneplus-dodge: enable Bluetooth | 0014 |
| 21 `a594124c7` | b | arm64: dts: qcom: sm8750-oneplus-dodge: set the panel VCI rail to 3.0 V | 0015 |
| 22 `4a097fe32` | b | remoteproc: qcom: pas: add an only_adsp bring-up switch | 0019+0029 |
| 23 `1f5624624` | b | arm64: dts: qcom: sm8750-oneplus-dodge: add rmtfs_mem | 0020 |
| 24 `f0cec0959` | b | drm/msm/dsi: keep the RGB888 command DST format with DSC | 0021 |
| 25 `8dd6e626b` | b | ASoC: codecs: add a bring-up driver for Awinic 0x2308 amplifiers | 0022+0035 |
| 26 `a0e62c945` | b | ASoC: codecs: aw882308: add the Receiver profile | 0023 |
| 27 `b7dceced4` | b | drm/msm/mdss: sm8750: read the display QTB once on every MDSS enable | 0030 |
| 28 `8db48c3e9` | b | wifi: ath12k: add WCN7860 (PCI 0x110e, peach) on the QCC2072 HAL | 0036 |
| 29 `b29ce0917` | b | bus: mhi: host: continue from BHI_EXECENV when the EE event is lost | 0037 |
| 30 `1e666fe58` | b | wifi: ath12k: send the peach TME-Lite patch before board data | 0039 |
| 31 `6f55ba8bb` | b | wifi: ath12k: send the peach host DMA window | 0040 |
| 32 `d176e9048` | b | wifi: ath12k: do not advertise the full peach DMA aperture | 0041 |
| 33 `1d6ef7ac9` | b | wifi: ath12k: leave peach ddr_range unset | 0042 |
| 34 `38e57ae7f` | b | wifi: ath12k: allow skipping the peach TME-Lite download | 0043 |
| 35 `4afc174df` | b | wifi: ath12k: download the peach PHY ucode as its M3 | 0044 |
| 36 `1e9090598` | b | wifi: ath12k: download the peach QDSS trace config | 0045 |
| 37 `4d20021dc` | b | wifi: ath12k: record the peach firmware crash | 0046 |
| 38 `ac08c3d21` | b | wifi: ath12k: bring peach up in mission mode | 0047 |
| 39 `65f486f96` | b | wifi: ath12k: do not tell peach the QDSS config is missing | 0048 |
| 40 `8a75d465a` | b | Bluetooth: qca: add WCN7860 support | 0051 |
| 41 `fa412839e` | b | arm64: dts: qcom: sm8750-oneplus-dodge: enable Adreno 830 GPU | 0065 |

Notes on the classes:
- (a) 3-5 (gpucc/SMMU, GPU+GMU nodes, A830 catalog) are backports of ROCKNIX
  patches from pending upstream series (Teguh Sobirin, upstream "drm/msm:
  Support for Adreno 830 GPU" and the sm8750 gpucc DT series). Upstream they
  should land through those series with original authorship, not as ours;
  drop them here once they reach Derek's base. 1 (PCI qcom) and 2 (ath12k)
  are our own fixes.
- (b) also holds driver work that is generic in shape but not ready for
  upstream: the peach/WCN7860 ath12k series (12, 28, 30-39), the MHI lost-EE
  fix (29), Bluetooth WCN7860 (40), the AW882308 amp driver (25-26), the
  sc8280xp MI2S tweaks (15, 17), the DSI RGB888 workaround (24) and the
  only_adsp bring-up switch (22, not for upstream).

Dropped from the trial (all intentional): DIAG/debug 0025, 0027, 0028 and
reverts 0031-0033; 0026 + revert 0034 (splash identity map); 0004 + revert
0038 (TME flag); 0013 + revert 0050 (rfkill); trial pairs 0052-0059 (pcie0
lane/speed, iATU dump, debug config_sid); debug-only logging 0024 (fastrpc
heap dev_info) and 0049 (ath12k hw-mode ath12k_info). Squashed: 0066 into
0063, 0018/0016 into the panel, 0017 into touch, 0029 into 0019 (the GDSC
keep-on and its removal cancel; only the remoteproc part is left), 0035 into
0022. 0001 (PREREQ) is split into dts, config, panel and touch.

Tree vs trial: `git diff trial/omamobile-dodge-port omamobile-dodge -- arch/arm64/boot/dts`
is empty and the dtb built from the branch is byte-identical to the gpu1 dtb.
`-- drivers` shows only the two dropped log calls (fastrpc.c, ath12k wmi.c)
and Derek's synaptics_tcm.c change from his new base (that driver is not
built in our config). The Image symbol diff is only Derek's Samsung code
(zumapro clk initcall, exynos initcall line numbers) and erratum veneer
addresses.

checkpatch (`format-patch` + `checkpatch.pl --strict`), remaining:
- 1-3, 10, 12, 13, 15, 16, 21-24, 28, 41: clean.
- 4, 14, 20, 25, 40: undocumented DT compatibles (adreno-44050000,
  adreno-gmu-830.1, awinic,aw882308, qcom,wcn7860-bt). Bindings patches are
  needed before upstream.
- 6 (dodge dts, 6 E/16 W), 8 (panel, 4 E/10 W), 9 (syna_tcm2 vendor driver,
  54 E/73 W/148 C), 25 (aw882308, 6 E): whitespace/indent/brace style from
  the carried 6.16 files. Needs a style pass before the PR; the touch driver
  is vendor code and needs the most work.
- 11, 17-19, 25, 26, 30: `Co-Authored-By: Grok` trailer (non-standard for
  the kernel; Martin decides on keeping or changing it, e.g. Assisted-by).
- 29-40: messages say "Ported from the dodge v6.16 bring-up tree" (the
  private 6.16 shas were removed); a few lines over 75 chars, one CHECK each.
- 5: uint32_t vs u32 (matches the surrounding catalog code); 7, 8, 25:
  MAINTAINERS/Kconfig-help warnings.

Build: full `make O=../out-omamobile-73-pr ARCH=arm64 LLVM=1
KERNELRELEASE=7.3.0-rc6-dodge-gpu1 Image modules qcom/sm8750-oneplus-dodge.dtb`
with config-7.3.0-rc6-dodge-gpu1 at HEAD: OK (one existing warning, unused
ath12k_qmi_process_coldboot_calibration). Per-commit check (touched .o files
and the dodge dtb, config reset to gpu1 before each step) started 09:25 CET,
results in `~/android/mainline/pr-work/bisect.out`; commits 1-6 OK at the time
of writing. For 3-4 the dodge dtb does not exist yet, so they still need a
`qcom/sm8750-mtp.dtb` build. Not boot-tested.

Before the PR (needs Martin): style pass on 6/8/9/25, the Co-Authored-By
trailers, DT bindings for the new compatibles, keep or drop only_adsp, push to
Martin's fork (gh login), and a boot test of the final branch.
