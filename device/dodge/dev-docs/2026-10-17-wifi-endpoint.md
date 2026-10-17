<!-- SPDX-License-Identifier: MIT -->
# 2026-10-17 — the Wi-Fi chip enumerates as 17cb:110e

**Goal.** Boot the device tree that enables the WCN power node, and
see whether an endpoint appears.
**Phone.** OnePlus 13 CPH2653. Omarchy desktop came back.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Pass. `lspci` shows `01:00.0` `17cb:110e` (rev 01).

## What we did

kexec from the running root failed twice the same way, including once
with a DTB built by `stage2-dtb.py`. Claude's reading was to stop that
and flash `boot_a`. The known-good image was copied aside
(`sha256` `5053f4d5…ee6f98`). The new chain image uses the same AVB
key (`28ca1e78…`). `DTB_OPTS` was `splash fb`, and the stage 2 cmdline
keeps `omamobile.ufs-probe` and `omamobile.userdata-rw`.

The PMU rails already match stock's `cnss-peach` limits: S3G
1.856–2.000 V, L2F and L3F fixed at 1.200 V and 1.800 V, and the SMPS
ranges cover stock's dig, aon and rfa2 windows. `pwrseq_wcn7850_vregs`
in this tree already requests `vddio1p2`.

`fastboot flash boot_a` of the footered image, then reboot. After SSH
returned, the modules were loaded in order: `pwrseq-core`,
`pwrseq-qcom-wcn`, `pci-pwrctrl-core`, `pci-pwrctrl-pwrseq`,
`phy-qcom-qmp-pcie`. The first `lspci` showed only the root port. A
rescan then showed the endpoint. `wcn7880-pmu` is bound to
`pwrseq-qcom_wcn`.

## What happened

`01:00.0` is `Network controller [17cb:110e] (rev 01)`. That is
stock's CNSS id, not the `0x1107` this tree's ath12k table claims.
ath12k was not loaded. The desktop service was active. The five
modules and a rescan are installed as `omamobile-wifi-pcie.service`
for the next boot. The known-good image is
`images/boot-chain-avb.known-good.img`.

## Learning

The 7850 power sequence is enough to put this chip on the bus. The
driver id to add next is `0x110e`. The first bus scan can run before
the sequencer has finished, so a rescan is part of the bring-up.
kexec from the Omarchy root stays off the list: two tries froze on
`Starting the new kernel` and left the USB network with no carrier.
