<!-- SPDX-License-Identifier: MIT -->
# AGENTS.md for the OnePlus 13 (dodge)

Read this before any step on dodge. The root [AGENTS.md](../../AGENTS.md)
is written for the Pixels, and its slot rules do not fit this phone.

1. **Read [PLAN.md](PLAN.md) §3 first.** §3.1 to §3.3 replace the root
   file's "only slot B is ours": the bootloader chain is never written
   except for the one-time firmware-match copy in §3.3; Omarchy boot
   images go to the *inactive* slot (currently `boot_b`); stock boot
   stays on the other slot as the way back. §3.4 says which root rules
   still bind (asking before every flash, reboot or unlock; announcing
   screen changes; no `devmem` or PMIC/PMU register access; no
   identifiers or vendor blobs in git).
2. **Then the newest entries in [dev-docs/](dev-docs/)**, from the index
   in its README. An entry marked "Superseded" is history: follow the
   plan instead.
3. **`bin/omamobile flash`, `push`, `images` and the `UFS_RW` guard are
   Pixel-only.** They do not apply to dodge until the plan's §5.4.
   Never `fastboot flash` without a slot suffix, never `--slot=all`.
   After every Omarchy boot-chain flash, run `fastboot set_active
   <omarchy-slot>` (check `getvar current-slot` first; today that slot
   is `b`): it gives the new image 7 tries until
   `dodge-boot-success.timer` marks it good (PLAN §3.3, §9). Never
   `set_active` to a slot whose firmware does not match the running
   slot's (copy-partitions / sha256 gate first).
4. **Nothing below `boot` is ever flashed in the day-to-day loop**,
   whatever an OTA, a guide or a forum post says: no `xbl`, `abl`,
   `modem`, firmware or `vbmeta` via fastboot. Anti-rollback can make
   that a permanent brick. The only exception is the §3.3
   firmware-match copy (A→inactive, byte-exact, read-back verified,
   never `vbmeta` / `qweslicstore` / `oplus*nv*` / modemst / fsg / fsc /
   persist / EFS / RPMB), which needs an explicit go.
5. **Record every attempt** as a dev-docs entry, in the format the
   README gives, in the same change as the plan update it causes.
6. **Do not boot stock Android while `userdata` holds Arch.** Stock
   `boot_a` is installed as a fallback image only; switching to it
   without wiping `userdata` can prompt a factory reset. Rollback to
   Omarchy if slot B fails: reflash Omarchy to `boot_b` and
   `set_active b`, or (emergency) reflash Omarchy to `boot_a` and
   `set_active a` (see `tools/dodge-restore-73gpu2`).
