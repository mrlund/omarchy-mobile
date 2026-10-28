<!-- SPDX-License-Identifier: MIT -->
# Firmware-match helper (dodge)

Auto-attests A/B firmware equality before `install-phone` activates the
Omarchy slot on Qualcomm ABL devices (OnePlus 13). Replaces the manual
`--firmware-slots-match` friction for the common path; the flag stays as
an operator override. The running→inactive copy is a named exception in
[CONTRIBUTING.md](../../../CONTRIBUTING.md) §3.1.

## How it works

1. Host (`tools/firmware-match`) reads `current-slot` in fastboot, then
   `fastboot boot`s a RAM-only chain image packed with
   `omamobile.firmware-match` (no flash; see `tools/dodge-chain`).
2. Stage-2 first-light init brings up USB NCM + dropbear, runs
   `device/dodge/firmware-match/helper --from <current> --to <target> --copy`,
   and leaves `/run/omamobile-firmware-match.status`.
3. Host SSHs in, reads the status, then `reboot-to bootloader`.
4. `install-phone` continues only on `RESULT=MATCH` or `RESULT=COPIED`.

Channel: SSH over USB NCM (`root@172.16.42.1`). Simplest robust path;
ACM serial mirrors the STATUS line to kmsg as a fallback breadcrumb.

## Partition list

Same set used for the 2026-10-28 slot-B move: every A/B firmware pair
except `vbmeta`, `qweslicstore`, `oplusstanvbk`, and the boot-chain
images (`boot` / `init_boot` / `vendor_boot` / `dtbo`) that install-phone
flashes itself. Non-A/B (modemst/fsg/fsc/persist/EFS/…) are never touched.

## Backup policy

Lab copies kept dest-slot dumps under `/var/tmp` and on the host. The
shipping helper does **not** dump the inactive slot before overwrite:
the source slot stays intact, and stock/OTA remains the recovery path.
Operators who want a dump can pull the dest partitions over SSH before
passing `--copy`.

## Same-slot / --reflash target

When the install target equals `current-slot` (pinned `OMAMOBILE_SLOT=a|b`
already active, or `install-phone --reflash`), `install-phone` skips the
RAM-boot helper entirely: there is no inactive firmware copy to make.
Dodge ships `OMAMOBILE_SLOT=inactive` for first install; day-2 boot
rewrites use `--reflash` so the stock fallback slot stays untouched.

## Partition discovery

The helper prefers `/dev/disk/by-partlabel/<name>_<slot>`, then falls back
to `PARTNAME=` in `/sys/class/block/*/uevent` (Arch root and the dodge
initramfs often lack by-partlabel — see AGENTS.md). The firmware-match
init hook also synthesizes by-partlabel symlinks before running the helper.

