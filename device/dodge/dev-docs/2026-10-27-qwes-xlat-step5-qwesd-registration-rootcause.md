# qwes-xlat step 5 — root-cause: why qwesd never registers its QWES QMI service

Status: **BLOCKER identified. No code fix made this phase (cause is not addressable by an
apps-side shim). Read-only; no boot taken; all partitions unchanged.**

## Question
Step 4 (modem-ON trial) found the modem still panicked at the rtsar Smart-Transmit license
check, and qwesd had registered **no** QWES QMI service on qrtr. This phase root-causes *why*
qwesd never registers — statically (disassembly/strings of qwesd + libqwes) and dynamically
(strace -f + gdb of qwesd in the bionic env on gpu1, modem flag OFF, **no boot**).

## Method
- Static: full `llvm-objdump -d` of qwesd (CFI-built, so all funcs show as `__cfi_check+off`;
  .text/.rodata are identity-mapped so dis addresses == file vaddrs). Decoded `main` and the
  real service start_routine.
- Dynamic: ran qwesd under the existing bionic env (loop-mount erofs system_a/vendor_a/apex ro,
  LD_LIBRARY_PATH=ours:vendor:/vendor/lib64:/system/lib64) on the **gpu1** kernel — the whole env
  reproduces there; only /dev/tee0 is absent, and the wedge is far upstream of any tee access, so
  no trial boot was needed (boot budget preserved: 2 of 3 remain).
  - strace: `strace -f -s 256 -tt` (network,openat,connect,socket,bind,read,write,ioctl,futex,…).
  - gdb: `-p <pid> -batch "info threads" "thread apply all bt"`.

## Startup flow (decoded)
- `main` (0xa364): `new(48)` → `android::SetUpMinijail` (seccomp; reads
  /vendor/etc/seccomp_policy/qwesd@2.0.policy) → install SIGTERM handler → `pthread_attr_init` +
  `setstacksize(16384)` → **one** `pthread_create` whose start_routine is the CFI trampoline
  0x14f90 → real entry **0xb460** → `pthread_join` that thread. (main has no QSEECom / binder /
  servicemanager / property / registration calls.)
- Service entry 0xb460 (runs as the joined thread): builds an in-memory config list; strlcpy a
  conf path; atomic access()/rename() handling of /data/vendor/qwes/qwesd.conf (absent → defaults);
  `curl_multi_init` + eventfd + a **curl worker thread**; a wall-clock sanity retry loop
  ("Waiting for valid system time", nanosleep(5)x5 — **bypassed** once RTC is set); an **optional**
  `dlopen("libloc_multinet.so")`+`dlsym("resolvePublicUrl")` (device-absent → tolerated); then a
  runtime-resolved `dsi_init()` (libdsi_netctrl network controller — failure is **tolerated**, both
  branches fall through); then it enters a **state-machine condvar wait** and never leaves it.

## The wedge (0xc3e4–0xc450)
```
lock   mutex 0x1c1b0
flag = [0x1c114]                 ; state field in the 1112-byte struct @0x1c110
if flag != 0            -> proceed
if list@0x1c540 non-empty -> proceed    ; a work queue (self-referential head = empty)
if byte[0x1c560] != 0   -> proceed
pthread_cond_wait(cond 0x1c180, mutex 0x1c1b0)   ; else block here
loop
```
qwesd blocks until **state flag [0x1c114] flips**, OR work is enqueued on list [0x1c540], OR
byte [0x1c560] is set. None ever happens → it waits forever. There are 9 cond_signal/broadcast
sites in qwesd; all live in async callbacks that are never invoked in a bare, modem-off env.

## Dynamic evidence (strace + gdb, gpu1, modem OFF, no boot)
- **No QMI service is ever registered.** The only two `socket(AF_QIPCRTR)` calls are made by the
  main thread during libqmi static-init (fd 3) and are **never bound and never sendto'd** — i.e.
  no QRTR NEW_SERVER announcement. `qmi_csi_register` is dlsym'd at runtime and is never reached.
- **Thread topology at the hang:**
  - main — blocked in `pthread_join` on the service thread (from qwesd 0xa498).
  - service thread (0xb460) — parks on the condvar ~7 ms after start, right after the optional
    libloc_multinet dlopen fails and it spawns the curl worker; stays parked until SIGTERM.
  - curl worker — parked on its own idle queue (normal).
