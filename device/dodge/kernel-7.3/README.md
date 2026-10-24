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
