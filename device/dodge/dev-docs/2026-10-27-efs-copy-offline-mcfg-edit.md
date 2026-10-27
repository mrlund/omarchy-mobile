<!-- SPDX-License-Identifier: MIT -->
# 2026-10-27 — offline MCFG deselect on the writable EFS copies

**Goal.** Make a copy set that can still register but has no active carrier
MCFG, by editing the rmtfs-served writable copies offline (modem not running).
Then use it for one cold boot that registers with no rtsar Smart Transmit check
and passes data.
**Phone.** OnePlus 13 (dodge). No serial, IMEI or MAC.
**Kernel.** `7.3.0-rc6-dodge-gpu1` (default) the whole time. No trial kernel booted.
**Result.** Stopped before any boot. The EFS sync images can't be edited
offline because they are encrypted and bound to the device. 0 of 2 boots used.

## What we did

Follows on from [rtsar vs active carrier MCFG](2026-10-27-rtsar-carrier-mcfg-pdc-boots.md).
Everything ran read-only on the laptop, against copies pulled from the phone:

- Pulled four copy sets into a mode-700 scratch dir outside the repo:
  - the pristine set
  - the post-ipa2e set
  - the last registration-capable carrier-Active set (the one used in the
    first PDC boot; its tarball checksum verified)
  - the current live copies
- Took per-4 KiB-block Shannon entropy and checked the headers and NV path
  strings of `modem_fs1`/`modem_fs2`, `oem_stanvbk`/`oem_dycnvbk` and
  `modem_fsg`/`modem_fsc`.
- Diffed the pristine fs1 against the carrier-Active fs1, byte by byte.
- Listed every copy-set backup on the phone with its fs1/fs2 mtimes, to look
  for a saved copy of the state from before the good run.

## What happened

- **`modem_fs1`/`modem_fs2` (the EFS sync images the modem writes):**
  - The small cleartext header names the image (`IMGEFS1`/`IMGEFS2`) and
    records geometry and sequence numbers.
  - Every other 4 KiB block has entropy between 7.94 and 7.97 bits/byte. The
    whole file is at 8.00. No path strings anywhere.
  - Pristine and carrier-Active fs1 differ in about 99.6 % of their bytes, as
    you'd expect from a fresh IV/key stream on every sync write. A small
    logical change (one MCFG flag) shows up as a full re-encryption.
  - So the image is encrypted, and the key is held by the modem/TZ for this
    device. There is no EFS2 tree to parse, so `/nv/item_files/mcfg/*` can't
    be found or edited, and neither can anything else.
- **`modem_fsg`/`modem_fsc`:** all zeros in every set (no golden copy). Nothing
  to edit.
- **`oem_stanvbk`/`oem_dycnvbk` (OnePlus NV backups):**
  - These are cleartext item records (`OEMNVBK` header), and the static one
    does contain the MCFG UIM-autoselect item and the rtsar Smart Transmit
    config item (a compressed blob).
  - They are byte-identical across the pristine, carrier-Active and live sets.
    The modem never writes them, so they don't hold the carrier-MCFG selection.
  - The modem reads them only to restore NV when the EFS is missing or invalid.
  - The header carries a digest.
  - Editing them would mean editing an NV/calibration backup, and it would
    only take effect after the EFS copies were blanked, which forces a
    factory-style NV restore. That is several changes at once, it puts the
    calibration state at risk, and it is an NV write in substance. That is
    outside the rules, so it wasn't done.
- **Backups:** the only copy set older than the good run (ipa2a) is the
  pristine one. No snapshot exists of the exact copies ipa2a booted from. Every
  later post-registration set carries the carrier config Active, and in every
  boot that went online on one of them, rtsar fired.
- No boot was spent. Partitions were checked read-only afterwards: 12/12
  identical to the baseline. Persist was unchanged. The phone stayed on gpu1
  with the modem-probe flag off and only adsp running.

## Learning

- The writable-copy route can only *swap whole copy sets the modem wrote*. It
  can't *edit* them. The MCFG selection can only be changed by the modem
  itself, either at runtime (PDC, which needs a modem refresh, and that needs
  mpss stopped, which is barred) or by its own first-boot autoselect.
- The good run's state (registered, PDC showing 0 configs) was lost because it
  was never snapshotted. From now on, take a copy-set backup **before and
  after every** modem-on boot, so a good state can be replayed by restoring
  the whole set.
- Paths that are still open and inside the rules: none that change only the
  copies. Options for the owner to choose from:
  - replay the pristine first-boot sequence (m74 A then B) under the IPA
    kernel and snapshot after each boot, to try to catch a registration-capable
    set before the carrier config goes Active
  - satisfy the license check properly through the QWES read path (qtee1)
- This confirms the rtsar/MCFG plan's assumption that the copies are the only
  mutable state. It also shows the copies are opaque, so "edit the copies" is
  not a usable tool.
