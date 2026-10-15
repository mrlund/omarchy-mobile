<!-- SPDX-License-Identifier: MIT -->
# AGENTS.md for the OnePlus 13 (dodge)

Read this before any step on dodge. The root [AGENTS.md](../../AGENTS.md)
is written for the Pixels, and its slot rules do not fit this phone.

1. **Read [PLAN.md](PLAN.md) §3 first.** §3.1 to §3.3 replace the root
   file's "only slot B is ours": the bootloader chain is never written,
   our boot images go to the *active* slot only, and the other slot is
   never flashed or made active until §3.3 clears it. §3.4 says which
   root rules still bind (asking before every flash, reboot or unlock;
   announcing screen changes; no `devmem` or PMIC/PMU register access;
   no identifiers or vendor blobs in git).
2. **Then the newest entries in [dev-docs/](dev-docs/)**, from the index
   in its README. An entry marked "Superseded" is history: follow the
   plan instead.
3. **`bin/omamobile flash`, `push`, `images` and the `UFS_RW` guard are
   Pixel-only.** They do not apply to dodge until the plan's §5.4.
   Never `fastboot flash` without a slot suffix, never `--slot=all`,
   never `set_active`.
4. **Nothing below `boot` is ever flashed**, whatever an OTA, a guide or
   a forum post says: no `xbl`, `abl`, `modem`, firmware or `vbmeta`.
   Anti-rollback can make that a permanent brick.
5. **Record every attempt** as a dev-docs entry, in the format the
   README gives, in the same change as the plan update it causes.
