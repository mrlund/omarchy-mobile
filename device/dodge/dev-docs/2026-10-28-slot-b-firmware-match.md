<!-- SPDX-License-Identifier: MIT -->
# 2026-10-28 — slot B move with firmware-match gate

**Goal.** Put Omarchy on slot B and stock boot on A, matching upstream's
inactive-slot model, after proving (or forcing) firmware equality.
**Phone.** OnePlus 13 (dodge), OxygenOS build family CPH2653 16.0.10.
**Kernel.** `7.3.0-rc6-dodge-gpu2` (unchanged).
**Result.** Pass. Case was **differed**: 27 A/B firmware partitions
mismatched; copied A→B with read-back verify; Omarchy boots from B;
stock `boot_a` written; never-touch guards unchanged.

## What we did

1. Read-only sha256 of every `/dev/disk/by-partlabel/*_{a,b}` pair while
   running Omarchy on `boot_a`. Dumps and the hash table live off-git in
   `~/android/mainline/scratch/slotb/` (delete later).
2. Martin approved proceeding despite the mismatch (copy A's firmware
   onto B, then continue).
3. Backed up every `_b` we would overwrite (497 MiB) to
   `/var/tmp/slotb-b-backup/` on the phone and
   `~/android/mainline/scratch/slotb/backup-b/` on the host, with a
   sha256 manifest.
4. Lifted the UFS storage-guard RO flag per partition only for the
   write, `dd` A→B, `fsync`, sha256 read-back, restored RO. Copied:
   abl, aop, aop_config, bluetooth, cpucp, cpucp_dtb, devcfg,
   engineering_cdt, featenabler, hyp, imagefv, keymaster, modem, pdp,
   pdp_cdb, pvmfw, qupfw, recovery, shrm, soccp_dcd, soccp_debug, tz,
   uefi, uefisecapp, xbl, xbl_config, xbl_ramdump.
5. Left untouched: vbmeta, qweslicstore, oplusstanvbk, all non-A/B
   (modemst/fsg/fsc/persist/EFS/oplusdycnvbk/RPMB), and the boot-chain
   partitions handled next.
6. Boot-chain on B: `boot_b` := running Omarchy `boot_a` (byte-exact);
   `init_boot_b`/`vendor_boot_b`/`dtbo_b` := stock OTA images (A's
   `init_boot` still has Magisk; stock preferred on B).
7. `tools/dodge-gate`, `reboot bootloader`, `fastboot set_active b`
   (cleared B's unbootable bit), `fastboot reboot`.
8. Verified Omarchy on B: Wi-Fi up, cellular registered with data, audio
   PipeWire/WirePlumber up, display DSI-1, autorotate running,
   `dodge-boot-success` marked `boot_b` successful, no rtsar fatal in
   dmesg. Guard hashes for modemst/fsg/fsc/oplusdycnvbk/qweslicstore/
   oplusstanvbk/modem unchanged.
9. Wrote stock OTA `boot.img` to `boot_a` only. Did **not** `set_active a`
   and did not boot it (`userdata` holds Arch).
10. Updated `device/dodge/AGENTS.md`, PLAN §3.3/§3.4, `device.conf`
    (`OMAMOBILE_SLOT=b`), and `tools/dodge-restore-*` (default SLOT=b;
    `SLOT=a … print` is the emergency dry-run).

## What happened

- Phase-1 case: **differed**, not matched. B was not blank.
- ARB: `xbl_config_{a,b}` are both ELF64 with phnum 14 and different
  content hashes; no discrete anti-rollback index integer was parsed
  with the host tools available. Fuse state still [I].
- Storage guard blocks partition writes until `blockdev --setrw` on the
  whole LUN and the partition; always restore `--setro`.
- GPT before switch: `boot_b` was `unbootable=1`. `set_active b` cleared
  it and reset `successful` until the timer/tool re-marked it.

## Learning

- The installer for dodge must refuse `set_active` until firmware
  sha256s match (or a copy-partitions step has been confirmed). Pixel-style
  `version-bootloader` checks do not work on this ABL (empty getvar).
- Keep Omarchy on the inactive-at-stock slot; never boot stock while
  Arch owns `userdata`.
- Checkpoint log: `~/android/mainline/logs/slotb-checkpoint.log`.
