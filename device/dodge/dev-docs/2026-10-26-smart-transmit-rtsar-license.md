# Smart Transmit / RTSAR license on dodge (SM8750) — can we turn it off, and run it ourselves?

Read-only research, 2026-10-26. No boots, no NV/EFS writes, nothing applied.
Describes items and mechanisms only — no identifiers, no license or calibration contents.

## The problem (recap)
Modem goes online, then at real TX bring-up the mpss throws:
`rtsar_framework.c: Smart Transmit License Check Failure Code (1,1,1)` -> fatal -> SSR loop.
Smart Transmit (STx) = Qualcomm time-averaged TX-power / SAR-compliance limiter (RTSAR
framework). It is a **licensed** modem feature. The crash is the modem failing to
validate that license at TX enable. On mainline nothing supplies the license.

## 1. The control — which EFS/NV items?
Found on-device by scanning the writable modem-efs copies + NV-backup blobs (names only):

- `/nv/item_files/mcs/lmtsmgr/sar/rtsar/rtsar_config` — THE RTSAR/Smart Transmit config
  item (under the modem Limits Manager, lmtsmgr). Confirmed as the canonical RTSAR item
  across multiple Qualcomm basebands. Holds the STx enable/mode, SAR_time_window,
  regulatory body (FCC/ICNIRP), Reserve_power_margin, and references the per-band/tech/DSI
  Plimit set. Its binary layout is NOT public.
- `/oem/oem_sar_dsi_config` — OEM SAR Device-State-Index config (selects which Plimit set
  applies per folder-open/closed / body / head state).
- `/nv/item_files/modem/lte/rrc/ampr_configured_ns.xml`, `/nv/item_files/modem/nr5g/RRC/llcdb_ampr_info`
  — A-MPR (Additional Max Power Reduction): static regulatory emission back-off per band,
  ALWAYS applied, independent of SAR/STx. Not a body-SAR cap.
- `/nv/item_files/mcs/lmtsmgr/vbatt/{vbatt_limits,vbatt_mode}` (+ gsm/lte/nr5g variants on
  other basebands) — battery-voltage TX-power limits, always applied, not SAR.

There is **no standalone "STx enable" boolean item** and **no legacy static-SAR table**:
on this device SAR limiting is RTSAR-only, and the enable lives inside `rtsar_config`.

## 2. Fallback behaviour when STx is off (FCC/Qualcomm evidence)
OnePlus 13 = FCC ID 2ABZ2-AA534 (CPH2513/CPH2515), plus Qualcomm STx whitepapers in
several FCC filings. Key documented facts:
- STx controls instantaneous TX power so the TIME-AVERAGED power stays <= Plimit (the
  per-band power that corresponds to the SAR design target). Instantaneously it may burst
  up to Pmax (the RF tune-up max output power).
- **With STx DISABLED (the lab "Pmax" state): the device transmits up to Pmax — i.e. the
  full calibrated max output power, with NO time-averaging cap.** Pmax is the normal
  cellular ceiling (≈ power class 3: ~23 dBm / 200 mW for LTE/NR sub-6; up to ~33 dBm for
  2G). So "off" is not "infinite" — it's the ordinary max TX power a phone without STx
  would use — but it removes the body-SAR time-averaging protection.
- **Fixed-cap mode DOES exist but only WITH STx enabled:** set Reserve_power_margin = 0,
  then Preserve = Plimit and STx hard-caps continuous TX at Plimit (no bursts). This is the
  documented "static cap at Plimit" mode. It still requires the STx license, so it does NOT
  avoid our crash.
- There is **no documented license-free static-SAR cap**. Applying the Plimit table as a
  hard cap IS the licensed STx feature.

