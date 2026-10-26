# Why the modem registered/held earlier but now hits rtsar Smart Transmit License crash

Phase 1: factual timeline diff of good vs failing runs (read-only, logs only, no boots).
Source: ~/android/mainline/logs (m74-*, p73-ipa1*, p73-ipa2*, earlier consult prompts),
cross-checked against real-partition hashes. No identifiers / EFS value bytes reproduced.

## Two distinct crash signatures (do not conflate)
- `lte_rrc_llc.c:8590 Assert ... DS_3GPP_BEARER_SWITCH_COMPLETE_IND not rcvd from DS in 2600ms`
  = data-services bearer-switch assert. Fires only on the NO-IPA kernel (gpu1), ~30 s after
  the modem goes online, because the data path has no IPA to complete the bearer switch.
- `rtsar_framework.c:3546 Smart Transmit License Check Failure Code (1,1,1)`
  = the license-gated Smart Transmit check. Only observed on the IPA kernel, during
  registration/TX bring-up (~20-30 s after modem-up), and only on some boots.

## Timeline (Oct 26, all times CET)
| run | kernel | IPA | writable EFS copies | online? | reached | outcome |
|-----|--------|-----|---------------------|---------|---------|---------|
| m74 A ~12:47 | gpu1 | no | pristine, modem's first write; operator MCFG goes **Pending** | no (opmode shutting-down) | search | no crash |
| m74 B ~12:50 | gpu1 | no | modem-written; **MCFG Active** | yes (manual UIM prov + DMS online) | reg home LTE ~6 s, CS+PS attached | crash **DS bearer** ~30 s later |
| m74 C ~12:57 | gpu1 | no | modem-written; MCFG Active | yes | reg LTE, attached | crash **DS bearer** |
| ipa1b 13:48 | ipa1 | yes | carried | yes | LTE attach | crash **DS bearer** (lte_rrc_llc:8590) |
| ipa2a 13:52 | ipa1 | yes | carried; **PDC lists 0 configs** (defaults); modem writes copies 13:56 | yes | reg LTE, **PS attached, DATA connected** (bearer/1) | **NO crash, held >200 s** |
| ipa2b 14:03 | ipa1 | yes | carried (post-ipa2a write) | yes | PS **detached** | crash **rtsar** @57 s (~26 s after up) |
| ipa2c 14:08 | ipa1 | yes | carried | yes | detached | crash **rtsar** @58 s |
| ipa2d 14:17 | ipa1 | yes | carried; MCFG TDC Active (unchanged) | **no** (MM masked, idle 190 s) | n/a | **NO crash** |
| ipa2e 14:24 | ipa1 | yes | carried | yes | search/detach | crash **rtsar** @84 s |
| ipa2f 14:29 | ipa1 | yes | **RESTORED fs1/fs2 to pre-write (12:46) backup** | yes (manual; MM failed sim-missing) | online 140 s (no reg data) | **NO crash** |
| ipa2g 14:35 | ipa1 | yes | carried | yes | search/detach | crash **rtsar** @60 s |
| ipa2h 14:43 | ipa1 | yes | carried | yes (long search) | detached | crash **rtsar** @112 s |
| ipa2i 14:56 | ipa1 | yes | carried | yes (NM gsm profile) | search/detach | crash **rtsar** @69 s |
| tc/qp 15:xx-17:xx | gpu1 | no | pristine restored + tqftpserv emptied | no (recon only) | n/a | no crash (no TX) |

(pr2a/b 11:24-11:58 were on the `pr2` panel/suspend kernel, not modem runs; excluded.)

## Invariants
- Real partitions (modem_a/b, modemst1/2, fsg, fsc, persist, oplus*nvbk) hashed **identical**
  at the 12:46 baseline, 13:02 after m74, and again today 17:16. Never written in any run.
- The writable **copies** (/var/lib/omamobile/modem-efs modem_fs1/fs2, served by rmtfs) ARE
  rewritten in full by the modem on registration, and (before the tc runs) were NEVER restored
  between boots - they carried over.
- tqftpserv readwrite dir holds mcfg.tmp (rewritten every boot, not restored) + server_check.txt.

## What the data shows about the hypotheses
- (a) EFS copy-state drift: **supported.** Every "carried-over post-write copies + online" boot
  hit rtsar. The three boots that did NOT crash each had a *different* copy/online state:
  ipa2a ran with PDC showing 0 configs (defaults, first clean reg, copies not yet carrying the
  post-reg write); ipa2f ran on copies restored to the pre-write 12:46 backup; ipa2d never went
  online. The onset of rtsar lines up with the modem's own write to the copies during/after
  ipa2a's first clean registration+data.
- (b) MCFG/PDC config switch: **supported and intertwined with (a).** In the good 12:50/12:57
  runs the operator MCFG was **Active**; now TDC_Denmark_Commercial is stuck **Pending** (activate
  returns DeviceInUse). A config that selects region/SAR/Smart-Transmit policy is the plausible
  thing written into the copies at first registration. Which config is active at the moment of
  online is the deciding variable.
- (c) TX power path / band: **not supported as the trigger.** The one boot that actually
  transmitted sustained data (ipa2a, PS attached, bearer up) did NOT crash; the rtsar boots
  crashed while PS was *detached* (before any data), during attach. So data/TX load is not the
  trigger; the check fires at attach/registration-completion.
- (d) license grace / time-based: **possible, unproven.** Crash latency varies (57-112 s) and
  outcome is intermittent with identical kernel+image+session, which is consistent with a
  grace/first-use timer or a per-boot state input, but nothing in the logs proves a clock tie.
- Kernel is NOT the discriminator for rtsar: same ipa1 image + same ipa1-session.sh produced
  both clean (ipa2a/f) and crashing (ipa2b/c) boots. The IPA kernel's role is only that it fixed
  the DS-bearer crash, letting the modem progress far enough to reach the Smart Transmit check.

## Leading explanation
The modem's first clean home-network registration (ipa2a) caused it to commit region/SAR/MCFG
state into the writable EFS copies that enables Smart Transmit enforcement. From the next boot
on, with that state carried over and no QWES license daemon (qwesd) to satisfy the check, the
modem asserts rtsar during attach. Earlier gpu1 boots "worked" only in that they crashed earlier
on the DS-bearer assert (no IPA) before ever reaching the Smart Transmit check, and/or ran before
that state was committed. Real partitions are untouched; the mutable state is entirely in the
rmtfs-served copies + MCFG selection.

## Cheap, rule-compliant test this points to (Phase 3 candidate)
Restore the writable copies to the exact 12:46 pristine tarball (20261026-124620), empty the
tqftpserv mcfg.tmp, boot the ipa2a image, provision slot 1 + go online, and watch: if it
registers and holds (reproducing ipa2a) -> confirms the copy/MCFG-state cause and yields a
non-QWES workaround; if it still rtsar-crashes -> the cause is not the copies alone.
Does NOT require any write to real partitions, pdc-activate, or stopping mpss.
