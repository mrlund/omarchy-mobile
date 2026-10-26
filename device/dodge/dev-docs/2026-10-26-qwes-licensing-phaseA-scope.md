# qwesd / QWES Smart Transmit licensing: Phase A scope + feasibility

Goal: can we satisfy the modem's `rtsar_framework.c:3546 Smart Transmit License Check Failure
(1,1,1)` by bringing up the Qualcomm QWES licensing service (qwesd) on our 7.3 kernel, without
writing secure/RPMB/persist storage? Read-only research + read-only on-phone inspection only.

## CORRECTION (2026-10-26): earlier draft checked the wrong tree
The first draft of this doc read the *running gpu1 kernel's* /proc/config.gz and concluded QTEE
"landed in 6.18, needs a backport". That was wrong. Our source trees
(~/android/mainline/wt-omamobile, wt-ipa) are genuinely **Linux 7.3.0-rc6** (Makefile VERSION=7
PATCHLEVEL=3) and already contain `drivers/tee/qcomtee/` (config QCOMTEE) and
`drivers/misc/rpmb-core.c` (config RPMB). So **no backport is required - the kernel piece is a
config flip** (CONFIG_QCOMTEE=y, plus RPMB if the driver needs it to probe). The running
gpu1/ipa1 kernels simply had those options off.

## What the modem actually asks for (from modem_a image strings, read-only)
The modem's license check calls into an **IPFM** (install-able PFM / license) client:
  IPFM_qsee_open(), IPFM_CheckFIDAndGetAllSerialNums, IPFM_CheckInstalledLicense,
  IPFM_CheckLicenseBuffer, IPFM_GetInstalledLicenseInfo, IPFM_SetOptions,
  "license check failed! response code %li feature id %li", and a "/Qwes" path.
Chain: modem (QMI QWES service) -> HLOS qwesd -> IPFM lib -> **qsee_open = a QSEE/QTEE
secure-world session** -> QWES/IPFM Trusted App -> checks an **installed license** in secure
(RPMB-backed) storage. "(1,1,1)" = three failed stages (no license source answered at all),
consistent with "no qwesd + no QTEE channel" on mainline. It does NOT answer from a persist
.pfm alone; it needs the TZ QWES TA via QSEE/QTEE plus the RPMB-backed license store.

## How QWES is packaged (meta-qcom qwes_1.0.bb, Qualcomm docs)
- `qwesd` + `qwes_cli` are **prebuilt closed-source Qualcomm binaries** (softwarecenter.qualcomm
  .com, entitlement-gated). The recipe only installs the prebuilt + qwesd.service. DEPENDS:
  curl, minkipc, qmi-framework, glibc (the meta-qcom build target is glibc/QCLINUX).
- qwesd "initializes the license store and optionally loads the QcWES TA".
- Licenses are `.pfm` files installed via `qwes_cli -f <x>.pfm install`; metadata is stored in
  **RPMB** (replay-protected, TEE-key-authenticated) with a copy on the data partition; install
  requires "RPMB provisioned" + the TA. We do NOT need to install (a factory Smart Transmit
  license is already provisioned on this commercial device) - we need the read/query path to
  answer the modem. We will not write RPMB/persist/secure storage, and will not fake responses.

## Our 7.3 kernel reality (corrected)
- Source is Linux **7.3.0-rc6**; qcomtee + rpmb-core are in-tree. Kernel work to get a QTEE
  channel = **enable CONFIG_QCOMTEE (+ RPMB as needed) and rebuild** - not a backport.
- On the *running* gpu1 kernel: CONFIG_TEE=y, CONFIG_QCOM_SCM=y, /sys/bus/tee present;
  CONFIG_QCOMTEE / CONFIG_RPMB were off. qcom_scm prints qseecom "untested machine, skipping" -
  that is the *legacy qseecom* allowlist in qcom_scm; the upstream qcomtee object-invoke path is
  separate (Phase A2 will confirm whether qcomtee probes regardless).
- Firmware dir /lib/firmware/qcom/sm8750/OnePlus/ has only modem/adsp/ipa/gpu mbns - **no QWES /
  IPFM TA staged for mainline**. Device has tz_a/b, uefisecapp, keymaster, featenabler, tzsc
  partitions; the signed QWES/IPFM TA lives on the stock Android vendor partition.

## Verdict: FEASIBLE-WITH-X (kernel), userspace/TA still under investigation (Phase A2)
Kernel channel: config-only (CONFIG_QCOMTEE=y). The hard parts that remain, to be scoped in
Phase A2:
 1. **qwesd is a closed bionic/Android vendor binary** (or the glibc QCLINUX prebuilt we are not
    entitled to download). Running the vendor bionic qwesd on our glibc mainline userspace likely
    needs an Android-userspace container / libhybris, plus its listeners (RPMB/fs listener that
    qseecomd / qtee_supplicant normally provide).
 2. **The signed QWES/IPFM TA** only exists on the stock Android vendor partition and must be
    loadable by the QTEE path on our kernel (signature/anti-rollback permitting).
 3. **RPMB provisioning** for the license store, which we must not write.
Phase A2 (checkpointed) will: inventory the vendor QWES bits read-only; build an ipa1-based 7.3
image with CONFIG_QCOMTEE=y; and do ONE trial boot (modem flag OFF) to confirm /dev/tee0 +
qcomtee probe and a read-only QTEE capability query. No TAs loaded, nothing written to
secure/RPMB.

## Phase A2 RESULT (2026-10-26): qcomtee probes and binds on our 7.3 kernel
Config flip confirmed: an ipa1-based 7.3.0-rc6 kernel with CONFIG_QCOMTEE=y (+ TEE, QCOM_SCM,
QCOM_TZMEM in SHMBRIDGE mode; RPMB left OFF) builds with qcomtee as a built-in - no backport.

ONE trial boot, read-only SSH ramdisk chain image, modem flag OFF, fastboot boot (no flash):
- `/dev/tee0` present; `/sys/class/tee/tee0/implementation_id = 4` (TEE_IMPL_ID_QTEE).
- dmesg: `qcomtee: QTEE version 5.2.0` - probed and bound with **no DT node** (qcom_scm
  registers the "qcomtee" platform device itself; `qcom_scm_qtee_init()` runs unconditionally in
  qcom_scm probe and gates only on a runtime SMC capability probe).
- The `qseecom: untested machine, skipping` message is emitted ONLY by the legacy qseecom path
  (DT allowlist in qcom_scm); **the qcomtee object-invoke path has no allowlist** and came up
  regardless. Question from the brief answered: untested-machine is legacy-qseecom-only.
- `implementation_id=4` is the read-only capability readout (exposed only after a successful
  QTEE get_version; the driver advertises OBJREF). No session opened, no TA loaded, nothing
  written; all block devices read-only throughout. Phone back on gpu1, hashes verified identical.

So the kernel channel (item 0) is DONE. The remaining items 1-3 from the verdict stand, re-scoped
for a READ path: the Smart-Transmit license is already provisioned in persist by stock Android,
so the objective is the IPFM_CheckInstalledLicense read, not provisioning. Persist is served
read-only; the RPMB listener is read-only (log + reject every write, never forward to device);
the QWES trustlet may be loaded into QTEE memory but never persisted to secure storage.
