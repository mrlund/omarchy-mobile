# qwesd step 6 (direction a): what the service thread waits for — signaler/callback trace (2026-10-27)

Follow-up to step 5 (root cause: qwesd registers no QWES QMI service because its single
worker thread parks in a state-machine condvar). Direction (a): trace the signalers back to
what registers them, identify the exact awaited event, and check step-4 qrtr snapshots.
**All static (no boot). 0 of 2 boots used. All protected partitions hash-identical to baseline.**

## The wait and its signalers (disassembly, qwesd)
- The worker thread (entry 0xb460) is a generic **job-queue state machine**. Current state =
  word [0x1c178]; work counter = [0x1c510]; work list head = [0x1c540]; wake flag = [0x1c114];
  stop byte = [0x1c560]. The queue mutex is [0x1c110+0xa0]=0x1c1b0 and its condvar is
  [0x1c110+0x70]=**0x1c180**.
- At startup STATE=0 (handler 0xc088) checks the work counter [0x1c510]; it is 0, so it jumps
  straight to the idle wait (0xc3e4): `pthread_cond_wait(0x1c180, 0x1c1b0)`, looping until
  [0x1c114]!=0 **or** list [0x1c540] non-empty **or** stop byte [0x1c560]!=0.
- There are 8 `pthread_cond_signal` sites. Seven target **per-request/per-object** condvars
  (object+0x28 / object+0x70) used by the generic post-work helpers (0x10524/0x11220/0x11a44/
  0x137bc: lock object+0xa0, enqueue, signal object+0x70). These wake the main thread **only**
  when their object base is the global struct 0x1c110 (+0x70 == 0x1c180). The one site that
  unconditionally targets 0x1c180 by absolute address (0xa31c) is the **SIGTERM handler**: it
  sets stop byte [0x1c560]=1 and signals — i.e. the only guaranteed wake in a bare environment
  is shutdown.
- Therefore forward progress requires an **async callback** to call a post-work helper against
  the global queue (enqueue + signal 0x1c180). The async job sources are: the curl completion
  worker, dsi_netctrl events, timers, and incoming QMI/Mink requests.

## What posts the first job in our environment: nothing
- No QMI/Mink service is registered yet, so there are **no inbound modem requests** to post work.
- No curl transfer is in flight; no timer is armed at startup.
- `dsi_init()` (0xba44, resolved from libdsi_netctrl via the 0x1359c dlopen/dlsym helper — which
  resolves **only** dsi_* symbols) is called once and is **fire-and-forget**: its result is
  logged and tolerated (success/failure converge at 0xbaf8), and **no dsi event callback is
  wired at the init site**. So dsi never posts a job either.
- Result: the work queue stays empty forever → permanent idle park, exactly matching the
  modem-off strace (two qrtr sockets opened at libqmi init, never bound/sendto; worker parks
  ~7 ms in; only SIGTERM moves it).

## It is NOT waiting on a specific modem-side QMI service id/instance, and NOT on dsi
- qwesd has **no** `qmi_client_notifier_init` / `qmi_client_init_instance` / `qmi_csi_register`
  import or string. Its only QMI import is `qmi_csi_send_broadcast_ind` (server-side broadcast).
  So it does not subscribe to any `qmi_client_notifier` service id + instance.
- Its IPC imports are `MinkIPC_connect` / `MinkIPC_release` (Mink-over-qrtr client). The single
  `MinkIPC_connect` call (0x11c04) targets the string **"/dev/socket/ssgtzd"** — the TrustZone
  gateway daemon — gated on config flag [0x1c018], and reached only AFTER the state machine
  advances past the idle wait.
- So the directive's fork does not cleanly apply: it is neither "a modem-side service appears
  (ordering/timing fix)" nor the "dsi/netmgrd (dsi stub)" branch. The blocker is that **no async
  source posts qwesd's first job** in the reconstructed env. qwesd's .rc is `disabled`/`late_start`
  (on-demand): it registers/acts only after an external trigger that is absent here.

## Step-4 qrtr snapshots (modem actually up) confirm it
- Before MPSS (qwesd already running): apps node (1) carried only locator (svc 64) + IPA-control
  (49). **No QWES service registered by qwesd.**
- After MPSS start: only RFS (14) + TFTP (4096) added on node 1; the modem's own QMI data
  services (WDS/DSD/DMS/NAS) never appeared (it crashed at t≈76 s still `registration-state:
  searching`). So even with the modem present, qwesd had already idle-parked and never registered
  — as the static analysis predicts.

## New material finding (changes the recommended fix) — ssgtzd transport
- `libminksocket_vendor.so` imports `qrtr_open`/`socket`/`connect`/`socketpair` and opens
  `/dev/membuf` + `/dev/qti-smmu-proxy`: it is Mink-over-qrtr to the **ssgtzd** daemon, **not**
  /dev/smcinvoke or /dev/tee0. So the qwesd *daemon's* secure path is
  qwesd → libminksocket_vendor → MinkIPC → **ssgtzd socket** → TZ/TA — a **different transport**
  than the proven step-3B read path (qwes_cli → libqwes → libminkdescriptor → /dev/smcinvoke →
  our shim → /dev/tee0). ssgtzd does not exist on qtee1.
- Consequence for direction (b): forcing the state flag under gdb would drive qwesd into
  `MinkIPC_connect("/dev/socket/ssgtzd")`, which fails with no ssgtzd present, so a bare force
  does not yield a working registration — it additionally needs an ssgtzd substitute.

## Recommendation
Unblocking the vendor qwesd daemon now requires BOTH (i) a trigger that posts its first job and
(ii) an ssgtzd gateway (its MinkIPC secure transport). That is a large new build. The cheaper,
lower-risk path is step-4 doc alternative #3: **a minimal QMI/Mink responder that answers the
modem's QWES license check by calling libqwes directly** (GetQwesService →
QWES_Agent_Check_Installed_License) over the already-proven libminkdescriptor→/dev/smcinvoke→
qcomtee shim to the real TA — bypassing qwesd's job-queue + ssgtzd dependencies entirely, with
nothing faked. Flagged for direction before building; no boot spent.
