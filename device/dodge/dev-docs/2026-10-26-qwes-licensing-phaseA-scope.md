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

## Phase A2 step 1 RESULT (2026-10-26): TEE-ABI mismatch is the blocker
Vendor QWES userspace inspected read-only. Every component that reaches secure world links
libminkdescriptor.so, which opens the legacy **/dev/smcinvoke** and uses the downstream
**SMCINVOKE_IOCTL_*** object-invoke ABI (plus legacy /dev/qseecom). NO vendor binary/lib
references /dev/tee*, qcomtee, or TEE_IOC_* - there is no userspace that speaks the upstream TEE
uapi our qcomtee driver exposes. All binaries are bionic (/system/bin/linker64): qwesd, qwes_cli,
qseecomd (listener host), rpmbClient (RPMB listener). The read entry points we want exist
(qwes_cli list/listfids, IQwesService_checkInstalledLicense, GetInstalledLicenseInfo).

Consequence: enabling qcomtee (done) + a bionic container is NOT enough - libminkdescriptor would
fail to open /dev/smcinvoke. Bridging options: (a) backport downstream smcinvoke.ko onto 7.3
(out-of-tree, overlaps qcomtee's QTEE SMC claim, multi-day, uncertain); (b) a CUSE /dev/smcinvoke
shim translating SMCINVOKE_IOCTL_* -> qcomtee TEE_IOC object-invoke on /dev/tee0, including the
bidirectional accept/server callback loop the FS/RPMB listeners need (several days). Both exceed
the one-day stop condition, so the qwesd read path stops here pending a decision on the shim.

## Phase A2 step 0 RESULT (2026-10-27): prior art -> route decided (build open minkipc over qcomtee)
Approved to build the smcinvoke<->qcomtee translator. ~30 min prior-art survey settled the route.

Key finding: the full HLOS-side QTEE stack already exists as open source, targeting exactly the
upstream TEE uapi our qtee1 kernel exposes (/dev/tee0, QTEE 5.2) - no closed /dev/smcinvoke needed:
- quic/quic-teec (libqcomtee): userspace Object-IPC client over the in-tree qcomtee driver, using
  TEE_IOC_OBJECT_INVOKE for outbound invokes and the supplicant recv/send (TEE_IOC_SUPPL_RECV/SEND)
  for QTEE->HLOS callbacks. BSD-3. Builds via CMake with a cross toolchain; depends on QCBOR.
- quic/minkipc: the open MINK-IPC stack built ON quic-teec. Relevant pieces:
  * libminkadaptor - the "User Invoke Gateway": implements the generic Mink Object C ABI
    (object.h: Object/Object_invoke; MinkCom.h: MinkCom_getRootEnvObject / getClientEnvObject /
    getMemoryObject) over qcomtee, including the inbound (supplicant) path. This is the open analog
    of the vendor libminkdescriptor.so (same MINK lineage), but talking /dev/tee0 instead of
    /dev/smcinvoke.
  * qtee_supplicant - the HLOS daemon that services QTEE callbacks (CBO listener dispatch).
  * listeners/libfsservice (fs + gpfs) - the filesystem listener (serves HLOS FS reads/writes to
    QTEE). Point its root at a READ-ONLY copy of persist pfm; refuse write ops.
  * listeners/librpmbservice - the RPMB listener. Its dispatch is a switch in rpmb_service.c:
    TZ_CM_CMD_RPMB_{INIT,READ,WRITE,PARTITION}; TZ_CM_CMD_RPMB_WRITE -> rpmb_handle_write() ->
    rpmb_write(). READ-ONLY enforcement is a one-function patch: in rpmb_handle_write log the
    command + num_sectors and return an error WITHOUT calling rpmb_write(); leave READ untouched
    and never forward a write to /dev/mmcblk0rpmb or /dev/bsg/ufs-bsg. (Our kernel has RPMB off, so
    this listener may simply find no device; it is a safety net.)
  * rpmb_client, libtimeservice, libtaautoload, listenercbo - additional listeners, not needed for
    a license READ but available.
  The QWES IDL itself (IQWESTAServices, IQWESKeyStore, IProvisioning, IKVStore) ships in minkipc's
  SDK, confirming QWES rides on this same Mink Object model over Object_invoke.

Routes weighed (cheapest first):
  (b) CHOSEN - build open minkipc + quic-teec + QCBOR for the target and run the vendor qwesd stack
      against libminkadaptor (over /dev/tee0) instead of vendor libminkdescriptor.so, with
      qtee_supplicant + a read-only libfsservice and a write-refusing librpmbservice for callbacks.
      Cheapest because transport AND the whole listener/supplicant layer already exist over qcomtee;
      we write almost no new plumbing - only the read-only policy patches and the wiring/config.
  (a) REJECTED as primary - a bespoke CUSE /dev/smcinvoke -> /dev/tee0 shim. It would reimplement
      the entire downstream SMCINVOKE_IOCTL_* surface (INVOKE/ACCEPT/SERVER/ACK, tzhandle encoding,
      the callback server loop) AND still need an FS/RPMB listener. More code, and it reinvents what
      libminkadaptor already does correctly against real QTEE object semantics. Kept only as a
      fallback shape (see risk below), and even then it would sit on libminkadaptor's Object_invoke,
      not raw ioctls.

Open risk (the real work, = step 1/2): ABI match. The vendor qwesd/qwes_cli/libqwes are bionic
(linker64) and link vendor libminkdescriptor.so + libminksocket_vendor.so by SONAME. libminkadaptor
builds a different SONAME (minkadaptor) and exports the generic Object/MinkCom C ABI. Step 1 must
diff what the vendor binaries actually import (undefined syms) against libminkadaptor's exports:
  - If they import the generic Mink symbols (Object_invoke vtable bootstrap + MinkCom_*), then build
    libminkadaptor for bionic (NDK; minkipc has Android.bp) and install it as libminkdescriptor.so
    (SONAME patch / symlink) so qwesd resolves against it - near drop-in.
  - If the vendor lib exposes extra private symbols qwesd hard-links, add a thin bionic shim that
    exports those and forwards to libminkadaptor - still far less than a CUSE shim.
Fallback if bionic ABI can't be matched at all: a CUSE /dev/smcinvoke node backed by libminkadaptor
(keeps the vendor lib unchanged behind a clean process/ABI boundary).

Hard rules unchanged: persist read-only (served from a read-only copy); RPMB listener read-only
(log + refuse every write by type/size, never forward); no TA persisted to secure storage (load
into QTEE memory only); real modem/EFS/persist partitions never written (hash before/after);
standing dodge trial rules; no identifiers/firmware/TA/.pfm in the repo; never fake/hard-code a
license response. If the read needs a secure-storage write to succeed, stop and report.

Next (step 1): on the host, diff vendor import syms vs libminkadaptor exports; cross-build
quic-teec+QCBOR+minkipc for aarch64; write the SMCINVOKE-ABI -> qcomtee Object-invoke mapping note.
