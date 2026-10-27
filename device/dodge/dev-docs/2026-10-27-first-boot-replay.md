# First-boot replay on the writable EFS copies (2026-10-27)

Follow-up to the rtsar / carrier-MCFG PDC boots. Goal: replay the modem's
first-boot sequence from known writable copy sets. Snapshot the copies around every
boot and catch a copy set that registers on the home LTE network without
the Smart Transmit (rtsar) license-check fatal.

Rules as before: IPA trial kernel by `fastboot boot` only (nothing flashed), battery
gate before every reboot, 12 real modem/EFS/nvbk/qweslicstore/persist
partitions hashed before and after each boot (all served read-only, never
written), persist not mounted, mpss never stopped, auto-restart off, no PDC
writes, no SMS/calls, no faked license responses. Only the rmtfs/tqftpserv
**copies** were restored between boots. Each restore was verified file by file.

## How the earlier registering runs were set up
From the 10-26 notes and logs: a pristine copy set is written by the modem on its
first boot (carrier config goes Pending -> Active). With manual UIM provisioning
plus DMS online on the next boots, the modem registered within seconds. One
carried set (the ipa2a run) registered, brought data up, and showed no rtsar.
Earlier pristine-restore boots were judged "sim-missing" only from
ModemManager. ModemManager had been started before UIM provisioning and latched a
failed state, and registration was never read from QMI NAS directly.

Replay session (per boot): load ipa/rmnet. Start rmtfs + tqftpserv + modem
**without ModemManager**. Read PDC (list only), UIM card status and NAS. Provision
slot 1 unless already bound, then set online. Poll every 3 s for mpss state, rtsar
and NAS registration. On first registration, snapshot the live copies (checking
fs1/fs2 before/after the tar for consistency). Only then start ModemManager,
simple-connect, apply the bearer IPv4 config with host routes to two public
resolvers, and ping. Watch until uptime 300 s, take a final live snapshot, and
snapshot again from the default kernel after the hard reboot.

## Boots
| Boot | Start copies | PDC carrier at modem-up | Provisioning | Registered | rtsar | Data / ping |
|---|---|---|---|---|---|---|
| R1 | carried set left by the previous PDC boot | Active | already bound | no (searching) | fatal ~13-28 s after online | n/a (modem crashed) |
| R2 | pristine set (restored) | Pending -> Active within 3 s of online | manual, ok | home LTE +6 s | none in 259 s | bearer up, 4/4 + 4/4 |
| R3 | R2's live snapshot taken at registration (restored) | Active | manual, ok | home LTE +6 s | none in 259 s | bearer up, 4/4 + 4/4 |

All three: oops 0, partitions 12/12 unchanged before/after, back on the default
kernel with the modem-probe flag off.

## Findings
- The pristine set **does** register and pass data once ModemManager is held back
  until after provisioning + registration. The earlier "sim-missing" was an
  ordering artifact, not missing SIM state in the copies.
- The carrier MCFG being **Active is not by itself the rtsar trigger**. R2 and R3
  ran with it Active (R3 from cold boot) and stayed registered and connected for
  more than 4 min with no license check fatal. That revises the previous dev-doc's
  conclusion.
- The rtsar fatal follows the **copy set lineage**. The set carried out of the
  earlier crashing boots (R1) reproduces the fatal. The set produced by a clean first
  boot from pristine (R2's registration snapshot) reproduces a good boot from cold
  (R3).
- The literal target (registered while carrier NOT Active) was not reachable: the
  carrier config flips Active before the first registration even from pristine.
  It turned out not to matter.

## Good-state snapshots (kept outside the repo, mode 700/400)
On the phone under `/root/efs-backups/`, mirrored to the host scratch area:
`replay-R2-pre-*` (pristine start), `replay-R2-reg-*` (live at registration,
consistent), `replay-R2-end-live-*` / `replay-R2-post-*` (end of good boot),
`replay-R3-reg-*`, `replay-R3-end-live-*`, `replay-R3-post-*` (reproduction).
The bad reference is `replay-R1-pre-*`. No snapshot contents, hashes or
identifiers are committed.

## Next
Run more cold boots from the R3 end state, with no restore in between, to see
whether a good set stays good across consecutive boots. Or find which step
in the earlier crashing lineage turned the set bad (one variable per boot).
