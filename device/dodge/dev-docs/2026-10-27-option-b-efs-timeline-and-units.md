<!-- SPDX-License-Identifier: MIT -->
# 2026-10-27 — when the EFS copy set goes bad, and flag-gated startup units

**Goal.** Option B from the [replay-stability](2026-10-27-replay-stability.md)
note: find out when a good copy set turns bad, and whether a clean close of the
UIM provisioning session keeps it good. Then make the working bring-up order
permanent in flag-gated units, using whichever approach keeps the modem good.
**Phone.** OnePlus 13 (dodge). No serial, IMEI, IMSI, ICCID, number or MAC.
**Kernel.** Trial `7.3.0-rc6-dodge-ipa1` by `fastboot boot` only. Default
`7.3.0-rc6-dodge-gpu1` stays flashed and is where every boot returns.
**Result.** A clean close does not keep a set good, and the slot-1 binding is
not the cause. The units therefore restore a named known-good set before every
modem start (option A). Two consecutive flag-on cold boots with the units both
registered, passed data, and had no rtsar. Flag left **off**.

Rules as before: rmtfs serves writable copies only, the 12 real partitions
(modem a/b, modemst1/2, fsg, fsc, both NV backups, qweslicstore a/b, persist)
were hashed before and after every boot and were unchanged, persist was not
mounted, mpss was never stopped, auto-restart off, no PDC writes, no SMS or
calls, no faked license responses, the battery gate ran before every reboot,
and one change per boot.

## Backups
Every snapshot (pre and post each boot, the timeline points, the unit-made
`auto-*` ones) is kept in three places outside git: on the phone (dirs 700,
files 400), in the host replay scratch dir, and in a separate host backup dir
whose manifest covers every file. All were checked with `sha256sum -c` in all
three places, and the tar hashes match across sites. No contents, hashes or
identifiers are committed.

## Option B boots
| Boot | Start copies | Slot-1 GW session at modem-up | Outcome |
|---|---|---|---|
| B1 | R2-reg (known good) | not bound, manual provisioning | registered ~7 s after online, data, no rtsar; timeline below, then clean close |
| B2 | B1's end state after the clean close | **not bound**, manual provisioning | rtsar fatal ~13 s after online |
| B3 | B1's first post-registration save (`t02`) | **already bound** (auto-provisioned) | registered ~3 s, data, no rtsar for ~4 min |

B1 timeline (snapshot taken whenever fs1/fs2 changed):
- At registration both images were rewritten once.
- About 70–100 s after online, fs1 was saved again (`t02`).
- About 190–220 s after online, fs2 was saved again (`t06`).
- The clean close worked. ModemManager was stopped first. Deactivating the
  slot-1 primary GW provisioning session removed it, and the modem went to
  searching. fs1 was saved once more 15–45 s after the close.

What this shows:
- **A clean close does not keep a set good.** B2 started unbound and still
  crashed.
- **The binding is not the cause.** B3 started bound and was good. That
  corrects the correlation in the earlier note.
- The set goes bad later than the first post-registration save. It happens at
  the ~200 s fs2 save, or with the close, or after it. Which one was not
  narrowed down: that boot was skipped to keep budget for the units.
- The copy images are encrypted, so the change can't be read.

## Units (fallback A)
In `device/dodge/modem`, all gated by `/etc/omamobile/modem-probe.enable`:
- `omamobile-modem-efs.service`, before rmtfs (rmtfs and the modem unit
  require it). It runs `omamobile-modem efs-prepare`:
  1. It refuses to go on unless the DT has an enabled IPA node and IPA
     probes. On gpu1, which has no IPA node, the modem stack therefore never
     starts and the copies are left alone.
  2. It refuses to restore while rmtfs is running.
  3. It checks the named good set's own SHA256SUMS.
  4. It takes an `auto-…-prev-end` snapshot of the copies as the previous
     boot left them.
  5. It restores the six copy files from the good set and checks them
     against the set's hashes.
- `omamobile-modem-online.service`, after the modem and before ModemManager.
  It runs `omamobile-modem online`:
  1. It waits for QMI.
  2. It provisions slot 1 unless the modem already bound it. That is a UIM
     session call.
  3. It sets DMS online.
  4. It waits up to 90 s for registration, then takes an `auto-…-reg`
     snapshot.
  ModemManager starts after it, because ModemManager latches sim-missing if
  it starts first.
- Snapshots go to `/var/lib/omamobile/efs-snapshots/auto-*`. Each one is a
  consistent tar: the fs1/fs2 hashes match before and after, with up to 3
  retries. The newest 12 are kept.
- Named good sets live in `/var/lib/omamobile/efs-good/<name>`. They are
  never rotated or deleted by the units.
  `/etc/omamobile/modem-efs-good` names the set to restore.
- The helper never prints identifiers and does no PDC or NV writes.

## Verification (flag on, two consecutive cold boots)
| Boot | Start copies | Unit chain | Provisioning | Registered | Data | rtsar |
|---|---|---|---|---|---|---|
| V1 | B3's end state (restored to the good set by the unit) | all success | by the unit | ~8 s after online | 4/4 pings to two hosts | none (~3.5 min observed) |
| V2 | V1's end state (restored to the good set by the unit) | all success | by the unit | ~8 s after online | 4/4 pings to two hosts | none (~3.5 min observed) |

Data was checked by a manual ModemManager simple-connect. The address went
onto the bearer's `qmapmux` interface, with host routes for the two ping
targets. The NM cellular profile is still not installed. Across V1 and V2 the
partitions were 12/12 unchanged, there were no oopses, and the phone was back
on gpu1 with the flag off.

## Not done / next
- The flag stays off by default. Turning it on needs the IPA trial kernel,
  because gpu1 has no IPA node and the efs unit refuses to start there.
- Each modem boot starts from the same learned state, because the good set is
  restored every time.
- A possible alternative to restoring: rmtfs `-r` (modem writes kept in RAM)
  on top of the good set.
- The exact bad write (the ~200 s save or the close) is still unidentified.
