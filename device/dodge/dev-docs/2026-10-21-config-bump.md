<!-- SPDX-License-Identifier: MIT -->
# 2026-10-21: 6.16 config bump (slice 1 toward omamobile 7.3)

**Status: built and staged on the phone, not booted yet.** The USB link is down
(loose cable, UDC state `default`), so a one-shot `fastboot boot` is not
possible. Kexec from a running stage 2 is not a substitute: LPIs are already
enabled there, the next kernel gets no clean ITS, and PCIe Wi-Fi MSI (our only
link without USB) breaks. boot_a is unchanged (`boot-chain-avb.img`, sha256
`5ab5829f…`).

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

## Next (needs USB)

1. Battery check, then `CHAIN_OUT=…/out-dodge-chain-cfg1 dodge-chain boot`
   (with the same env).
2. Check: `/sys/kernel/security/lsm` has landlock; `pacman -Sy` without
   `--disable-sandbox`; `/sys/devices/soc0`; `/dev/mapper/control`;
   display off/on, touch, Wi-Fi, USB, audio, sensors and autorotate; dmesg
   against the old boot.
3. If clean: `footer`, flash `boot_a`, `fastboot set_active a`, check a normal
   boot. Then the overlay becomes permanent until the loaders move to
   `$(uname -r)`.
