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

## Write-method investigation (2026-10-26 16:37-16:50, after Martin approved an STx-off test)
Goal: switch STx off in the writable copies only, one test boot. Result: STOPPED before any
write/boot - no clean method exists on this mainline kernel. Copies only read; real
partitions untouched; phone left gpu1, flag off, copies pristine.
- Runtime (modem writes the item via DIAG/QMI so rmtfs persists it): NOT AVAILABLE. No
  /dev/diag, no DIAG_CHAR, no diag-router; qmicli has no EFS/NV item write. No in-kernel diag
  char device for the SoC modem on mainline.
- Offline edit: rtsar_config is absent from the live EFS2 images; it exists only in
  oem_stanvbk (OEM static NV backup), which the modem DOES read at boot via rmtfs (linux-msm
  rmtfs PR #33). But each of the 8 records stores the config as a ZLIB-compressed payload
  (78 9c) behind an ASCII "STX2" tag, inside NV-backup framing with length/CRC. The internal
  RTSAR struct layout is undocumented. A reliable single-field (enable/mode) flip would need
  decompress + known struct + recompress + framing/CRC repair across records - not reliable,
  i.e. image-hacking, which is disallowed. No open EFS2/NV-backup writer exists.
- Unblock later: a DIAG-EFS2-over-QRTR write path (supported), OR the STX2 struct + oem_stanvbk
  record/CRC spec (offline). Both are separate projects.

## Option 1 (DIAG write path) feasibility - read-only recon (2026-10-26 16:55-17:09)
Goal (Martin): before treating option 1 as a project, check whether the dodge modem actually
exposes a DIAG transport that andersson/diag-router (linux-msm/diag) could bind, and whether
an open EFS2-over-DIAG client could then stat/get the rtsar_config item. READ-ONLY only: no
EFS write. Three gated flag boots on gpu1, pristine EFS base, tqftpserv emptied; real
partitions hashed before/after (identical every boot - no partition writes); copies+tqftpserv
backed up (phone + host mirror) each boot; phone returned to gpu1/flag-off/clean each time.

Tooling check (sanctioned, already on the phone): diag-router is the right router (handles the
DIAG_CNTL feature-mask handshake + HDLC framing, exposes DIAG over a socket) but it needs an
aarch64 build AND a separate EFS2 client; the phone rootfs has no compiler. More importantly,
diag-router binds DIAG either as a glink/rpmsg channel (peripheral-rpmsg.c: "DIAG"/"DIAG_CNTL"
/"DIAG_CMD") or as QRTR service id 4097 (peripheral-qrtr.c: DIAG_SERVICE_ID 4097, modem
instances CNTL=0/CMD=1/DATA=2). So the real question is whether the modem advertises DIAG on
either transport.

Kernel/transport (NOT a blocker): gpu1 has CONFIG_RPMSG_CHAR=m and CONFIG_RPMSG_CTRL=m (plus
RPMSG_QCOM_GLINK=y); the modules are staged and load cleanly at runtime (rpmsg_char, rpmsg_ctrl,
qcom_glink_smem). The userspace rpmsg DIAG path is supported - no kernel rebuild needed.

Finding - DIAG is NOT exposed by this modem build, on either transport:
- glink/rpmsg: with the modem running, 4080000.remoteproc advertises only DATA1-4, DATA11, DS,
  IPCRTR, LOOPBACK_CTL_MPSS, SSM_RTR_MODEM_APPS, modem_apps, rpmsg_ctrl. No DIAG / DIAG_CNTL /
  DIAG_CMD channel. So diag-router's rpmsg peripheral has nothing to bind.
- QRTR: qrtr-lookup (present at /usr/bin) enumerates a full QMI service suite on the modem node,
  but `qrtr-lookup 4097` returns an empty list - no DIAG QRTR server is registered. So
  diag-router's QRTR peripheral has nothing to bind either.
Conclusion: option 1 as premised (DIAG-over-rpmsg, or DIAG-over-QRTR, driving an EFS2 client)
cannot proceed on this firmware. No EFS2 stat/get was possible; no put was attempted. The
blocker is the modem firmware's diag enablement, not the mainline kernel.

Incidental: on these pristine-EFS / empty-tqftpserv boots (no operator config -> no
registration -> no TX bring-up) the modem stayed `running` for the whole ~2 min window and did
NOT hit the rtsar license crash. Consistent with the crash being gated on TX bring-up during
registration; it does not contradict earlier crashes (those boots drove attach/registration).

Leads for a possible pivot (NOT pursued - needs Martin's direction):
- The modem exposes a rich QMI surface over QRTR, and qmicli/mmcli/qrtr-lookup are already on
  the phone. Present QMI services include the Specific Absorption Rate service, the RF radiated
  performance enhancement service, the Persistent Device Configuration (PDC) service, a "Modem
  embedded file system" service, and (on the apps node) a "Remote file system" service. A
  QMI-based path (PDC / an EFS-over-QMI service / runtime SAR control) may be the open
  alternative to DIAG for either reading the item or changing SAR behaviour - but whether
  libqmi/qmicli can address an arbitrary EFS path, or set SAR to an unrestricted state, is
  unconfirmed and is a separate investigation.

## Option (a) QMI read-only recon (2026-10-26 17:15-17:18, gpu1, flag gated, tqftpserv emptied)

Read-only QMI probe over `qmicli -d qrtr://0` + `qrtr-lookup`. Real partitions
hashed identical before/after; copies+tqftpserv backed up (phone+host); pristine
restore verified; flag off; ended gpu1/clean. No writes of any kind issued.

Modem was up (`modem=running`) but in the recon state (operator config emptied,
no registration, no TX bring-up).

### Service registration (qrtr-lookup, modem node 0)
- 17 SAR  (Specific absorption rate)            registered, port 46
- 21 MFS  (Modem embedded file system)          registered, port 25
- 34 COEX (Coexistence)                         registered, port 47
- 36 PDC  (Persistent device configuration)     registered, port 34
- 41 RFRPE(RF radiated performance enhancement) registered, port 93
- 38 STX  (Simultaneous/Smart Transmit)         NOT registered (qrtr-lookup 38 empty;
          also absent from the full node-0 service dump).

  => The Simultaneous/Smart-Transmit QMI service is not present in this recon state.
     Likely registers only during full TX bring-up - i.e. the same window in which
     the rtsar license check fires and the modem crashes (chicken-and-egg).

### SAR (17)
`--sar-rf-get-state` -> "SAR RF state: 0". This is an RF-state INDEX (0..20) mapped
from NV, NOT a boolean. State 0 does NOT mean "no back-off"; it is one configured
state. SAR controls static SAR back-off tables, not the RTSAR/Smart-Transmit
license-gated time-averaging framework. qmicli exposes get/set-state.

### MFS (21)
Registered on the modem, but NO tool on the device can address it: libqmi/qmicli
has no MFS command, and no public mfs_v01 / EFS-QMI IDL (message ids) was found in
the sources checked. RFSA FILE_READ (0x0022) belongs to a different service (28,
apps-side, used by rmtfs) and cannot read modem EFS from the AP. Reading an EFS
path (e.g. rtsar_config) via MFS would require the vendor IDL, which is not public.

### PDC (36)
- list-configs platform: Total 0 (no platform configs).
- list-configs software: Total 25 carrier MBN configs.
  - Config 1 = the TDC Denmark commercial config: Status = **Pending**.
  - All 24 others: Status = Inactive.
  - (Config ids/version bytes intentionally not reproduced here.)
- qmicli 1.38 PDC has list-configs (read) but no get-selected-config command, so
  "selected vs active for slot 1" can't be read directly with this libqmi.

Interpretation of Pending / earlier DeviceInUse:
- "Pending" = the TDC config has been selected/loaded as the config to use but
  activation has not completed; PDC configs typically require a modem refresh/
  restart to transition Pending -> Active.
- The earlier activate returning **DeviceInUse** is consistent with the config
  already being in the Pending (activation-in-flight / modem-holding) state: PDC
  refuses a fresh activate while the subsystem is already mid config-operation /
  the device is in use. It is not a permissions failure.
- The carrier MBN (TDC) is the component that can carry the regulatory SAR/Smart-
  Transmit policy, so the Pending TDC config is plausibly tied to whether RTSAR is
  demanded at registration.

### RFRPE (41)
Registered (port 93). RF radiated performance enhancement = radiated-power/antenna
tuning. No libqmi command; no public IDL. Not a license/Smart-Transmit toggle.

### Does any service expose a Smart Transmit enable/mode?
No read-only, documented knob was found:
- STX (38) is the natural control surface but is not registered in this state.
- SAR (17) is static SAR tables, not the RTSAR license gate; state 0 != disabled.
- RFRPE (41) is radiated tuning, not a license gate.
- MFS (21) could reach the rtsar_config NV item but only with the (non-public) IDL.
- PDC (36) governs the carrier MBN that may demand RTSAR, but toggling it is a write
  (activate) and still would not supply the QWES license.

dmesg during the probe showed no rtsar/license/smart/fatal lines (no TX bring-up in
this recon state), only unrelated msm module-load traces.