So: the only EFS lever that could both stop the crash AND keep the modem transmitting is
DISABLING RTSAR in rtsar_config. That would (if the modem then skips the licensed path)
leave TX at Pmax, capped only by A-MPR + vbatt + network power control — i.e. no body-SAR
protection. Whether disabling it actually bypasses the license check is UNVERIFIED (the
check may run at modem init regardless of config). It is also an undocumented-layout binary
EFS write, RF-compliance-breaking, and would need exact backup/restore (we already back up
EFS every boot).

## 3. Has anyone done this on mainline / community?
No public pmOS / linux-msm / lore / XDA report of "Smart Transmit License Check Failure" or
of disabling RTSAR via `rtsar_config` was found. Qualcomm/FCC sources and general EFS-tool
docs only. This looks like an undocumented QWES/licensing gap for mainline on these SoCs,
not a known kernel/IPA bug. EFS edit tooling that exists (DIAG-based, e.g. catxeon/
qcom-efs-browser read-only-by-default; mtbtool feature NV writes) can read/write EFS/NV with
SPC unlock, but none document an STx/RTSAR toggle.

## 4. The QWES side — what supplies the license, and can we run it?
On stock, STx licensing is served by **QWES** (Qualcomm Wireless Edge Services). On-device
we have the daemon `qwesd` + `qwes_cli` (staged on the writable side), the persist pfm
license store (STx license present and installed), and the qwes license-store blobs.

### What qwesd actually needs (from its ELF + strings, read-only)
- Interpreter `/system/bin/linker64`, built for Android 35 => it is a **bionic** binary.
- NEEDED: libqmi_csi (runs as a QMI *service* over QRTR — how it answers the modem),
  libQSEEComAPI (TrustZone), libminksocket_vendor + libminkdescriptor (MINK object-IPC into
  TZ), libcurl + libdsi_netctrl (optional device-to-cloud license fetch at
  api.qwes.qualcomm.com), libcrypto, libqcbor, bionic libs.
- Strings confirm a TrustZone dependency: `/dev/socket/ssgtzd`, `TZCom_getRootEnvObject`,
  `HavenToken` attestation, with a "TZD connection failed; falling back" / "test_mode token"
  path. So real license attestation needs TZ; a degraded test-mode exists but would not
  produce a license the modem accepts.

### Is there a non-bionic build? YES
`qualcomm-linux/meta-qcom` ships a **native glibc** QWES recipe (`qwes_1.0.bb`, aarch64,
systemd service, `DEPENDS = curl minkipc qmi-framework glibc`), committed by a core
linux-msm dev. So a glibc qwesd exists (prebuilt on softwarecenter.qualcomm.com, likely
gated) that avoids Waydroid/bionic entirely. Its deps are open:
- `qualcomm/qmi-framework` (BSD-3) — the qcsi/qcci QMI transport.
- `qualcomm/minkipc` (BSD-3) — MINK object-IPC over TEE/smcinvoke/sockets/SMC.

### The real blocker is TrustZone + RPMB, not bionic
dodge 7.3 kernel config: `QCOM_SCM=y`, `QCOM_QSEECOM=y`, `QCOM_TZMEM=y` (SHMBRIDGE),
`TEE=y`. BUT **`CONFIG_RPMB` is NOT set**, and at runtime there is **no `/dev/qseecom`,
`/dev/smcinvoke`, or `/dev/tee*`** node. Mainline QSEECOM is in-kernel (UEFISECAPP) and does
not expose the userspace TZ char device that libQSEEComAPI/minkipc need; no QTEE backend is
built. QWES license install/attestation requires RPMB provisioned (Qualcomm docs) — RPMB is
absent here. So even the glibc qwesd cannot complete real attestation on this kernel as
configured: no userspace TZ transport, no RPMB. QMI/QRTR itself IS available on glibc
(qmicli, qrtr-lookup present).

### Halium / libhybris distros (Droidian, UT, Sailfish/FuriOS)
They run Android vendor blobs in an LXC Android container on a glibc host. None were found
to run qwesd/QWES on SM8550/8650/8750 — their modem path is RIL/ofono2mm in the container,
and they don't document QWES/STx licensing. So no ready-made recipe to copy.

