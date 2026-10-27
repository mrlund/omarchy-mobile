# q6: persist-RO-mount modem-ON trial (StX/PFM license)

Date: 2026-10-27 (CET). Board: dodge (SM8750, CPH2653, slot _a, unlocked).
Kernel: 7.3.0-rc6-dodge-qtee1+ (ipa1 + CONFIG_QCOMTEE=y). Reversible `fastboot boot`,
nothing flashed. ONE boot consumed (authorised). Back on 7.3.0-rc6-dodge-gpu1 after.

## Goal
Test whether serving the real persist PFM license store READ-ONLY to QTEE (via the
qtee_supplicant FS listener) at /mnt/vendor/persist, mounted BEFORE MPSS, lets the modem's
Smart-Transmit (STx) license check pass. Follow-up to step-8 (persist PFM store found).

## Source partition (confirmed)
- persist = /dev/sda2 (LUN 0, 64 MiB, ext4, empty GPT PARTLABEL -> why by-partlabel
  scans on sde/sdf missed it in step 8). UUID 866e56d4-9344-48cf-8843-62f375277b94.
- Read-only image at /root/persist-ro/persist.img (made 2026-10-26) matches live sda2.
- sha256 (first16) before == after == b1cd8f9c5d72931b  (partition untouched).

## Store contents (names + sizes only; NO contents in repo)
/data/pfm/licenses/ :
  oem_stx_platform_license.pfm.inst  4375 B
  qls_hlos-timestamp                 0 B
  store_0 .. store_6                 184320 B each
(plus other .inst/.err licenses and storage.txt/check.bin as catalogued in step 8.)

## Procedure
Mounted persist RO at /mnt/vendor/persist via loop image (ro,loop,noload; opts observed
ro,relatime,norecovery) BEFORE starting MPSS. qtee_supplicant ran with RO FS + RO/refusing
RPMB listeners under strace (every request timestamped). QWES TA held resident via a
qwes_cli checkall keepalive. Then rmtfs/tqftpserv + MPSS start, watch registration/TX/rtsar.

## Result: STILL FAILS, identically
[49.403054] qcom_q6v5_pas 4080000.remoteproc: fatal error received:
  rtsar_framework.c:3546:Smart Transmit License Check Failure Code (1, 1, 1)
mpss crashed; never registered (stuck searching); no data bearer; no ping.
Timeline: persist mounted at up=26s; MPSS started up=26s; crash at kernel 49.4s (mpss had
persist mounted + served for its entire ~23s run). So the mount was NOT too late.

## Decisive evidence (why serving persist RO is necessary-but-insufficient)
1. FS listener DID serve the pfm dir RO post-mount: ~194 successful opens (fd=7) of
   /mnt/vendor/persist/data/pfm and /licenses/.
2. But the modem OPENED the licenses directory (probe) and then NEVER read the license
   files: zero successful store_* opens post-mount, and getdents_count == 0 (the directory
   was never enumerated by anyone). It does not pull store_*/oem_stx*.pfm.inst through the
   FS listener.
3. RPMB listener active: cmd_id=258 (0x102), buf_len=20480, dispatched repeatedly during
   the modem window. NO write-refusals were logged -> the modem's RPMB traffic this window
   was reads/auth, not writes we blocked.
4. QWES feature licences 600..619 all return Status 1 (licensed) via the TA -- unrelated to
   StX; confirms QWES feature-licensing != StX/PFM licensing.

This matches the StX chain already documented: modem -> IPFM_CheckInstalledLicense ->
qsee_open (QTEE) -> QWES/IPFM TA -> INSTALLED license in RPMB-backed secure storage. The
modem reads the *installed* license from RPMB via the TA; it does NOT read the plaintext
persist PFM files directly. The persist /data/pfm store is the PROVISIONING SOURCE that
qwesd would install into RPMB -- not the thing the check reads.

## Note on the "corrupted path" log artifact (ruled out as a bug)
Early (pre-mount) supplicant errors show a mangled path
"dir_open: directory does not exist: /mnt/ven\xFD\xFF\xFF\xFFpersist/data/pfm/licenses/".
This is COSMETIC, not a path-construction bug: dir_open is dispatched with req and rsp
sharing one buffer; tz_dir_open_rsp_t.ret sits at buffer offset 12 (== pathname[8]); on the
error path ret = E_FS_DIR_NOT_EXIST = -3 = 0xFFFFFFFD is written BEFORE the error string
prints pathname, so the response code bleeds into the aliased path. opendir() used the clean
path and failed only because persist genuinely was not mounted yet in that window (the QWES
TA checkall at up=24s polled pfm ~2s before the mount landed at up=26s). Post-mount the same
opens succeed (fd=7). No functional impact; worth a cosmetic fix (print before setting ret).

## Conclusion / decision point for Martin
Having the persist PFM provisioning store present and readable is NECESSARY but NOT
SUFFICIENT. The modem's StX check reads the INSTALLED license from RPMB via the QWES/IPFM
TA. Installing persist -> RPMB would require BOTH (a) a working qwesd QMI responder (closed
bionic prebuilt; does not run on our glibc mainline without a container/libhybris) AND
(b) RPMB secure-storage WRITES -- which the standing hard rules explicitly forbid (RPMB
listener logs+refuses every write; TA lives in QTEE memory only; no secure-storage writes;
no fake/hard-coded license responses). So this persist-RO path is blocked by the standing
constraints. STOP and report; the go/no-go on any RPMB-write provisioning path is Martin's.

## Hard-rules compliance
No persist/partition writes (sda2 sha256 before==after). Listeners read-only; no write
forwarded to the device. No fake/hard-coded license. MPSS not stopped. All 12 tracked
partition hashes unchanged (modem_a/b, modemst1/2, fsg, fsc, oplusdycnvbk, oplusstanvbk_a/b,
qweslicstore_a/b, persist:sda2). Reversible boot; EFS+tqftpserv backups taken. oops=0,
warn=4. Phone restored to 7.3.0-rc6-dodge-gpu1, modem flag off, battery 100%, fs clean.
