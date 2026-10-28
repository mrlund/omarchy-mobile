<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge): first light and guarded install

Status (2026-10-28): boots native Arch / Omarchy on SM8750 from the inactive
slot's `boot` partition. Kernel tip for review: curated `dodge/pr-kernel-v1`
(gpu2 + IPA). This document is the CONTRIBUTING §5 / §6 first-light record.

## 1. Sources

- **Kernel base:** `omamobile` on
  [derekross/linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile).
- **Board series:** subsystem-split commits on `dodge/pr-kernel-v1` (DT/board,
  display/panel, GPU, IPA, audio, Wi-Fi/BT, sensors, …). Config profile:
  `gpu2` (`CONFIG_QCOM_IPA=m`, MSM DRM).
- **Device tree:** `arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dts`
  (`compatible = "oneplus,dodge", …`).
- **Userspace:** `device/dodge/` and `packages/omamobile-device-dodge` in this
  repository.

## 2. Install contract (`tools/install-phone`)

Descriptor: [device.conf](device.conf) (`BOOT_METHOD=qcom-abl`,
`BOOT_IMAGES=boot`, `UFS_RW="boot_a boot_b userdata"`).

1. Phone in fastboot; product `dodge`; bootloader unlocked.
2. Installer reads `current-slot`, picks the other as inactive.
3. Requires `--firmware-slots-match <token>` (non-boot firmware on the inactive
   slot already matches the running slot). The installer **never** flashes
   xbl, abl, vbmeta, modem, radio, persist, efs or devinfo.
4. Flashes only `boot_<inactive>` and `userdata`, then
   `--set-active=<inactive>` and reboot.
5. `--dry-run` prints every command first.

Preparing the inactive slot's firmware from stock (once per phone) is a
manual fastboot copy of the running slot's firmware partitions onto the
inactive slot; record the bootloader version you attested in the flag.

## 3. Boot success and rollback

`device/dodge/boot-success/` marks the active slot successful after a clean
boot so the bootloader stops counting down retries. To return to the other
slot: `fastboot --set-active=<other>` (stock or the previous image). Keep a
known-good `boot` image offline.

## 4. Modem (opt-in)

Units under [modem/](modem/) stay inert unless
`/etc/omamobile/modem-probe.enable` exists. With the flag, each boot restores a
named good EFS *copy* under `/var/lib/omamobile/efs-good/` (read-only `dd` of
the phone's own partitions; never `-P` on the live partitions; never committed
to git). See [modem/README.md](modem/README.md).

## 5. Phone-smoke checklist (fill before opening the PR)

| Gate | Command / evidence | Result |
| --- | --- | --- |
| SSH | `ssh root@172.16.42.1` | _placeholder_ |
| Display | Hyprland / brightness / DPMS | _placeholder_ |
| GPU | `glmark2-es2` | _placeholder_ |
| Wi-Fi | NetworkManager scan + associate | _placeholder_ |
| BT | `bluetoothctl` pair | _placeholder_ |
| Audio | speaker + mic through PipeWire | _placeholder_ |
| Autorotate | tilt; rotation lock tile | _placeholder_ |
| Modem | MM registers; NM `omamobile-cellular` | _placeholder_ |
| Inactive install | `install-phone --dry-run` then real | _placeholder_ |

## 6. Shared-code rule

Changes to shared `tools/install-phone` keep the Pixel `android-v4` path
working: cheetah descriptors that only allowlist `*_b` still install to slot B
when the phone is on slot A. `qcom-abl` is additive.