- All QMI libs load fine from /vendor/lib64 (libqmi_csi, libdsi_netctrl, libqrtr, libqmi_encdec,
  libqmiservices, libqmi_cci, libqmi_common, …) — missing libs are **not** the cause.

## Hypotheses ruled OUT (with evidence)
- **Property area / "property stub":** /dev/__properties__ is ENOENT so every
  `__system_property_get` returns empty — but the **only** property qwesd reads is `ro.arch`
  (lib-path selection; harmless with LD_LIBRARY_PATH set). There is no QWES-enable property. The
  "QWES not enabled" string is referenced only in the runtime QMI request handlers (0xcdb8/0x133f4),
  not the startup/registration path. **Supplying a property area would not help.**
- **servicemanager / AIDL:** qwesd imports no binder/servicemanager symbols; none appear in strace.
- **/dev/qseecom / QSEECom:** neither qwesd nor libqwes imports any QSEECom_* symbol
  (libQSEEComAPI.so is a dead DT_NEEDED); no /dev/qseecom access on the hang path. ("Don't assume
  /dev/qseecom" was correct.)
- **ssgtzd / /dev/tee0:** no connect to /dev/socket/ssgtzd and no /dev/tee0 access before the wedge.
- **libloc_multinet.so:** optional dlopen, device-absent, tolerated — red herring.
- **dsi_init failure:** tolerated (both branches fall through) — not a hard blocker.
- **qmi_fw.conf absent, qwesd.conf absent:** libqmi defaults to qrtr; qwesd defaults its conf.

## Root cause
qwesd does **not** register its QWES QMI service unconditionally at startup. Its service thread
runs a state machine that blocks in a condition-variable wait (cond @0x1c180, state flag @0x1c114,
work-list @0x1c540) waiting for an **asynchronous event that does not occur in a modem-off
environment**. The two qrtr sockets opened at libqmi init are never announced — qwesd is waiting
as a *client* for a QMI service-availability / indication event (resolved via dlsym at runtime,
consistent with a modem-side dependency: dsi_netctrl / modem QMI). Only after that event flips the
state flag and signals the condvar would qwesd advance to `qmi_csi_register`. With the modem OFF
the event never fires, so qwesd parks ~7 ms in and never registers — exactly what strace+gdb show.

## Direction (answered)
qwesd is the QWES QMI-CSI **server** (apps-side service) and the modem is the **client** of it
(the only statically-imported qmi_csi symbol is `qmi_csi_send_broadcast_ind`; qrtr is transport).
But qwesd gates *becoming* that server behind an async event that itself depends on modem/QMI
bring-up.

## Why this blocks the planned step-3 path
The directive's step 3 said: fix the smallest piece (property shim / stub servicemanager /
libQSEEComAPI→qcomtee shim), and **if qwesd then registers with the modem flag OFF, do one
modem-ON trial.** None of those shims apply — the dependency is on a modem-side QMI event, not on
any missing apps-side service. No apps-side shim can make qwesd register with the modem OFF, so the
precondition for the authorized modem-ON trial cannot be met this way. This reframes step 4's
negative result: it is a modem↔qwesd **bring-up-order dependency**, not a missing local service.

Resolving it (e.g., making qwesd register before/independently of the awaited modem event, or
establishing exactly which QMI service/indication it waits for and providing it) is a larger effort
than the ~half-day stop threshold and changes the approach, so this phase stops here for a decision.

## Phone state (unchanged)
- Kernel 7.3.0-rc6-dodge-gpu1, boot_a, `dodge.flashed` present (restored DEF). Battery 100%.
- remoteproc: adsp=running; mpss not instantiated (modem flag OFF).
- Partition hashes (first16) — all at baseline, untouched:
  modem_a=3998fa8ca602a9c4 modem_b=c10429a60343ceac modemst1=5dce762bccf7d059
  modemst2=95c4e7bee54a335e fsg=bb9f8df61474d25e fsc=fa43239bcee7b97c
  qweslicstore_a=879c097b7daf3936 qweslicstore_b=879c097b7daf3936
- Boots consumed this phase: 0 (budget: 2 of 3 remain).
