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

## PR branch omamobile-dodge (2026-10-25, pr1)

Local branch `omamobile-dodge` in `wt-omamobile` (not pushed anywhere), the
clean form of `trial/omamobile-dodge-port` (f08f72d3e, kept untouched) for a
later PR to Derek. Patches: [../kernel-7.3-pr/](../kernel-7.3-pr/).

- Base: Derek's `omamobile` at `97a6b87a8` ("Input: synaptics-tcm: Enable
  analog supply before digital supply"), 41 commits past 2a7b29c24, all
  Google Tensor/Samsung. Nothing we carry is in it. Replay had zero conflicts.
- HEAD: `0d65e1509`, 45 commits: the 41 of the first cut plus 4
  DT binding patches (3-6). Classes: (a) generic upstream candidates first,
  (b) dodge for Derek on top.

| # | class | author | subject | from trial |
|---|---|---|---|---|
| 1 `8b1ad529d` | a | Martin Lund | PCI: qcom: parse iommu-map with a 2-cell IOMMU specifier in config_sid | 0060 |
| 2 `5ae997e76` | a | Martin Lund | wifi: ath12k: complete regd_update_completed when a country change is rejected | 0061 |
| 3 `a3ed0c7fa` | a | Martin Lund | dt-bindings: display/msm/gpu: add the Adreno 830 (0x44050000) | new |
| 4 `0b51ef18b` | a | Martin Lund | dt-bindings: display/msm/gmu: add the Adreno 830 GMU | new |
| 5 `e89ab834e` | a | Martin Lund | ASoC: dt-bindings: add the Awinic AW882308 amplifier | new |
| 6 `9c103c665` | a | Martin Lund | dt-bindings: net: bluetooth: qcom: add WCN7860 | new |
| 7 `099b16bf9` | a | Martin Lund | arm64: dts: qcom: sm8750: add gpucc/gxclkctl/adreno-smmu | 0062 |
| 8 `5abff4386` | a | Teguh Sobirin | arm64: dts: qcom: sm8750: add Adreno 830 GPU and GMU nodes | 0063+0066 |
| 9 `079a91716` | a | Teguh Sobirin | drm/msm/adreno: add the Adreno 830 catalog entry | 0064 |
| 10 `3c270a815` | b | index986 | arm64: dts: qcom: add the OnePlus 13 | 0001 (dts) |
| 11 `4bda89670` | b | index986 | arm64: configs: add an sm8750.config fragment for the OnePlus 13 | 0001 (config) |
| 12 `e8446f58b` | b | index986 | drm/panel: add the AA569 DSC command-mode panel of the OnePlus 13 | 0001 (panel)+0018+0016 |
| 13 `e2d0bf36e` | b | index986 | Input: add a Synaptics TCM2 SPI touchscreen driver | 0001 (touch)+0017 |
| 14 `11c604814` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: add ABL board ids | 0002 |
| 15 `40c8ebdc6` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: enable the WCN PMU | 0003 |
| 16 `acceb2f1a` | b | Martin Lund | wifi: ath12k: keep peach DMA inside the low 256 MiB | 0005 |
| 17 `00016ede1` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: enable the speaker amplifier bus | 0006 |
| 18 `b37e70c38` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: add the speaker amplifiers | 0007 |
| 19 `ac2502bee` | b | Martin Lund | ASoC: qcom: sc8280xp: set the I2S format on MI2S back ends | 0008 |
| 20 `89c5b5ed4` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: add the sound card | 0009 |
| 21 `3bcb5c8bd` | b | Martin Lund | ASoC: qcom: sc8280xp: no headset jack on MI2S links | 0010 |
| 22 `93aaeeccf` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: add the WCD939x and microphones | 0011 |
| 23 `a833520fd` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: add the USB-C headset path | 0012 |
| 24 `e490e0d10` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: enable Bluetooth | 0014 |
| 25 `e42581b9c` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: set the panel VCI rail to 3.0 V | 0015 |
| 26 `465e0236a` | b | Martin Lund | remoteproc: qcom: pas: only_adsp bring-up workaround (not for upstream) | 0019+0029 |
| 27 `9e04d4333` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: add rmtfs_mem | 0020 |
| 28 `2272daffa` | b | Martin Lund | drm/msm/dsi: keep the RGB888 command DST format with DSC | 0021 |
| 29 `05cb79c53` | b | Martin Lund | ASoC: codecs: add a bring-up driver for Awinic 0x2308 amplifiers | 0022+0035 |
| 30 `2e4c1b1ea` | b | Martin Lund | ASoC: codecs: aw882308: add the Receiver profile | 0023 |
| 31 `685961088` | b | Martin Lund | drm/msm/mdss: sm8750: read the display QTB once on every MDSS enable | 0030 |
| 32 `e30929700` | b | Martin Lund | wifi: ath12k: add WCN7860 (PCI 0x110e, peach) on the QCC2072 HAL | 0036 |
| 33 `f9179bc2c` | b | Martin Lund | bus: mhi: host: continue from BHI_EXECENV when the EE event is lost | 0037 |
| 34 `1e4310be3` | b | Martin Lund | wifi: ath12k: send the peach TME-Lite patch before board data | 0039 |
| 35 `cfb3335d8` | b | Martin Lund | wifi: ath12k: send the peach host DMA window | 0040 |
| 36 `a48c82248` | b | Martin Lund | wifi: ath12k: do not advertise the full peach DMA aperture | 0041 |
| 37 `6cdde6c91` | b | Martin Lund | wifi: ath12k: leave peach ddr_range unset | 0042 |
| 38 `15ba7b639` | b | Martin Lund | wifi: ath12k: allow skipping the peach TME-Lite download | 0043 |
| 39 `aafb0103c` | b | Martin Lund | wifi: ath12k: download the peach PHY ucode as its M3 | 0044 |
| 40 `03f78f68c` | b | Martin Lund | wifi: ath12k: download the peach QDSS trace config | 0045 |
| 41 `c7212c35b` | b | Martin Lund | wifi: ath12k: record the peach firmware crash | 0046 |
| 42 `ee00e9759` | b | Martin Lund | wifi: ath12k: bring peach up in mission mode | 0047 |
| 43 `bb10be835` | b | Martin Lund | wifi: ath12k: do not tell peach the QDSS config is missing | 0048 |
| 44 `0d35c7379` | b | Martin Lund | Bluetooth: qca: add WCN7860 support | 0051 |
| 45 `0d65e1509` | b | Martin Lund | arm64: dts: qcom: sm8750-oneplus-dodge: enable Adreno 830 GPU | 0065 |

