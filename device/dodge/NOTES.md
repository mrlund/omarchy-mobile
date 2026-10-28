<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge)

Status (2026-10-28): native Arch Linux ARM / Omarchy Mobile on Qualcomm SM8750
(`7.3.0-rc6-dodge-gpu2` lineage). Display, GPU (A740), touch, Wi-Fi, Bluetooth,
speakers/mics, sensors (autorotate), USB gadget networking and SSH work on the
phone. Modem (MPSS + IPA + ModemManager + NetworkManager cellular) works with
an opt-in flag and a per-phone EFS restore (see [modem/README.md](modem/README.md));
no modem blobs or EFS snapshots are in this repository. Fingerprint, cameras
and NFC are not started.

Kernel series: [linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile)
branch proposed as `dodge/pr-kernel-v1` (subsystem-split; gpu2 + IPA). Device
tree: `arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dts`. Userspace: this
tree's `device/dodge/` and `packages/omamobile-device-dodge`.

Install path: `BOOT_METHOD=qcom-abl`, `OMAMOBILE_SLOT=b`. `tools/install-phone`
flashes `boot_<OMAMOBILE_SLOT>` (else the inactive slot) and `userdata`, then
`--set-active` to that slot. It never flashes xbl, abl, vbmeta or modem.
`--firmware-slots-match` is required (this ABL's `version-bootloader` is
empty). Phone evidence 2026-10-28: 27 firmware partitions differed; A→B copy
then Omarchy on `boot_b` — see [BRINGUP-M1.md](BRINGUP-M1.md) §5.

## Feature matrix (phone-verified)

| Block | Status | Notes |
| --- | --- | --- |
| Boot | works | Omarchy on `boot_b` (2026-10-28); stock `boot_a` fallback image; boot-success marks B |
| Storage | works | UFS; guard allowlists `boot_a`/`boot_b` and `userdata` |
| Display | works | Samsung panel through msm/dpu; brightness and DPMS |
| GPU | works | Adreno A740 (gpu2); glmark2 on the phone |
| Touch | works | Synaptics over SPI |
| Buttons | works | Power and volume |
| USB net | works | CDC NCM gadget + ACM console; SSH |
| Wi-Fi | works | WCN7850 / ath12k |
| Bluetooth | works | WCN7850 |
| Battery | partial | gauge reads; charging path not fully claimed |
| Speakers/mics | works | AW882xx + UCM2 + PipeWire |
| Sensors | works | SSC via hexagonrpc / libssc; autorotate |
| Modem | testing | MPSS + IPA + MM + NM; EFS restore every boot; opt-in flag |
| Suspend | WIP | s2idle not yet the default |
| Fingerprint | no | |
| Cameras | no | |
| NFC | no | |

## Provenance

- Board DTS and driver enablement authored for Omarchy Mobile from public
  mainline SM8750 support, OnePlus 13 DT fragments, and bring-up on this phone.
- Audio codec unmute and panel sequence: see kernel commit messages and
  `Assisted-by` / `Signed-off-by` trailers.
- Missing upstream sign-offs from earlier community fragments (index986 /
  ROCKNIX / Teguh) are listed in the kernel PR description for the maintainer.

## What is not in this tree

Lab notebooks (`dev-docs/`), DIAG trials, out-of-tree splash/fastrpc experiments,
EFS snapshots, modem firmware blobs, and AGENTS/PLAN files stay on the private
bring-up branch. The modem units document how to take **read-only** `dd`
copies of the phone's own EFS partitions onto the device; those copies are
never committed.
