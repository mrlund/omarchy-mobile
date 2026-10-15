<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — mainline dodge DTB against the stock ids

**Goal.** Clone `sm8750-mainline`, confirm `sm8750-oneplus-dodge.dtb`
builds, and compare it with the stock ids, watchdog and USB controller
from the OTA.
**Phone.** Not touched. CPH2653, build `CPH2653_16.0.10.501(EX01)`.
**Kernel.** No kernel of ours has booted. The tree under comparison is
`sm8750-mainline` `v6.16` at `16cf517b2781`.
**Result.** Pass for the build. The DTB does not carry stock's
`qcom,msm-id` or `qcom,board-id`, and it has no watchdog node.

## What we did

`sm8750-mainline/linux` HEAD is branch `v6.16`. `master` on that
repository is older and has no dodge board. `OnePlus-13-WIP` is also
older (2025-08-06) and does have a dodge board. `v6.16` is the newest
and is the branch the plan names.

Cloned depth 1 into `~/android/mainline/wt-dodge` and created local
branch `omamobile-dodge` at `16cf517b2781`. Nothing was pushed.

Built with the system clang, 22.1.8, into `~/android/mainline/out-dodge`:

```text
make O=~/android/mainline/out-dodge ARCH=arm64 LLVM=1 defconfig
make O=~/android/mainline/out-dodge ARCH=arm64 LLVM=1 qcom/sm8750-oneplus-dodge.dtb
```

The DTB is 87477 bytes. A decompile warns that `/memory` has no unit
name and that several GENI QUP nodes share unit addresses. The build
itself completed.

Stock comparison used the sun base and the dodge overlays already
unpacked from the EU OTA
([2026-10-15-ota-boot-images](2026-10-15-ota-boot-images.md)).

Linux 7.3-rc7 (torvalds `master`, read the same day) has
`sm8750-mtp.dtb` and `sm8750-qrd.dtb` only. `sm8750-oneplus-dodge.dts`
is not there.

## What happened

The built DTB's root is `model = "OnePlus 13"`,
`compatible = "OnePlus,13", "qcom,sm8750"`. There is no `qcom,msm-id`
and no `qcom,board-id`. Stock's dodge overlays use
`qcom,board-id = <0x40008 0x00>` and eight sun/sunp msm-id pairs. Those
pairs were not collapsed to one value.

USB matches the controller named in stock's bootconfig
(`androidboot.usbcontroller=a600000.dwc3`):

| Node | compatible | status |
| --- | --- | --- |
| `usb@a6f8800` | `qcom,sm8750-dwc3`, `qcom,dwc3` | okay |
| `usb@a600000` | `snps,dwc3`, `dr_mode = "otg"` | inside the enabled wrapper |
| `phy@88e3000` | `qcom,sm8750-m31-eusb2-phy` | okay |
| `phy@88e8000` | `qcom,sm8750-qmp-usb3-dp-phy` | okay |

In this tree `qcom,dwc3` is the match for `dwc3-qcom-legacy.c`. The
newer `dwc3-qcom.c` matches `qcom,snps-dwc3`, which this DTB does not
list. Both PHY compatibles have drivers in the same tree. Upstream
7.3-rc7's `sm8750.dtsi` lists `qcom,sm8750-dwc3`, `qcom,snps-dwc3`
instead.

No watchdog node in `sm8750.dtsi` or in the dodge board, and none in
upstream 7.3-rc7's `sm8750.dtsi` either. Stock's sun base has
`/hypervisor/qcom,gh-watchdog` with a phandle and no other properties,
and every vendor FDT in the OTA has that empty node. No `compatible`
in those FDTs matches `qcom,apss-wdt` or any other watchdog driver.
The dodge overlay's `qcom,pmic-pon-log` lists `depends-on-supply =
<&gh_watchdog>`. Gunyah reserved regions in the stock sun base are
`0x80000000` size `0x1200000` and `0xbd930000` size `0x800000`.

The dodge board deletes the SoC `reserved-memory` node and supplies
its own. Its `hyp-region@80000000` is size `0xe00000` (14 MiB), smaller
than stock's Gunyah region at the same base. Stock's second Gunyah
region and the splash region at `0xfc800000` are not in this map. There
is no ramoops node.

The panel node on `&mdss_dsi0` is `compatible = "oneplus,dodge-panel"`.
That string is not one of the six names on stock's
`oplus,dsi-panel-primary` list.

## Learning

The first image can carry this DTB, and ABL's id match is still an open
suspect (§5.3 step 2). Do not write a single msm-id into it until the
live FDT says which sun variant this unit is. The board id to compare
against remains `<0x40008 0x00>`.

`QCOM_WDT` cannot arm anything with this DTB. The watchdog row of the
fast loop is absent. `panic=10` and a human are the way back from a
hang. Plan §5.1.

The reserved-memory map in this DTB is the board file's map, not the
OTA's. It is not a source for a ramoops address. A rooted `/proc/iomem`
is still the check before any region is copied.

Rebasing this checkout onto 7.3-rc7 is not a fast-forward. Upstream has
no dodge board, and its USB wrapper compatible changed. The local clone
is depth 1, so that rebase needs a real history first. It was left for
a later step.

Plan §5.1, §5.2, §6 phase 0c, §9.