Authorship and trailers:
- 8-9 (GPU+GMU nodes, A830 catalog): author restored to Teguh Sobirin
  (ROCKNIX SM8750 patches 0038 and 0049). 8 keeps his Signed-off-by from the
  ROCKNIX patch; 0049 has none upstream, so 9 has no author SoB. Both carry a
  `Link:` to the ROCKNIX patch, a `[mrlund: ...]` backport note, then Martin's
  Signed-off-by.
- 7 (gpucc/gxclkctl/adreno-smmu): ROCKNIX patch 0033 has no personal author
  (project only) and no Signed-off-by, so Martin stays author; `Link:` and a
  `[mrlund: ...]` note added.
- 10-13 (dodge dts, sm8750.config, AA569 panel, Synaptics TCM2): author
  `index986` (from the sm8750-mainline/linux v6.16 history), `Link:` to that
  tree, `[mrlund: ...]` note (ported to 7.3, style fixes). The source has no
  Signed-off-by, so these have no author SoB (checkpatch NO_AUTHOR_SIGN_OFF).
- Every other commit is our own work (author Martin).
- The old `Co-Authored-By: Grok` trailers are gone. Commits with AI help carry
  `Assisted-by: Grok` before the Signed-off-by lines, the format in
  `Documentation/process/coding-assistants.rst` (3-6, 15, 21-23, 29-30, 34).
  That document also says the human submitter adds and certifies the
  Signed-off-by: Martin has to review each patch before sending it.
