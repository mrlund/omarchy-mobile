<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — SSH from our kernel, our DTB, our initramfs

**Goal.** Phase 3's pass: `ssh root@172.16.42.1` from a kernel we
built, with nothing flashed.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 2 `6.16.0-g02a028467db0-dirty` (`out-dodge`; the dirt
is temporary `pr_err` markers in `rpmh-rsc.c`, since dropped). Stage 1
the chain-loader with `kexec -c`.
**Result.** Pass. `1d6b:0104` and SSH 27 s after `Booting OKAY`.

## What we did

The first chain boot with `kexec_load`
([2026-10-16-fastboot-boot-kexec-file-load.md](2026-10-16-fastboot-boot-kexec-file-load.md)):
`DTB_OPTS=""` (the dodge DTB with the live `/memory` map only),
`tools/dodge-try`'s initramfs, `CONFIG_SM_TCSRCC_8750=y`.
`tools/dodge-chain boot` with `CHAIN_OUT=~/android/mainline/out-dodge-rdinit`.
`boot-v4-kexec-c-ssh.img`, 58404864 bytes, sha256
`b9b0066364b04d6912170900ba3f4cd87916d59b172ebe007daae45bd18db487`.
Before it, one probe boot on the same chain came back at 271 s with
the "our DTB" and "UDC exists" bits set.

## What happened

| t after `Booting OKAY` | USB |
| --- | --- |
| 0 s | `18d1:d00d` (fastboot) |
| 1 s | nothing |
| 27 s | `1d6b:0104`, laptop has 172.16.42.2, SSH answers |

From the phone (full log in `logs/dodge-chain-ssh-20261016-103137.dmesg`):

```
Machine model: OnePlus 13
Kernel command line: rdinit=/init clk_ignore_unused pd_ignore_unused panic=10 console=tty0
qcom-eusb2-repeater c400000.spmi:pmic@7:phy@fd00: Registered Qcom-eUSB2 repeater
qcom-m31eusb2-phy 88e3000.phy: Registered M31 USB phy
omamobile: USB gadget up on a600000.usb
```

The RSC reads version 3.8, `max_tcs=8`, `ncpt=16`. The UDC is
`a600000.usb` at `high-speed`, with `dr_mode = "otg"` and
`usb-role-switch` as in the DTS. `devices_deferred` holds only
`1c00000.pcie` (its PHY) and `aux_bridge.aux_bridge.0`. The interconnects'
`sync_state()` waits on `1d84000.ufs` (UFS is a module). Still up at
63 s, past the regulator core's unused-rail cleanup.

From about 20 s the log fills with SMMU faults:

```
arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402, iova=0xfc862900, fsynr=0x3f0021, cbfrsynra=0x800, cb=5
```

SID 0x800, IOVAs inside ABL's splash buffer (`0xfc800000`, 0x2b00000).
That is the display engine still scanning out the splash, now behind an
SMMU our kernel owns with no mapping for that stream (`DRM_MSM` is a
module and not loaded). 90263 callbacks were suppressed in one burst.
The phone stays up.

## Learning

On our DTB the USB chain probes as upstream expects; nothing in the
devicetree needed changing. Every USB failure since 2026-10-15 came
from stage 2 running on stock's DTB, plus the missing TCSR clock.
Next: stop the splash faults (reserve the splash buffer and give the
display stream an identity mapping, or let ABL's MDP be turned off),
make `tools/dodge-try` build the chain image, then phase 3's UFS step.
