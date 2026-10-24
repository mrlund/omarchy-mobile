<!-- SPDX-License-Identifier: MIT -->
# dodge on Linux 7.3 (staged port, local only)

A backup of the local branch `trial/omamobile-dodge-port` in
`~/android/mainline/wt-omamobile`. It is based on Derek's `omamobile` @
`2a7b29c24` (7.3-rc6). Nothing is pushed to any kernel remote.

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
- `0052` (2026-10-24): pcie-qcom config_sid parses the 2-cell `iommu-map` (sm8750 `#iommu-cells = <2>`). Without it, the endpoint MSIs carry the root port's ITS DeviceID and Wi-Fi BHI times out. Boot-tested: Wi-Fi connects.
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

Boot (one-shot, never flashed), with the 6.16 stage 1 unchanged:

```sh
CHAIN_OUT=~/android/mainline/out-dodge-chain-73 STAGE2_OUT=~/android/mainline/out-dodge \
STAGE2_IMAGE=.../out-omamobile-73/arch/arm64/boot/Image \
STAGE2_DTB_IN=.../out-omamobile-73/arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dtb \
DTB_OPTS='splash fb' STAGE2_CMDLINE="<same as 6.16>" tools/dodge-chain pack
fastboot boot ~/android/mainline/out-dodge-chain-73/images/boot-chain.img
```

Results: `../dev-docs/2026-10-21-kernel-7.3-stage1.md`.
