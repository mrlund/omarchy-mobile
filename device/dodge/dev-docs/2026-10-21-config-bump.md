<!-- SPDX-License-Identifier: MIT -->
# 2026-10-21: 6.16 config bump (slice 1 toward omamobile 7.3)

**Status: flashed to boot_a (14:43 CEST), normal boot verified.** The first
attempt was blocked at 14:32 by the USB gadget being stuck (NOTES, open bug).
A reboot cleared it at 14:35. The previous chain is kept as
`out-dodge-chain/images/boot-chain-avb.before-cfg1.img` (sha256 `5ab5829f…`).

## What changed

- Fragment `kernel/generic-2026-10-21.config`, merged onto
  `config-6.16.0-gb3ee311dab85-modules` → `kernel/config-6.16.0-gbd9587d65`
  (a 177-line diff). Every fragment value was checked in the merged config.
- Enabled (all `=y`, because modules are held and never autoload):
  - Landlock
  - `QCOM_SOCINFO`, `BLK_DEV_DM` + `DM_VERITY`, `EROFS_FS`
  - binder + binderfs
  - PSI, `BOOT_CONFIG`, `FONTS`, dmabuf heaps (system, CMA), F2FS, `CHR_DEV_SG`,
    PM debug
  - IPv6 built in (it was `=m`), inet diag, policy routing, cls/act BPF
  - netfilter core, nftables (inet/netdev/ipv4/ipv6 + `NFT_*`),
    xtables/iptables/ip6tables
- Skipped, with the reason:
  - display/DSI/MDSS/GDSC, Wi-Fi, USB gadget: the risky bring-up areas
  - stage 1/kexec: the boot chain stays as it is
  - UFS inline crypto: touches the UFS probe on the root disk
  - CMA size: changes the memory layout under the DSPs
  - `FB_SIMPLE`, `PCI_PWRCTRL_GENERIC`: overlap with our splash/fb and pwrseq
  - Pixel-only drivers
  - `NETFILTER_XTABLES_LEGACY`: not in 6.16
- Notes on dependencies: the IPv6 netfilter options stayed at `m` until
  `IPV6=y`, and `INET_UDP_DIAG` needs `INET_DIAG=y`.

## Build and modules

- `out-dodge-cfg1`, with `KERNELRELEASE=6.16.0-gbd9587d65` (a **new** release,
  so the old and new module trees live side by side). rc=0. The Image is 42M,
  with 1336 `.ko`. The DTB is byte-identical to the `out-dodge` one.
- On the phone:
  - `/usr/lib/modules/6.16.0-gbd9587d65.held` (74M, stripped)
  - `/usr/local/lib/omamobile.6.16.0-gbd9587d65` (36 `.ko` rebuilt; the
    `dodge-wlan-*.ko` have no source, are unused, and were dropped)
  - `omamobile-kmod-overlay.service` (sysinit) binds both over the paths the
    loaders hard-code, but only when `uname -r` differs from
    `6.16.0-gb3ee311dab85`. Checked on the running kernel: exit 0, nothing
    mounted.
- Test image: `out-dodge-chain-cfg1/images/boot-chain.img` (sha256
  `d455c437…`). It is the same as the flashed chain except
  `STAGE2_IMAGE=out-dodge-cfg1/.../Image`. Stage 1 still uses the old
  `.config`, and the DTB, initrd and cmdline are unchanged. Built in a separate
  `CHAIN_OUT`, so the flashed image is untouched.

## One-shot test (14:37 CEST, `fastboot boot`)

- Battery gate `tools/dodge-battcheck`: 56%, −78 and −67 mA mean.
- `6.16.0-gbd9587d65`, our DTB (soc@0). The overlay unit was active and bound
  both trees, and the modules loaded from them (vermagic matches).
- `lsm=capability,landlock` ("landlock: Up and running").
- `pacman -Sy` without `--disable-sandbox` synced all four repos.
- `/sys/devices/soc0` reads SM8750/618. `/dev/mapper/control` exists, and
  `dmsetup` reports driver 4.50.0.
- binder, erofs and f2fs are in `/proc/filesystems`. `/proc/pressure` exists.
  `nft add/delete table` and `iptables -L` work. IPv6 is on.
- Wi-Fi connected (HTTPS 200), BT powered, USB `configured`, the sound card
  and Speaker sink present. The sensors service and iio-sensor-proxy were
  active, and autorotate saw the accelerometer.
- Display off/on through Hyprland dpms: bl_power 4/Off → 0/On, with no
  DSI/msm errors. Martin confirmed the picture was normal, touch landed in the
  right place, and rotation was correct.
- dmesg error/warn lines (normalized) compared with the old kernel's boot: no
  new lines. Only the taint flag lost `[O]` (the overlay modules are now
  in-tree builds).

## Flash and normal boot (14:43 CEST)

- `dodge-battcheck` passed (−43 mA), then `fastboot flash boot_a`,
  `fastboot set_active a` (current-slot a), and reboot. A second gate run
  from fastboot could not reach SSH; this is expected, and the pass just
  before the reboot is the one that counts.
- Normal boot: the same release and cmdline. The overlay unit was active.
  ath12k, msm, synaptics_tcm2 and mac80211 loaded from the new tree. Landlock
  on, Wi-Fi on (HTTPS 200), sensors and autorotate running, no failed units,
  `is-system-running` running. A short `pw-play` to the default (Speaker)
  sink returned rc 0.
- `dodge-boot-success` at 14:45:35: `boot_a: 0x77 ... retry=6 successful=1`.

## Follow-ups

- The overlay is now permanent. Later, move the loaders to `$(uname -r)` paths
  and drop the pinned names.
- Use `DBUS_SESSION_BUS_ADDRESS` for pw-play under `su` (only RTKit
  warnings, harmless).
