# qwes-xlat q9 - modem-ON devcoredump trial (capture the modem's own StX verdict)

Date: 2026-10-27 (approved 11:23). Reversible: `fastboot boot` qtee1 image only (nothing
flashed). HARD RULES honoured: no secure-storage writes; real modem/EFS/persist/qweslicstore
partitions untouched (12/12 sha unchanged); listeners read-only (log+refuse, never forward a
write); persist served READ-ONLY; no fake/hard-coded license; mpss never stopped; no
identifiers/firmware/TA/.pfm/dump contents in repo. Modem RAM (if dumped) was to stay mode 600
under ~/android/mainline/logs, off repo/shared, describe-only.

## Goal
q8 showed every stored PFM license (incl. StX FID 1118) reports, TO THE HLOS qwes_cli caller,
Status 0 / Restrictions 11 - a static signed property, not a runtime verdict. Owner's two
corrections: (1) qls_hlos-timestamp being 0 bytes is weak evidence for a secure-time gate (it
is 0 bytes in stock factory persist too, yet StX works on Android); (2) qwes_cli is an HLOS
caller, so its uniform Status 0/11 may just be the HLOS view, not the modem's verdict. So:
capture the MODEM's own IPFM verdict by enabling the mpss remoteproc coredump and reading the
devcoredump after the rtsar fatal.

## Procedure (same as q6 + coredump)
Boot qtee1 kernel -> start qtee_supplicant (RO RPMB+FS listeners, under strace) -> load+hold the
QWES TA via qwes_cli -> mount persist READ-ONLY (loop image) -> `echo enabled > modem
remoteproc coredump` BEFORE MPSS start -> start MPSS -> drive ModemManager to registration ->
wait for the rtsar fatal -> read /sys/class/devcoredump/devcd*/data.

## Result: the devcoredump mechanism does not fire on this platform
- coredump knob set successfully: `modem rproc=remoteproc0 coredump=enabled recovery=enabled`.
- rtsar fatal fired as always: `qcom_q6v5_pas 4080000.remoteproc: fatal error received:
  rtsar_framework.c:3546:Smart Transmit License Check Failure Code (1, 1, 1)` at kernel
  uptime 58.4s, followed by `crash detected in modem: type fatal error` / `handling crash #1`.
- AFTER `handling crash #1` there is NO `recovering modem`, NO `stopped remote processor`,
  NO `coredump` line for the rest of the boot. The rproc recovery/coredump worker never ran
  to completion, so NO devcoredump device was created (`/sys/class/devcoredump` empty; no
  /root dump file). Enabling coredump (and by extension `inline`, which also needs the
  recovery path + dump segments) had no effect on this mainline qcom_q6v5_pas modem for this
  fatal path. The modem's F3/QSR ring could NOT be recovered this way.

## What WAS captured (the modem's secure-storage behaviour via the listeners)
- The only structured verdict the modem surfaced to HLOS is the SMEM crash reason itself:
  `Smart Transmit License Check Failure Code (1, 1, 1)` - identical to q6/every prior run.
- RPMB listener served many READ dispatches during the window: `cmd_id=258 (0x102)
  buf_len=20480`, all reads. ZERO write cmd_ids, ZERO RO-refusals, ZERO write/creat/unlink/
  rename syscalls anywhere in the strace. The modem/TA secure path is RPMB reads (served RO).
- persist was mounted RO and the PFM store (store_0..6, oem_stx_platform_license.pfm.inst,
  0-byte qls_hlos-timestamp) was visible to the session, but a QWES/listener consumer polled
  `/mnt/vendor/persist/data/pfm/licenses/store_0` and got ENOENT throughout the window (a
  mount-visibility/namespace difference for the listener). Crucially the rtsar verdict and its
  timing were byte-identical to q6 where that store WAS served RO -> the HLOS persist copy is
  NOT the gating input; the modem's StX check keys off the RPMB-backed secure store (and/or a
  non-storage precondition), not the persist plaintext copy.

## Interpretation
- "(1, 1, 1)" remains the modem's own three-field StX result, but the decoder for those three
  values lives in the modem's F3, which the devcoredump route cannot reach on this driver.
- The check is insensitive to the HLOS persist license copy (served vs ENOENT -> same crash,
  same 58s). Consistent with q7/q8: the license is present+valid+bound; the failure is
  enablement/restriction evaluated inside the modem+TA against the RPMB secure store or a
  non-storage precondition - NOT license presence and NOT the persist copy.

## Next hypothesis / next capture method
Since devcoredump is unavailable here, read the modem's own log directly instead:
- The rtsar string already proves the modem writes its crash reason to SMEM. Read the modem
  SMEM error/F3 MSG ring (debugfs `qcom_smem` / SSR err region) right after the fatal, in a
  trial, to recover the full reason behind "(1,1,1)" (response code / feature id / restriction
  the modem logged). Alternatively bring up the modem DIAG/F3 channel over qrtr during the
  check. Both are read-only observation paths (owner decision for the next approved trial).
- Leading hypothesis unchanged: a global enablement precondition (QWES secure-time/attestation
  / consumer-TA caller identity) the mainline stack doesn't satisfy, evaluated modem-side.

## Safety ledger
flag off; back on 7.3.0-rc6-dodge-gpu1; HASHES-UNCHANGED (12/12 incl. persist + qweslicstore
unchanged); persist sda2 sha256 before==after; oops=0; no writes attempted (listeners
read-only, confirmed in strace); reversible boot (nothing flashed). Dump: none produced, so
nothing to store/redact.
