# q8 — Decoding restriction mask 11 on FID 1118 (and why it is NOT 1118-specific)

Date: 2026-10-27 (Europe/Copenhagen). Kernel: 7.3.0-rc6-dodge-qtee1+ (trial).
Method: ONE reversible modem-OFF `fastboot boot` (nothing flashed), persist mounted
read-only, QTEE FS+RPMB listeners read-only. No install/remove, no sync/force-sync,
no writes. All 12 partition hashes identical before/after (persist b1cd8f9c…,
qweslicstore 879c097b…). Reproduces/extends the q7 finding. Describe-only: no
serials, identifiers, firmware, TA or .pfm contents are stored here.

## What we set out to decode
q7 showed StX feature **1118 installed but Status 0, Restrictions 11 (0b1011,
bits 0/1/3)** while a control feature read Status 1. The task: find the restriction
bit definitions and classify what would satisfy each.

## Static source hunt for a restriction-bit map — NEGATIVE
Exhausted every available source; none defines the restriction-mask bits:
- minkipc QWES IDLs (IQWESTAServices/CQWESTAServices/IQWESKeyStore/IProvisioning/
  IDeviceAttestation): only service IDs + attestation security levels; no license
  restriction enum. `createServiceById(license, serviceId, service)` is the only
  license-touching method; the restriction value is a field of the TA's CBOR
  response, not an IDL constant.
- qwes_cli / libqwes.so: print the value as a raw number only
  ("License install succeeded. Restriction mask %llu", "Restrictions %ld",
  "LicenseRestrictions:"). No bit-name table. They DO expose a sync/time path
  (QWES_Agent_Force_Sync, Register_Sync_Callback, ToTime, /dev/socket/qwes_ipc,
  /dev/socket/ssgtzd).
- Public (Qualcomm WES/SoftSKU docs, CodeLinaro/meta-qcom, QCBOR, FCC StX filings):
  no public bit map. Useful facts only — see below.
Conclusion: the restriction-mask bit semantics are internal to the closed QWES TA.
We will NOT fabricate per-bit definitions.

## Decisive new data (q8 read-only queries)
Per-FID CheckFeatureEnablement across ALL 18 installed FIDs + the [1600,1601] range,
plus GetInstalledLicenseInfo on the 1118 license:

- **Every stored PFM license reports Status 0 with Restrictions 11** — 1118 is
  identical to its peers (1000/1003/1105/1109/1112/1117/1119/1122/1136/1144/1600/
  1601/2900..2903/2912/2913). The only outliers: FID 210 = Restrictions 32 (also
  Status 0); the built-in control feature = Status 1 with NO restrictions printed
  (mask 0).
- **GetInstalledLicenseInfo(1118) returns `LicenseRestrictions: 11` directly from
  the installed license record** (info_len 396, LicenseeHashes empty). So **11 is a
  static, signed property baked into the license at provisioning time** — not a
  runtime "you failed these checks" value, and not corruption.
- RPMB reads succeeded through the read-only listener (the TA read each license);
  this is NOT an RPMB-provisioning or storage-access failure.

## Interpretation
1. Mask 11 is the ORDINARY restriction set these CHIPSET_OEM licenses are ISSUED
   with — uniform across the device. 1118 (Smart Transmit) is in no way special,
   not extra-restricted, not expired, correctly present.
2. The bits are declarative license CONSTRAINTS, not clearable flags. They cannot be
   "cleared" (they are inside the signed license); the environment must SATISFY them.
   Mapping 0b1011 to the license's own declared binding fields in the StX .inst
   (describe-only): licenseHardwareVersions 0xA012 (chipset/HW bind),
   licenseOEMIDs 51 (OEM bind), and an expiration/validity extension (INCLUDE_
   EXPIRATION_EXTENSION). HW+OEM binds MATCH this exact device, so those constraints
   are satisfiable/satisfied here. (Labelled inference — no authoritative bit map.)
3. The real signal is that **every stored license uniformly reads "not enabled" in
   our mainline environment while the unrestricted built-in reads enabled.** That
   points to a GLOBAL enablement precondition the mainline stack does not provide —
   the same precondition the modem's own IPFM check needs and fails (the StX
   (1,1,1) crash). Leading candidate: QWES secure HLOS time / provisioning sync —
   `qls_hlos-timestamp` is 0 bytes and there is no time_daemon/QMI-time/Force_Sync
   feeding the TA. Secondary candidate: a consumer-TA caller identity / attestation
   context our bare qwes_cli+minimal supplicant does not present (so our userspace
   check may not be a faithful proxy for the modem's path).

## Classification (satisfy, not clear)
- HW-version bind (0xA012): SATISFIED on this device — not the blocker. [read-only / already true]
- OEM-ID bind (51): SATISFIED on this device — not the blocker. [read-only / already true]
- Validity/secure-time (expiration extension; qls_hlos-timestamp empty): NOT satisfied
  under mainline. Providing it persistently is a WRITE to persist
  (`.../pfm/qls_hlos-timestamp`) and/or an RPMB secure-time record — barred by our
  rules. [needs a write — named]
- Consumer-TA caller identity / attestation context: cannot be fully emulated by our
  harness; this is the modem's IPFM client on stock Android. [impossible without
  Qualcomm/Android; partially confirmable]

## Bottom line
No license install or RPMB license write is warranted — the license is present,
valid, correctly bound, and normally restricted. The defect is ENABLEMENT, gated by
a global precondition (most likely QWES secure-time/sync, possibly caller/attestation
context) that mainline does not supply — which is exactly what makes the modem's own
STx license check fail.

## Recommended next step
To distinguish time-sync vs caller-context as the enablement gate, capture the
MODEM's own IPFM failure detail at the crash: its
`license check failed! response code %li feature id %li` + `LicenseRestriction`
runtime values. That needs a modem-ON crash-repro boot with modem logging — a
decision point for the owner, since it is no longer a modem-OFF read-only step.
A read-only alternative first: confirm whether any sanctioned, non-persistent way
exists to feed the QWES TA an HLOS timestamp for the duration of a single enablement
query (no persist/RPMB write) and re-run checkall.

## State
Phone restored to 7.3.0-rc6-dodge-gpu1; modem flag off; battery 100%; all mounts
cleared; 12/12 partition hashes unchanged (persist b1cd8f9c…).
