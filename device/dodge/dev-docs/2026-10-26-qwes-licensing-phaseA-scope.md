# qwesd / QWES Smart Transmit licensing: Phase A scope + feasibility (no phone boots)

Goal: can we satisfy the modem's `rtsar_framework.c:3546 Smart Transmit License Check Failure
(1,1,1)` by bringing up the Qualcomm QWES licensing service (qwesd) on our 7.3 kernel, without
writing secure/RPMB/persist storage? Read-only research + read-only on-phone inspection only.

## What the modem actually asks for (from modem_a image strings, read-only)
The modem's license check calls into an **IPFM** (install-able PFM / license) client:
  IPFM_qsee_open(), IPFM_CheckFIDAndGetAllSerialNums, IPFM_CheckInstalledLicense,
  IPFM_CheckLicenseBuffer, IPFM_GetInstalledLicenseInfo, IPFM_SetOptions,
  "license check failed! response code %li feature id %li", and a "/Qwes" path.
Reading of the chain:
  modem (QMI QWES service) -> HLOS qwesd -> IPFM lib -> **qsee_open = a QSEE/QTEE secure-world
  session** -> QWES/IPFM Trusted App -> checks an **installed license** held in secure storage.
"(1,1,1)" is three failed stages (present / valid / service-reachable) = no license source
answered at all, which is exactly "no qwesd + no QTEE channel" on mainline.

## How QWES is packaged (meta-qcom qwes_1.0.bb, Qualcomm docs)
- `qwesd` + `qwes_cli` are **prebuilt closed-source Qualcomm binaries**, fetched from
  softwarecenter.qualcomm.com (sec-userspace.qclinux prebuilt, entitlement-gated). The recipe
  only installs the prebuilt + qwesd.service. DEPENDS: curl, minkipc, qmi-framework, glibc.
- qwesd "initializes the license store and optionally loads the QcWES TA".
- Licenses are `.pfm` files installed via `qwes_cli -f <x>.pfm install`; metadata is stored in
  **RPMB** (replay-protected, TEE-key-authenticated) with a copy on the data partition, and
  survives data erase. Install requires "RPMB is provisioned" + the TA.

## Our 7.3 kernel reality (running kernel, read-only)
- Base is mainline ~6.16 (version magic 6.16.0). TEE subsystem present: CONFIG_TEE=y,
  CONFIG_QCOM_SCM=y, /sys/bus/tee exists.
- qcom_scm probes: "qseecom: found qseecom with version 0x1402000" BUT **"untested machine,
  skipping"** (SM8750 not on the legacy qseecom allowlist).
- **CONFIG_QCOMTEE is not set** - the upstream QTEE driver is absent.
- **CONFIG_RPMB is not set** - no RPMB subsystem.
- Firmware dir /lib/firmware/qcom/sm8750/OnePlus/ has only modem/adsp/ipa/gpu mbns - **no QWES /
  IPFM TA staged**. The device has tz_a/b, uefisecapp, keymaster, featenabler, tzsc partitions;
  the QWES/IPFM TA is signed and lives on the stock Android vendor partition, not staged for
  mainline.

## Upstream driver status
- The Qualcomm **QTEE (qcomtee) driver landed in Linux v6.18** (merged Sep-Oct 2025): a new
  TEE-subsystem backend (object invocation, TEE_IOC_OBJECT_INVOKE) + new qcom_scm object-invoke
  support + tzmem shm_bridge changes, ~4200+ lines across ~22 files. It is NOT in 6.16/6.17.
- RPMB subsystem + UFS RPMB would also need enabling/wiring.

## Verdict: BLOCKED-BY-Y (do not proceed to Phase B)
Phase B's precondition ("A says feasible without forbidden writes") is NOT met. To make the
modem's IPFM/QWES check pass we would need ALL of:
 1. Backport the **qcomtee (QTEE) driver from 6.18** to our 6.16 base + its SCM object-invoke +
    tzmem prerequisites. The modem check does `IPFM qsee_open()`, so it fundamentally needs a
    working QSEE/QTEE secure channel our kernel does not have. => multi-day kernel driver work,
    which is an explicit STOP condition.
 2. Enable/implement **RPMB** (CONFIG_RPMB off) + UFS RPMB, since the installed license is held
    in RPMB-backed secure storage (IPFM_CheckInstalledLicense).
 3. Obtain **qwesd** - closed-source, entitlement-gated Qualcomm prebuilt. We will not fake or
    hard-code license responses (and could not: the TA validates).
 4. Stage/run the signed **QWES/IPFM TA**, which only exists on the stock Android vendor
    partition and needs the QTEE loader path to run.

Size estimate: qcomtee backport + RPMB + UFS RPMB + DT/qseecom-allowlist + the closed userspace
stack = multi-day-to-weeks, dependent on closed-source binaries and secure-world/RPMB
provisioning we are told not to touch. Well beyond the one-day threshold.

## Recommendation
The clean paths to a working radio are not the local-qwesd route:
 (a) a kernel-side option to make the modem skip/accept the Smart Transmit check (NV/MCFG config
     that does not enforce rtsar, or a modem build/config without it) - the earlier runs that
     avoided rtsar suggest config state governs whether the check runs; or
 (b) land the PR with the radio feature-gated/documented as needing the QTEE+QWES stack (a
     6.18-class kernel + Qualcomm licensing userspace), tracked as follow-up.
No phone boot was needed or done for Phase A. Phone left on gpu1, flag off.