### No open QWES reimplementation
qwesd and the QcWES TA are proprietary/prebuilt. Only the transports (qmi-framework,
minkipc) are open. The QWES QMI message set is not publicly documented. qwes_cli usage is
documented (`qwes_cli -f <fp>.pfm install` / `list`, needs RPMB) but that installs into the
store; it does not replace the modem's runtime license query.

## Ranked options (feasibility / effort / risk / evidence)

1. **Park the modem.** gpu1 default already ships with the modem flag off; everything else
   on dodge works. Zero risk. (Baseline if the below are judged not worth it.)

2. **Disable RTSAR via `rtsar_config` EFS edit (Martin's 1st choice).**
   - Feasibility: PLAUSIBLE but UNVERIFIED — may or may not bypass the license check.
   - Effort: medium. DIAG/EFS write to one item of undocumented binary layout; needs a
     careful read-modify-write + guaranteed restore. One test boot to see if the crash
     clears. (Not this run — writes are off.)
   - Risk: HIGH on RF compliance — if it works, TX runs at Pmax with NO body-SAR cap, only
     A-MPR/vbatt/network control. Corruption risk on a binary item (mitigated by our EFS
     backups). Reserve_power_margin=0 does NOT help (keeps STx licensed → still crashes).
   - Evidence: item path confirmed; FCC docs on Pmax/off behaviour. Bypass-of-check is the
     open unknown.

3. **Run glibc qwesd to observe its QMI exchange with the modem (Martin's 2nd choice,
   research).**
   - Feasibility: PARTIAL. Can likely get qwesd (glibc build or bionic-in-container) to
     start and register its QMI service over QRTR, and CAPTURE the request/response to the
     modem — even if attestation fails. Cannot make it serve a VALID license without TZ +
     RPMB.
   - Effort: HIGH. Obtain glibc qwesd (Qualcomm software center, likely access-gated) OR run
     the bionic qwesd in a Waydroid/LXC Android container with a /system + vendor libs;
     build/ship qmi-framework + minkipc; bridge QRTR into the container; add QMI tracing.
     To go beyond observation you'd additionally need: a mainline userspace TZ transport
     (/dev/smcinvoke or QSEECOM char dev, or the QTEE driver) + the QcWES TA loadable +
     `CONFIG_RPMB` enabled and RPMB provisioned. That is a substantial kernel+userspace
     effort with uncertain payoff (TA + RPMB provisioning are OEM/secure).
   - Risk: LOW (observation only; no RF change). Mainly time.
   - Evidence: ELF NEEDED list; meta-qcom glibc recipe; kernel config gaps (RPMB off, no TZ
     node); open qmi-framework + minkipc.

4. **Bring up the full QWES stack to actually license STx.** Needs items in (3) PLUS a
   working TZ path and provisioned RPMB on SM8750 mainline. Highest effort, uncertain it is
   even possible without OEM secrets. Not recommended now.

## Recommendation
- For "get the modem working": the ONLY EFS lever that could stop the crash while keeping TX
  is disabling RTSAR in `rtsar_config` (option 2) — but it is unverified to bypass the
  license check and, if it works, removes the body-SAR cap (TX at Pmax). There is no
  documented license-free fixed/averaged cap. If Martin accepts the RF-exposure trade-off on
  a dev device, option 2 is the single most promising next experiment: one EFS write + one
  test boot, with our existing EFS backup/restore. Treat it as experimental, reversible, and
  one-change-per-boot.
- For understanding: option 3 (observe qwesd's QMI exchange) is low-risk and would tell us
  exactly what the modem asks for and whether a license response alone (without the full TZ
  attestation) is accepted — worth doing as research before investing in option 4.
- Park (option 1) remains the safe default until one of the above is chosen.
