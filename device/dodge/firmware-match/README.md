<!-- SPDX-License-Identifier: MIT -->
# Firmware match before the other slot (dodge)

OxygenOS has anti-rollback: booting a slot whose bootloader firmware
(`xbl_config` and friends) is older than the fuse floor can hard-brick the
phone. So before a boot image goes onto the inactive slot, and before that
slot is ever made active, every A/B firmware pair must be byte-equal.
On 2026-10-28 this phone's 27 differing pairs were copied A→B by hand and
read back (BRINGUP-M1.md §3); since then A and B should match, but an
OxygenOS OTA or a stock boot can change one side.

[`check`](check) is the read-only half of the helper that the deferred
inactive-slot installer was to run: it hashes the 33 pairs and prints
`RESULT=MATCH` or which pairs differ. It writes nothing. Run it on the
booted Omarchy, over USB SSH, with the running slot as `--from`:

```sh
tools/phone-ssh 'sh -s -- --from b --to a' < device/dodge/firmware-match/check
```

Only `RESULT=MATCH` (exit 0) clears the way for writing `boot_<other>`.
On `RESULT=DIFF` stop: a copy is a by-hand step the owner approves, with
sha256 read-back, and it never touches `vbmeta`, `qweslicstore`,
`oplusstanvbk` or any non-A/B partition.
