# qwesd WRITE/serve path — step 4: modem-ON trial with the translator stack (2026-10-27)

## Goal
One reversible modem-ON trial on the `7.3.0-rc6-dodge-qtee1+` kernel (= the ipa1 kernel
plus only `CONFIG_QCOMTEE=y`), built with modules and modules_install'd into the rootfs
under its own `.held`/overlay release dir like ipa1. Bring up the translator stack
(our `qtee_supplicant` read-only RPMB + FS listeners) and the long-running **vendor
`qwesd`** in the reconstructed bionic env, with the smcinvoke→qcomtee shim, BEFORE the
modem starts — so when MPSS does its QWES Smart-Transmit license check (the
`rtsar_framework.c:3546` crash) there is a live QWES responder on the QMI bus.

## Trial mechanics (all hard rules honored)
- Full-rootfs trial: `fastboot boot` of the qtee1 chain image (nothing flashed), stage-2
  cmdline `… oops=panic … omamobile.userdata-rw`, no `dodge.flashed` → trial=1. On-device
  220 s deadline, soak-extended to 480 s (as the ipa trials did) so the full watch window +
  a data bearer could fit in one boot. Battery-gated (`tools/dodge-gate`), host watchdog 560 s.
- Modem brought up on the **post-registration writable EFS copies** already in place
  (`/var/lib/omamobile/modem-efs/`), fresh-backed-up before the boot (mode 400).
- `/dev/tee0` present, `qcomtee: QTEE version 5.2.0`, NO `/dev/smcinvoke`, NO `/dev/qseecom`.
- `qweslicstore_a`/`_b` forced read-only at boot; persist never mounted. MPSS never manually
  stopped. No SMS/calls. 1 of 2 boots used.

## Result — rtsar did NOT pass; identical failure
    [  76.059] qcom_q6v5_pas 4080000.remoteproc: fatal error received:
               rtsar_framework.c:3546:Smart Transmit License Check Failure Code (1, 1, 1)

The modem started, searched (operator seen, signal ~36/100), never completed registration
(`registration-state: searching`, `packet-service: detached`), and MPSS crashed ~30 s after
start with the SAME license-check failure as the baseline. No data bearer (modem was already
crashed when the data phase would have run).

## Root cause of the negative result: qwesd registered NO QWES QMI service
- `qtee_supplicant` came up correctly and **read-only**: RPMB service registered (ID `0x2000`),
  UFS RPMB probed; **zero write attempts** logged by either listener; `qweslicstore` ro.
- `qwesd` **loaded fully** (all DT_NEEDED resolved, bionic linker + minijail/seccomp came up in
  log-only mode) and stayed alive — but it produced **no application output** and, decisively,
  **registered no service on the apps-side (node 1) QMI bus**. Two `qrtr-lookup` snapshots (before
  and after MPSS start) show only the usual services (locator/IPA-control/test/subsys-control/
  coresight/slimbus/sensor-core + modem-side RFS and TFTP once MPSS was up). There is **no QWES
  service** for the modem's QWES client to talk to.
- So the modem's `IPFM_CheckInstalledLicense` QMI request had no responder → license check failed
  → rtsar crash, exactly as without the stack. qwesd exchanged **nothing** observable with the modem.

## Interpretation / likely blocker
qwesd stalled/short-circuited at startup before registering its QMI-CSI service, producing no
log beyond the linker/minijail lines. qwesd links `libQSEEComAPI.so` (legacy QSEECom path to
`/dev/qseecom`), which does not exist on qtee1. The most probable blocker is that qwesd's
service bring-up goes through the **legacy QSEECom path** (load the QWES TA via
`QSEECom_load_app` on `/dev/qseecom`) rather than the Mink/smcinvoke path our shim covers — so
the shim never gets exercised and qwesd never reaches `register_service`. (In step 3B the
license READ went through the Mink path because `qwes_cli` drives libqwes directly; the daemon's
QMI bring-up appears to take a different, QSEECom-gated route.) This is the `/dev/qseecom`
dependency named as a stop condition.

## Phone state after the trial
Restored to `7.3.0-rc6-dodge-gpu1` (DEF), modem flag off, modem not running. **All 11 protected
partitions hash-identical to baseline** (modem_a/_b, modemst1/2, fsg, fsc, oplusdycnvbk,
oplusstanvbk_a/_b, qweslicstore_a/_b). Rootfs clean. No secure storage written anywhere.

## Next candidate directions (not yet attempted)
1. Confirm the qwesd QMI-registration path: trace which secure-world device it opens at startup
   (QSEECom `/dev/qseecom` vs Mink `/dev/smcinvoke`) — e.g. an `strace`/open-audit of qwesd in the
   bionic env on a RAM boot (no modem needed) to see exactly where it stalls.
2. If qwesd is QSEECom-gated: provide a QSEECom→qcomtee shim for `libQSEEComAPI.so` (load_app/
   send_cmd → QTEE object calls on /dev/tee0), analogous to the smcinvoke shim, so the daemon's
   TA load + QMI service come up on qtee1 without `/dev/qseecom`.
3. Alternatively drive the QWES QMI service from libqwes directly (which already works via the
   Mink path in 3B) with a minimal QMI-CSI responder, bypassing the vendor qwesd daemon.
