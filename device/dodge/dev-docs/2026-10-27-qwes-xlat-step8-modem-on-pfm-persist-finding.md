# dodge QWES-xlat — Step 8: modem-ON trial on qtee1 (TA resident + RO listeners). Root cause isolated to the persist PFM license store.

Date: 2026-10-27 (Europe/Copenhagen)
Kernel: 7.3.0-rc6-dodge-qtee1+ (= ipa1 + CONFIG_QCOMTEE=y). QTEE 5.2.0, /dev/tee0.
Boot: reversible `fastboot boot` of the full-rootfs chain image (nothing flashed), 480 s soak deadline, host watchdog. 1 boot consumed.

## What was tried (approved redirect)
Hypothesis under test: in Step 4 the vendor qwesd parked and never loaded the QWES TA; in Step 3B `qwes_cli` loaded it and it answered "licensed". So this trial loaded the QWES TA via the proven `qwes_cli` path and kept a client holding it, with the qcomtee userspace stack up BEFORE the modem, and logged every HLOS request QTEE makes.

Stack brought up before MPSS, all read-only:
- `qtee_supplicant` with the RO **RPMB** listener (write-refusing, log-only) and RO **FS** listener (all opens forced O_RDONLY, writes refused). Supplicant run under `strace -ttt -f` tracing every open/read/write/ioctl → complete timestamped record of what QTEE asks HLOS for.
- bionic env (erofs system/vendor/apex ro + binds); modem_a mounted RO at /vendor/firmware_mnt.
- `qwes_cli checkall` to load+exercise the QWES TA over libqwes → our smcinvoke→qcomtee shim → /dev/tee0; plus a keep-alive re-checkall loop during the modem window.

HARD RULES honored: no secure-storage writes; real partitions untouched; listeners read-only; no fake/hard-coded license; MPSS never stopped; TA image only ever read RO. qweslicstore_a/b forced RO by the kernel at boot. All 11 protected partition hashes **unchanged** before/after. oops=0.

## Results
1. **QWES feature license is fine.** `qwes_cli checkall` → for every feature ID 600–619: `CheckFeatureEnablement succeeded`, `Status 1` (licensed). The QWES TA loads and validates from HLOS userspace exactly as in 3B. (The "Failed to write /data/vendor/qwes_test/*.cbor" lines are the client failing to save its own response to a non-existent rootfs test dir — not a partition/listener write.)
2. **rtsar STILL FAILS, identically.** `qcom_q6v5_pas 4080000.remoteproc: fatal error received: rtsar_framework.c:3546:Smart Transmit License Check Failure Code (1, 1, 1)` at modem-uptime ~58 s. Modem crashed; never registered (stuck "searching"); provisioning/online timed out because the modem was already going down.
3. **The TA image is not pulled from HLOS and the client-residency theory is moot.** `/vendor/firmware_mnt/image/qwes.mbn` does not exist on this modem_a; strace shows **zero** qwes.mbn reads, yet CheckFeatureEnablement still succeeds → the QWES TA is already resident in QTEE (served by QTEE from secure firmware), so loading/holding it from a client has no bearing on the modem's own secure qsee_open.

## Root cause isolated (the listener log is decisive)
During the modem's license check, QTEE drove the FS listener to open the modem's **PFM (Persistent Feature Management) license directory**, and every attempt returned ENOENT:

```
265x  openat("/mnt/vendor/persist/data/pfm")                 = -1 ENOENT
265x  openat("/mnt/vendor/persist/data/pfm/licenses/")       = -1 ENOENT
105x  openat("/mnt/vendor/persist/data/pfm/licenses")        = -1 ENOENT
 ~15x each  .../pfm/licenses/store_0 .. store_6              = -1 ENOENT
```

So the modem's Smart-Transmit (rtsar) license check reads its license from the **persist partition's PFM store** — `/mnt/vendor/persist/data/pfm/licenses/store_0..store_6` — served to QTEE by HLOS via the FS listener. In this trial persist was never mounted at /mnt/vendor/persist, so the whole PFM tree was absent → dir_open fails repeatedly → the modem's license check fails (1,1,1) and q6v5 takes the fatal.

This is a **different store** from the QWES feature license. The QWES feature license (feature IDs 600–619, exercised green by qwes_cli, backed by the QWES TA + qweslicstore) is present and valid. The Smart-Transmit/rtsar license is PFM-in-persist and was simply not available to QTEE in the trial environment.

Per the vendor fstab (vendor_a `etc/fstab.qcom`): `/dev/block/bootdevice/by-name/persist  /mnt/vendor/persist  ext4` — i.e. persist is an ext4 partition the stock stack mounts at /mnt/vendor/persist, and the PFM licenses live under it.

## Best next hypothesis
Provide the modem's PFM license to QTEE **read-only**: before MPSS, mount the device's real persist partition read-only at `/mnt/vendor/persist` (or have the FS listener serve `data/pfm/licenses/` RO from it), so the Smart-Transmit license check can read `store_0..store_6`. Nothing is faked — the check would read the device's own provisioned PFM license. This stays inside the hard rules (persist read-only, no writes).

### Open sub-question to resolve first (no boot needed)
This device's GPT, as seen by mainline, exposes **no `persist` partlabel** — only an erofs `vm-persist` (sde78). The vendor fstab references `by-name/persist` (ext4), but no such partition appears in /dev/disk/by-partlabel (full label list captured in the session log). So before the next trial we must determine where this OnePlus 13's PFM/persist store physically lives (candidate labels to check RO: featenabler_a/b, oplusreserve1..5, mdm1oemnvbktmp, secdata, param), or establish whether the PFM license set was ever provisioned on this unit at all (which, if empty, would mean Smart-Transmit cannot pass without provisioning — a separate problem).

## Artifacts (on-device, redacted; not committed)
/root/q5-supplicant.strace (full request trace), /root/q5-supplicant.log, /root/q5-qwescli.log, /root/q5-keepalive.log; host logs logs/p73-q5-*.txt. No identifiers/firmware/TA/.pfm blobs in the repo.