- 26 (only_adsp) is kept, marked "Bring-up workaround, not for upstream:" with
  why it is needed and what the proper fix is (keep the modem and CDSP nodes
  disabled in the board dts until they work). Drop it before submission.

DT bindings (3-6): `qcom,adreno-44050000` added to gpu.yaml's "clocks in the
GMU" list (not the two-region list: the SM8750 node has `cx_dbgc` too, which
the generic reg-names list allows); `qcom,adreno-gmu-830.1` shares the 840.1
clock rule in gmu.yaml; new `sound/awinic,aw882308.yaml` (aw88395.yaml
requires `awinic,audio-channel`, which this part does not use);
`qcom,wcn7860-bt` added to `qcom,wcn7850-bt.yaml`. `make dt_binding_check`
on the four files: clean. `CHECK_DTBS=y` on `sm8750-mtp.dtb`: clean. On
`sm8750-oneplus-dodge.dtb`: 22 board-level warnings, none from GPU, GMU, amp
or BT (undocumented `OnePlus,13`, `oplus,dhall-ak09970`,
`synaptics,tcm-spi-hbp`, `oneplus,dodge-panel` and their vendor properties,
the memory node's `ddr_device_type`, the sound card compatible, one TLMM
state).

Style pass (fixups autosquashed): dodge dts (whitespace, tabs, the long memory
`reg` split, a stale comment), panel (tabs), aw882308 (one statement per
line), syna_tcm2 (checkpatch `--fix-inplace` and whitespace). Errors left:
none apart from NO_AUTHOR_SIGN_OFF (9-13, see above). Warnings left: syna_tcm2
vendor code (BRACES 15, LONG_LINE 12, LEADING_SPACE 9, LINE_SPACING 9,
NEEDLESS_IF 6, SUSPECT_CODE_INDENT 3, CONSTANT_COMPARISON 2, NEW_TYPEDEFS 2,
MODULE_LICENSE 2, AVOID_EXTERNS, MACRO_ARG_UNUSED, TRAILING_SEMICOLON, plus
about 150 CHECKs), panel (CONFIG_DESCRIPTION, MSLEEP x2), aw882308
(CONFIG_DESCRIPTION), undocumented board compatibles in 10, MAINTAINERS
(FILE_PATH_CHANGES), and a few long lines, one typo and one OOM message in the
ath12k/BT patches.

Checks: per-commit build of all 45 (config reset to gpu1, touched `.o`, and
`qcom/sm8750-mtp.dtb` plus the dodge dtb for dts commits; doc-only commits
skipped): all OK; the only new warning is at 42 (peach mission mode leaves
`ath12k_qmi_process_coldboot_calibration` unused). Full build
at HEAD (`KERNELRELEASE=7.3.0-rc6-dodge-pr1`, config-7.3.0-rc6-dodge-gpu1):
OK, one existing warning (unused `ath12k_qmi_process_coldboot_calibration`).
The dodge dtb is byte-identical to the gpu1 dtb.

Trial image (never flashed): `TRIAL-7.3-pr1-boot_a.img`, packed like the gpu1
images (`dodge-chain pack`, 6.16 stage 1, usbfix1 stage-2 initramfs,
`DTB_OPTS='splash fb'`), cmdline without `dodge.flashed`, with `oops=panic
panic=10 hung_task_panic=1 softlockup_panic=1`. An AVB-footer copy
(`dodge-chain footer`) is `TRIAL-7.3-pr1-boot_a-avb.img`. Its modules are in
`~/android/mainline/stage-73-pr1/` (`lib/modules/7.3.0-rc6-dodge-pr1` for
`/usr/lib/modules/7.3.0-rc6-dodge-pr1.held`, `ovl/` for
`/usr/local/lib/omamobile.7.3.0-rc6-dodge-pr1`, `skip-units-7.3.0-rc6-dodge-pr1`
a copy of the gpu1 one). Not boot-tested.

Before the PR (needs Martin): review and certify each Signed-off-by, the
syna_tcm2 warnings, bindings for the board compatibles, drop 26, a boot test,
then push to his fork.
