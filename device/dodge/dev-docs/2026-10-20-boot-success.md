<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20 — slot A marked successful from Linux

**Goal.** Stop every Linux boot from spending slot A's retry budget, so
the phone no longer drops to fastboot with slot A unbootable after about
seven restarts.
**Phone.** OnePlus 13 CPH2653, `CPH2653_16.0.10.501(EX01)`.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Pass. `slot-successful:a` reads `yes`, and the retry count
held across four plain reboots and two boots from fastboot. A systemd
timer marks the slot on every good boot.

## Root cause

Qualcomm ABL keeps each slot's state in byte 6 of the slot's `boot_X`
GPT entry (attribute bits 48-55): priority 48-49, active 50, retry count
51-53, successful 54, unbootable 55. A slot that is not successful loses
one try per boot; at zero ABL marks it unbootable and stays in fastboot.
Android's `boot_control` HAL sets bit 54 once Android has booted. Linux
had nothing that did, and the storage guard leaves every UFS disk
read-only (`blockdev --setro`), which is the `EPERM` seen on
2026-10-17.

What this ABL reads, from the phone rather than from ABL source:

- `boot_a` is entry 12 on `/dev/sde` (the LUN that also holds `abl_a`,
  `tz_a` and the rest of slot A's chain). Its byte read `0x37` (priority
  3, active, 6 tries, not successful).
- Every other `*_a` entry on `sde` reads `0x7f` (7 tries, successful)
  and does not change from boot to boot. Only `boot_a` counted down. So
  ABL keeps the slot state in `boot_a` alone. `xbl_a` and friends on
  `sdb` read `0xc4`, which is not the same layout and is never touched.
- `fastboot getvar slot-*:a` matches `boot_a`'s byte exactly.
- `fastboot set_active a` writes `boot_a` to 7 tries, not successful.

[I] for the ABL code path itself; the behaviour above is [V].

## Options

- **`qbootctl` (linux-msm, as packaged by postmarketOS).** Its
  `mark-successful` sets the bit on *every* A/B partition it finds under
  `/dev/disk/by-partlabel`, across all LUNs, and commits each disk's GPT.
  That is a write to GPTs we do not need to touch (including the LUN
  that holds `xbl_a`). Its `ATTR_BOOTABLE` path flips the unbootable bit
  with XOR, and its `ATTR_SLOT_ACTIVE` path copies the primary byte into
  the backup. Not used.
- **A narrow tool of our own (chosen).** Set bit 54 of `boot_<running
  slot>` only, in both GPT copies of that one disk, plus the two CRCs.

## What we did

`device/dodge/boot-success/dodge-boot-success` (Python, installed at
`/usr/local/lib/omamobile/dodge-boot-success`):

1. Finds the running slot: `androidboot.slot_suffix` if the cmdline has
   it (ours does not: the chain-loader kexecs with its own cmdline),
   otherwise the one `boot_X` that is active and not unbootable. Any
   other count refuses.
2. Finds `boot_<slot>` by `PARTNAME` in sysfs (exactly one match), reads
   the primary GPT (LBA 1) and the backup (the header's AlternateLBA)
   with `O_DIRECT`, and checks signatures, header CRCs, entry-array CRCs,
   MyLBA/AlternateLBA, and that both entry arrays are identical. The
   entry at `PARTN - 1` must be named `boot_<slot>`.
3. Refuses a slot that is unbootable or not active. Exits 0 if the bit is
   already set (idempotent).
4. Builds the new entry array and headers, and refuses unless the entry
   array differs in exactly one byte (the attribute byte) and each header
   only in its header CRC and entry-array CRC.
5. `blockdev --setrw` on the whole disk only, writes the 4 KiB entry
   sector then the header of the primary, then the same for the backup
   (the backup stays valid while the primary is written), and puts
   `--setro` back in a `finally`. Partition nodes (`abl_a`, `boot_a`,
   ...) keep their own read-only flag throughout.
6. Re-reads both copies with `O_DIRECT`, requires them to equal what was
   written and re-validates every CRC, and checks `boot_b` is unchanged.

`--status` prints the state; `--dry-run` does everything except the
write.

`dodge-boot-success.timer` (`OnBootSec=90s`, enabled) starts
`dodge-boot-success.service`, which is ordered after `sshd`,
`omamobile-adsp-battery` and `omamobile-dodge-audio` and has an
`ExecCondition` that all three are active. Installed by hand in
`/etc/systemd/system`, like the other dodge units.

Backups before the first write (never in git):
`~/android/reference/dodge-cph2653/gpt-sde-2026-10-20/`: `sde` LBA 0-5
(protective MBR, primary header, 96 entries) and LBA 634875-634879
(backup entries and header), with `SHA256SUMS`. Both copies validated on
the laptop: header and entry CRCs good, entry arrays identical.

## What happened (times CEST)

| Time | Step | Slot A |
| --- | --- | --- |
| 14:42 | fastboot, before | `slot-successful:a: no`, `slot-retry-count:a: 6`, `slot-unbootable:a: no` |
| 14:42 | `fastboot reboot` into Linux | GPT `0x2f`: 5 tries, not successful |
| 14:43:54 | `dodge-boot-success` by hand | `0x2f -> 0x6f`, both CRCs verified; a second run: "already marked" |
| 14:44 | fastboot, after | `slot-successful:a: yes`, `slot-retry-count:a: 5`, `slot-unbootable:a: no` |
| 14:45 | `fastboot reboot` into Linux | still `0x6f`, 5 tries |
| 14:46-14:54 | three plain `reboot`s from Linux | Linux each time (SSH 40 s after the reboot), sshd, battery and audio active, the timer ran at 90 s: "already marked", 5 tries every time |
| 14:54 | fastboot | `yes`, `5`, `no`; then `fastboot set_active a`: `no`, `7`, `no` |
| 14:55 | `fastboot reboot` | Linux; GPT `0x37` (6 tries); at 90 s the **timer** marked it: `0x37 -> 0x77`, CRCs verified |
| 14:57 | fastboot | `slot-successful:a: yes`, `slot-retry-count:a: 6`, `slot-unbootable:a: no`, `slot-unbootable:b: yes` |
| 14:58 | `fastboot reboot` | Linux; the timer: "already marked"; sshd, battery, audio, Hyprland active, no failed units |

A byte compare of `sde` LBA 0-5 and 634875-634879 against the backups
after the first write showed differences only at the `boot_a` attribute
byte and the two CRCs of each header. `boot_b` (`0xf2`) was never
written.

## Learning

- **A successful slot does not count down.** ABL left the retry count
  alone on every boot once bit 54 was set.
- **The trade-off.** The countdown was also an automatic way back: a
  kernel that crash-loops used to land in fastboot after its tries. A
  marked slot keeps booting it. So after every `boot_a` (or chain image)
  flash, run `fastboot set_active a`, as the flash steps already do: it
  clears the bit and gives the new image 7 tries, and the timer marks it
  only once sshd, battery and audio are up 90 s into a boot.
- **One disk, one byte.** Nothing writes `abl`, `xbl`, any `*_b` entry,
  persist, the modem partitions or partition data; the geometry, names
  and GUIDs are compared byte for byte before and after.
- PLAN §3.1/§3.3 and §9 updated.
