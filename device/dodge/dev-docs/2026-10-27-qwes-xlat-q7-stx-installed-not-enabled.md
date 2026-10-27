# q7: Smart Transmit license is INSTALLED but reports enablement Status 0 (read-only, modem OFF)

Date: 2026-10-27 (approved 10:56). Settles, read-only, whether the TA reports the Smart
Transmit (StX) license as installed + licensed. NO modem start, NO writes of any kind.
One reversible `fastboot boot` of the qtee1 trial kernel (nothing flashed); persist mounted
read-only (image loop of a prior RO copy); qtee_supplicant RO FS+RPMB listeners; only
read-only `qwes_cli` queries. All 12 protected partition hashes unchanged; persist sha
`b1cd8f9c…` before == after; back on gpu1 afterward.

(Describe-only: no device identifiers, license serials, firmware/TA bytes, or .pfm/.inst
contents are recorded here. The provisioning manifest and its certificate were parsed
host-side only.)

## The StX feature ID, from the persist provisioning manifest
`data/pfm/licenses/oem_stx_platform_license.pfm.inst` is an ASCII JSON manifest (+ a signing
certificate), NOT a binary blob. It names the feature plainly:
- feature = "Smart Transmit", **licenseFeaturesId = 1118**
- deviceFileName encodes `…-no-exp-…` → **no expiration**; graceCount/gracePeriod = 0
- PRODUCTION / CHIPSET_OEM, bound to this SoC (SM8750 / 0xA012), production-signed
- embedded expiration-extension (CBOR) decodes to `{…: {1118: true}, …: [1,0]}` → feature 1118 marked enabled in the manifest
So the StX feature ID is **1118**, and the license carries no time/expiry gate.

## Does the TA report 1118 installed + licensed? (the crux)
With persist served read-only to QTEE and the modem OFF:
- `qwes_cli listfids` (GetAllInstalledFeatureIDs) → **18 FIDs INCLUDING 1118**
  (210, 1000, 1003, 1105, 1109, 1112, 1117, **1118**, 1119, 1122, 1136, 1144, 2900–2903,
  2912, 2913) + range [1600,1601]. A license record for 1118 exists (a serial is returned).
  → **1118 IS INSTALLED.** No install, no RPMB write is required. (This overturns the q6
  "needs RPMB writes" reading: the factory license is present.)
- `qwes_cli -i 1118 check` / `checkall` → **Feature ID 1118, Status 0 (NOT enabled),
  Restrictions 11**, serial present.
- Control `qwes_cli -i 600 checkall` → **Feature ID 600, Status 1 (enabled)**.
→ The TA works (600 = enabled) and sees 1118 installed, but reports **1118 enablement
  Status 0** with a restriction mask of **11**. The StX license is *installed but not
  currently enabled* — not missing, not expired.

Note: 1118 is NOT in the 600–619 band that earlier checkall/3B runs probed, which is why
prior runs (Status 1 for 600–619) never actually exercised the StX feature.

## The FS listener is NOT the bug (getdents=0 from q6 explained)
This time persist was mounted before the listener started. strace of the RO FS listener shows
QTEE successfully:
- enumerated the licenses dir via `getdents64` (returned 12 then 37 entries; 368 / 2168 bytes),
- opened and read `store_0..store_6` and `oem_stx_platform_license.pfm.inst` read-only (fds 7/8).
No write/creat/unlink/rename attempts, no RO refusals. So the q6 `getdents=0` was the
pre-mount window / an aborted earlier step, **not a minkipc fs-listener dir-read bug**. The
listener serves the PFM store correctly, read-only.

## Best reading of the modem's `rtsar_framework.c:3546: …Failure Code (1,1,1)`
Modem strings (modem_a, decompressed image segments) give the IPFM license-check chain and
its loggers, in order:
`DeviceID qsee_open() failed` → `IPFM qsee_open() failed` → `IPFM_CheckInstalledLicense failed`
→ `CommonUtils_IPfmOpen` → **`license check failed! response code %li feature id %li`** →
**`LicenseRestriction`**. The qsee_open path returned (qwes_cli proves QTEE/TA reachable), the
license IS installed, and it is the *restriction/enablement* that is not satisfied — matching
the TA's "1118, Status 0, Restrictions 11". The literal 3-arg `(%d,%d,%d)` format string was
not recoverable from the extractable FAT segments, so the exact field decode is not asserted;
but the three codes are the StX check-failure triple for a **present-but-not-enabled** license
(feature 1118), NOT "not installed" and NOT "expired" (the license is no-exp).

## Secure time
`qls_hlos-timestamp` is 0 bytes. Because the StX license is no-exp (cert validity effectively
unbounded), expiry/secure-time is ruled out as the direct cause. A time/counter *restriction*
bit inside mask 11 remains a secondary possibility but is not the primary gate.

## Next concrete hypothesis
The blocker is **StX license enablement**, not presence. `Restrictions 11` (0b1011) on an
otherwise-installed 1118 license is why both `qwes_cli check` (Status 0) and the modem's
IPFM check fail. Next step: decode the restriction-mask bits (what binding/condition bits 0,1,3
require) and determine why 600 enables (Status 1) while 1118 does not under mainline — i.e.
which enablement precondition the StX feature needs that is currently unmet. This is a
read-only decode + reasoning step; no writes and no further boots implied yet.

## State
Reversible `fastboot boot` only (nothing flashed); modem stayed OFFLINE the whole session;
listeners read-only; persist RO (loop image of a prior copy, real sda2 never opened for write).
persist sha `b1cd8f9c…` before == after; all 12 protected partition hashes unchanged; rootfs
clean; oops=0. Device back on gpu1 with the modem flag off.
