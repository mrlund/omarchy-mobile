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
2. Install target = `OMAMOBILE_SLOT` (generic key; dodge sets `b`; default `b`)
   (first install from stock on A → flash B).
3. Firmware gate (qcom-abl): when the install target differs from
   `current-slot`, `install-phone` auto-runs `tools/firmware-match` —
   RAM-boots a helper image, hashes A/B firmware pairs, copies
   running→inactive with sha256 read-back if needed, reports over USB
   NCM SSH, reboots to bootloader. Refuses if the helper fails.
   `--firmware-slots-match <token>` remains a manual override (skips the
   helper). Same-slot reflash skips both. This ABL's empty
   `version-bootloader` is why the Pixel BL string check cannot
   substitute. The installer **never** flashes xbl, abl, vbmeta, modem,
   radio, persist, efs or devinfo. Design: [firmware-match/README.md](firmware-match/README.md).
4. Flashes only `boot_<target>` and `userdata`, then
   `--set-active=<target>` and reboot.
5. `--dry-run` prints every command first (helper is not RAM-booted).

Preparing target-slot firmware (once per phone when slots differ): the
helper does the byte-exact copy. On 2026-10-28 a manual A→B pass covered
27 partitions; see §5. Shipping helper does not dump the dest slot first
(source slot remains intact; stock/OTA is the recovery path).

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

## 5. Phone-smoke evidence (2026-10-28 slot-B move)

On-phone bring-up (private branch `oneplus13-dodge` @ `4bb5c98`), kernel
`7.3.0-rc6-dodge-gpu2`, OxygenOS family CPH2653 16.0.10:

| Gate | Evidence | Result |
| --- | --- | --- |
| Firmware-match | sha256 of every `*_a`/`*_b` pair: **27 differed** (B not blank). Byte-exact A→B copy of abl/aop/…/xbl/modem/… (read-back verified). Left untouched: vbmeta, qweslicstore, oplusstanvbk, modemst/fsg/fsc/persist/EFS/oplusdycnvbk/RPMB | pass |
| Inactive-slot boot | Omarchy `boot_b` set active; stock OTA `boot.img` on `boot_a` only (not booted; Arch owns userdata) | pass |
| `version-bootloader` | empty on this ABL → firmware-match helper / `--firmware-slots-match`, not Pixel BL strings | noted |
| Auto firmware-match helper | `fastboot boot` chain image; RESULT=MATCH on A==B (no writes); returned Omarchy `boot_b` (2026-10-28) | pass |
| SSH / Wi-Fi | up after `set_active b` | pass |
| Cellular | registered with data (gpu2 IPA) | pass |
| Audio | PipeWire / WirePlumber up | pass |
| Display | DSI-1 | pass |
| Autorotate | running | pass |
| Boot-success | `dodge-boot-success` marked `boot_b` successful | pass |
| EFS guards | modemst/fsg/fsc/oplusdycnvbk/qweslicstore/oplusstanvbk/modem hashes unchanged | pass |
| `install-phone --dry-run` | still to run against this descriptor on a spare / dry path | _TODO before open_ |

Full narrative stays on the private branch
(`device/dodge/dev-docs/2026-10-28-slot-b-firmware-match.md`); this table is
the review-facing summary.

## 6. Shared-code rule

Changes to shared `tools/install-phone` keep the Pixel `android-v4` path
working: cheetah descriptors that only allowlist `*_b` still install to slot B
when the phone is on slot A. `qcom-abl` is additive.
