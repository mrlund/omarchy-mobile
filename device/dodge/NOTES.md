<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge)

Status (2026-10-28): native Arch Linux ARM / Omarchy Mobile on Qualcomm SM8750
(`7.3.0-rc6-dodge-gpu2` lineage). Display, GPU (Adreno 830), touch, Wi-Fi,
Bluetooth pairing, speakers/mics, sensors (autorotate), USB gadget networking
and SSH work on the phone. Modem (MPSS + IPA + ModemManager + NetworkManager
cellular) works behind an opt-in flag with a per-phone EFS restore (see
[modem/README.md](modem/README.md)); no modem blobs or EFS snapshots are in
this repository. Fingerprint, cameras and NFC are not started.

Kernel series: [linux-omarchy-mobile #115](https://github.com/derekross/linux-omarchy-mobile/pull/115)
(`dodge/pr-kernel-v1`; subsystem-split; gpu2 + IPA). Device tree:
`arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dts`. Userspace: this tree's
`device/dodge/` and `packages/omamobile-device-dodge`.

Install path: `BOOT_METHOD=qcom-abl`, `OMAMOBILE_SLOT=inactive`. First
install flashes the slot that is **not** running (stock stays on the running
slot); `tools/firmware-match` copies firmware running→target (see
[firmware-match/README.md](firmware-match/README.md)). `--firmware-slots-match`
remains a manual override. Day-2 updates are packages; to rewrite
boot/userdata on an already-Omarchy phone without touching the other slot:
`install-phone --reflash` (this ABL cannot fetch boot images, so the
installer cannot auto-detect Omarchy from fastboot alone). Never flashes
xbl, abl, vbmeta or modem from an image; firmware-match may copy
running→inactive ([CONTRIBUTING.md](../../CONTRIBUTING.md) §3.1). Phone
evidence 2026-10-28: 27 firmware partitions
differed; A→B copy then Omarchy on `boot_b` — see [BRINGUP-M1.md](BRINGUP-M1.md)
§5. Helper e2e 2026-10-28: `fastboot boot` + RESULT=MATCH (A==B, no writes),
returned to Omarchy on `boot_b`.

## Feature matrix (phone-verified)

| Block | Status | Notes |
| --- | --- | --- |
| Boot | works | Omarchy on `boot_b` (2026-10-28); stock `boot_a` fallback image; boot-success marks B |
| Storage | works | UFS; guard allowlists `boot_a`/`boot_b` and `userdata` |
| Display | works | Samsung panel through msm/dpu; brightness and DPMS; warm-boot drop fixed (QTB read) |
| GPU | works | Adreno 830 (gpu2); glmark2 / Freedreno on the phone; Vulkan untested |
| Touch | works | Synaptics over SPI |
| Buttons | works | Power and volume |
| USB net | partial | CDC NCM gadget + ACM console; SSH. Gap: gadget stuck after cable replug until reboot |
| Wi-Fi | works | WCN7860 (peach) / ath12k; autoconnect and 5 GHz |
| Bluetooth | partial | WCN7860; pairing verified; A2DP untested (no headset yet) |
| Battery | partial | gauge reads; charging path not fully claimed |
| Speakers/mics | works | AW882xx + UCM2 + PipeWire; speaker, earpiece and built-in mics; headset plug untested |
| Sensors | works | SSC via hexagonrpc / libssc; accel, proximity, compass; autorotate |
| Modem | testing | MPSS + IPA + MM + NM; LTE registration and data; EFS restore every boot; opt-in flag; calls/SMS untested |
| Suspend | WIP | screen-off idle works; s2idle not yet the default |
| Fingerprint | no | |
| Cameras | no | |
| NFC | no | |
| Charging / Haptics / Torch / GNSS | no | |
| AoC | - | Tensor-only block |

## 2026-10-28: matrix evidence

Phone-verified summary for [docs/DEVICES.md](../../docs/DEVICES.md). Companion
kernel in review as
[linux-omarchy-mobile #115](https://github.com/derekross/linux-omarchy-mobile/pull/115).
Full narrative for the slot-B move is in [BRINGUP-M1.md](BRINGUP-M1.md) §5.

| Block | What was run on the phone | Status word |
| --- | --- | --- |
| Boot / storage | Inactive-slot install after firmware-match (27 A/B pairs copied running→target, sha256 read-back); Omarchy on `boot_b`; boot-success marks B; stock OTA `boot` kept on `boot_a` | works |
| Display | msm/dpu panel up; brightness and DPMS; warm-boot drop closed (QTB read on MDSS enable; Martin verified cold start and idle/wake 2026-10-24) | works |
| GPU | Adreno 830 via Freedreno on gpu2; Hyprland and glmark2 on the phone; Vulkan (turnip) not run | works |
| Touch / buttons | `touchpanel` input; power and volume keys | works |
| USB net | CDC NCM + ACM + SSH. Known gap: after a cable replug the UDC can stay stuck until a reboot | partial |
| Wi-Fi | WCN7860 / ath12k; autoconnect, DHCP, 5 GHz | works |
| Bluetooth | hci0 up; pairing with another phone verified; A2DP / headset audio not tested | partial |
| Battery | fuel-gauge capacity reads; charging path not claimed | partial |
| Speakers/mics | Speaker and earpiece heard; built-in mic record+playback hands-on; USB-C headset plug untested | works |
| Sensors | Accelerometer, proximity, compass through SSC; autorotate on by default after install | works |
| Modem | With `/etc/omamobile/modem-probe.enable` and IPA (gpu2): LTE registration and data; EFS restore every boot; calls and SMS untested. Flag is opt-in in the package | testing |
| Suspend | Screen-off idle with GDSC off; `systemctl suspend` / s2idle not the default | WIP |

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
