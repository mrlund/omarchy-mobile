# qwes-xlat step 7 (alt #3, step 1 static): the QWES license path is NOT a qrtr QMI service (2026-10-27)

Goal of alt #3: a minimal responder that answers the modem's QWES **QMI** license request by
relaying to the real TA via libqwes. Step 1 (static, no boot) was to find the qmi_idl_service_object
and the qwesd request handler. **Finding: that QMI service does not exist.** The modem's Smart-Transmit
license check is a secure/QTEE (qsee) path, not an apps-side qrtr QMI service. Evidence below.
**0 of 2 boots used. All protected partitions hash-identical to baseline; phone on gpu1, modem off.**

## 1. qwesd is NOT a qmi_csi (qrtr) server
- DT_NEEDED lists libqmi_csi.so, but qwesd's ONLY imported qmi_csi symbol is
  `qmi_csi_send_broadcast_ind`. It imports **no** `qmi_csi_register` /
  `qmi_csi_register_with_options` / `qmi_csi_handle_event`, and does **not** dlsym them
  (no such names anywhere in its rodata).
- The single `qmi_csi_send_broadcast_ind` call (0xc3b8) is made with a **NULL service handle**:
    c3a8 mov x0, xzr      ; service_handle = NULL
    c3ac mov w1, #0x22    ; msg_id = 34
    c3b0 mov w3, #1 ; c3b4 strb wzr,[sp,#0x40]  ; 1-byte body = 0
  A NULL-handle broadcast is a no-op — qwesd holds no CSI service handle because it never
  registered one. So there is **no qmi_idl_service_object that qwesd publishes on qrtr**, and
  nothing for a modem QMI client to look up. (Matches step-4: qwesd registered nothing on qrtr.)

## 2. qwesd is a Mink CLIENT to the secure world (provisioning/sync), not a modem-facing server
- Imports/strings: `TZCom_getRootEnvObject`, `registerClientEnv`, `IClientEnv_open(%u) returned %d`,
  `MinkIPC_connect`/`MinkIPC_release` to `"/dev/socket/ssgtzd"`. This is the standard QTEE
  ClientEnv path: qwesd authenticates a client env and **invokes** the QWES TA (via libqwes:
  GetQwesService → QWES_Agent_* = Install/Check/Sync/Get_License_Info). Its config/endpoints
  (`/data/vendor/qwes/qwesd.conf`, `token_cert`, `https://api.qwes.qualcomm.com/api/d2c`) show its
  job is license provisioning + cloud token sync — a TA client, not a QMI server.

## 3. The modem's Smart-Transmit license check is a secure (qsee/QTEE) path, no QMI
- modem_a strings: `CommonUtils_IPfmOpen`/`IPfmClose`, `IPFM_CheckInstalledLicense`,
  `IPFM_GetInstalledLicenseInfo`, `IPFM_CheckLicenseBuffer`, and crucially
  **`IPFM qsee_open() failed %d`** and `IPFM pointer is null` — the feature-license app opens a
  **secure (qsee) session**, not a qmi_client. The validation handlers it drives
  (`LicenseValidateAndEnable_Handler`, `CFE_ValidateLicense`, `GetTx2xLicensedConstant`,
  `GetTx2xWrappedLicensedConstant`) are TA-side.
- The modem exposes/uses many QMI service objects (WLFW, NAS, loc/qmiLoc, SNS, fs) but a grep for
  **any** QWES qmi service object / `qwes*_v0x` / `QMI_QWES` / qwes qmi_client returns **nothing**.
  So the modem does not reach QWES over QMI at all.

## Conclusion: alt #3 as specified has no target
A `qmi_csi_register`-on-qrtr responder (directive steps 2-4) would never be contacted by the modem:
the modem's rtsar/Smart-Transmit license check (`rtsar_framework.c:3546 (1,1,1)`,
`IPFM_CheckInstalledLicense`) is served inside QTEE via `qsee_open` to the QWES/feature-license TA,
entirely in the secure world. Apps-side qwesd only provisions/syncs that TA. No faked answer was,
or could be, produced; nothing was built or booted.

## Recommended redirect (aligns with the project's original translator framing + hard rules)
The real satisfier is almost certainly **secure-world residency/serviceability of the QWES TA when
the modem does its qsee_open**, not an apps QMI responder:
- Ensure the QWES/feature-license TA is loadable/resident in QTEE at modem bring-up (step 3B already
  loaded it into QTEE memory via the libminkdescriptor -> /dev/smcinvoke -> qcomtee shim and read the
  installed license back from the REAL TA, nothing faked, nothing persisted).
- Provide the apps-side **listeners the TA needs while the modem drives it**: RPMB (read-only: log +
  refuse every write, never forward to device) and persist/qweslicstore served **read-only** — exactly
  the listeners the standing hard rules already scope. The modem's IPFM qsee_open likely fails on
  qtee1 because those secure-storage listener callbacks are unserviced, not because any QMI service
  is missing.
This needs direction before building: it is a different (larger) design than a QMI responder, so per
"stop at a blocker bigger than ~half a day" I stopped here and am reporting rather than booting.
