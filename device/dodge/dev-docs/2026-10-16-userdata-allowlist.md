<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — userdata allowlist logs sda15, still read-only

**Goal.** Phase 3.5 gate 3: log the one `userdata` partition and leave
every disk read-only.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** `6.16.0-g02a028467db0` #8, built 2026-10-16 12:42 CEST.
`DTB_OPTS='splash fb'`.
**Result.** Pass. `would allow sda15 (userdata)` at 1.66 s. 145 block
devices, all `ro=1`. Nothing mounted.

## What we did

`tools/dodge-try chain` from fastboot. The init's allowlist runs after
the partition list settles. It does not call `setrw`.

Image `out-dodge-rdinit/images/boot-chain.img`, sha256
`337471422e5c77b35dc5771031538e1c9b54abafe418a36b987ece3f444c4c3e`.
`Booting OKAY` and SSH at 27 s. `dmesg` is
`logs/dodge-allowlist-20261016-124330.kmsg` (not committed).

## What happened

```
omamobile: ufs-ro: would allow sda15 (userdata)
omamobile: ufs-ro: allowlist check: every disk read-only
```

No `STOP` line. No `FAILED to set`. Exactly one `PARTNAME=userdata`.
`/proc/mounts` has no `/dev/sd*`. `soc@0` is present. The laptop check
of the saved GPT list had already named `userdata` once, on `sda15`.

## Learning

The allowlist names the partition phase 4 may later make writable, and
this boot did not make it writable. Every other partition stays
read-only. Phase 3.5's three gates are met. Formatting `userdata` is
phase 4 and has not been started.
