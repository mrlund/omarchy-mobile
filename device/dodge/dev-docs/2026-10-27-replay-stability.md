<!-- SPDX-License-Identifier: MIT -->
# 2026-10-27 — consecutive cold boots from the good EFS copy set

**Goal.** Check whether the copy set left by the good R3 replay boot stays good
across back-to-back cold boots with no restore in between (target: 3 boots).
If it does, make the proven bring-up order permanent in the flag-gated units.
**Phone.** OnePlus 13 (dodge). No serial, IMEI or MAC.
**Kernel.** Trial `7.3.0-rc6-dodge-ipa1` by `fastboot boot` only (nothing
flashed). The phone returns to the default `7.3.0-rc6-dodge-gpu1`.
**Result.** Stopped after one boot. The R3 end-state set does **not** stay good:
boot S1 from it hit the rtsar Smart Transmit fatal. The last proven good set was
restored to the live copies. The ordered-startup units (step 2) were not started.

Follow-up to [first-boot replay](2026-10-27-first-boot-replay.md). Rules as
before: writable rmtfs copies only, 12 real partitions hashed before and after
(unchanged), persist not mounted, mpss never stopped, auto-restart off, no PDC
writes, no SMS/calls, no faked license responses, battery gate before the reboot.

## Backups first
Before any boot, every replay snapshot (R1-pre, R2/R3 pre, reg, end-live, post),
the pristine set from 10-26 and the then-live copies (`replay-S0-live`, equal
file-for-file to `replay-R3-post`) were kept in three places, outside git:
- on the phone under `/root/efs-backups/` (dirs 700, files 400);
- on the host in the replay scratch dir (700);
- in a separate host backup dir with a manifest covering every file.

Each snapshot carries its own SHA256SUMS. All were checked with
`sha256sum -c` at all three places, and the tar hashes match across sites.
The real-partition hash baseline sits next to the third copy. No contents,
hashes or identifiers are committed.

## Boot
| Boot | Start copies | Provisioning at modem-up | Registered | rtsar | Data |
|---|---|---|---|---|---|
| S1 | live set left by R3 (no restore) | **already bound** | no (searching) | fatal ~13-28 s after online | n/a |

Partitions 12/12 unchanged, oops 0, back on gpu1, modem flag off.
`modem_fs1` changed during S1, `modem_fs2` did not. The tqftpserv state is the
same in every snapshot since R1.

## Finding: provisioning state at modem-up tracks rtsar
| Boot | Start set | Slot-1 GW session at modem-up | Outcome |
|---|---|---|---|
| R1 | carried from the crashing PDC boots | already bound | rtsar |
| R2 | pristine | not bound, manual provisioning | registered, data, no rtsar |
| R3 | R2's snapshot at registration | not bound, manual provisioning | registered, data, no rtsar |
| S1 | R3's end state (after ~4 min registered) | already bound | rtsar |

Every bad boot started from a set where the modem had already persisted the
slot-1 provisioning binding. Every good one started unbound and was provisioned
by hand before online. The registration-time snapshot (R2-reg) was still
unbound. So the binding is written to the EFS copies some time after first
registration, and the next cold boot from that set fails.

This is a correlation over four boots, not a proven cause. Two readings fit:
- a modem auto-provisioned from persisted EFS state goes down a different
  startup path, and the Smart Transmit license check fails on that path;
- or something else written with the binding during the long registered period
  causes it.

The copy images are encrypted (see the offline-edit dev-doc), so we cannot read
which.

## State after
The proven good start set (R2-reg, which R3 started from) was restored to the
live copies with the phone on gpu1 and rmtfs stopped. It was checked file by
file and snapshotted (`replay-S1-restored-R2reg`). The S1 before/after
snapshots are kept at all three backup places as the evidence of the
good-to-bad transition.

## Next
- Option A (no new mechanism): treat a good set as start-only. Restore a known
  unbound set before every modem-on boot, then provision by hand. That gives
  working radio and data on each boot, but resets the modem's learned state.
- Option B (one variable per boot): find out when the binding is persisted.
  Boot from R2-reg, snapshot every ~30 s while registered, then cold-boot from
  the last unbound snapshot. Also try explicitly deactivating the provisioning
  session before the hard reboot, so the persisted state stays unbound. That is
  a UIM session call, not a PDC or NV write.
- The ordered-startup units wait until a set is shown to survive consecutive
  boots, or until option A is chosen as the policy.
