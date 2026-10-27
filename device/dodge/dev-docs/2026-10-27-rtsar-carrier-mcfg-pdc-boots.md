# rtsar / Smart Transmit vs carrier MCFG active-state — PDC boots (2026-10-27)

Follow-up to the good-vs-bad timeline. The devcoredump route was dropped: with
modem auto-restart disabled by design, qcom_q6v5_pas skips crash handling and
emits no coredump, and recovery cannot be enabled because stopping mpss hard
-resets the phone.

Hypothesis tested: the Smart Transmit (rtsar) license check is pulled in by the
**active carrier modem configuration** (operator MCFG), and the default /
no-active-config state uses static SAR tables only (no license check). This also
explains the earlier good run, whose carried config set had no active carrier
config and held >200 s with no rtsar.

Method (unchanged hard rules): IPA trial kernel via `fastboot boot` (nothing
flashed), battery-gated, reversible. The 12 real modem/EFS/persist partitions
are hashed before and after each boot and served read-only; never written.
Config changes, when attempted, are made only on the **writable copies** through
the modem's own sanctioned config service (QMI Persistent Device Configuration),
and the copies are backed up first. No SMS, no calls, mpss never stopped, no
faked/hard-coded license responses.

## Boot 1 — carrier config Active (reproduce)
Copies carried the registration/crash state. PDC read-only inventory at modem-up:
platform configs 0; software configs total 25; the carrier config **Active**, all
others Inactive. No generic/ROW config was selected.
- Result: modem searched the home operator, then
  `rtsar_framework.c Smart Transmit License Check Failure (…)` ~45 s after the
  modem came up. Reproduces the regression.
- The intended runtime PDC deselect did not actually apply this boot (two session
  bugs: the active-config id was not parsed out, and low-power was entered before
  the SIM application was read, which also broke provisioning). A runtime deselect
  additionally returns DeviceInUse unless the modem is first in low-power, and in
  practice a config change is not picked up without a modem refresh/restart, which
  we cannot do without stopping mpss. So the runtime-deselect path is a dead end
  under these rules.
- Partitions: 12/12 unchanged. Phone returned clean to the default kernel.

## Boot 2 — carrier config NOT active (restore + proven provisioning)
Writable copies restored from the per-boot pristine backup (the no-active-config
set; its fs1/fs2 match the untouched modemst partitions), then booted with the
proven provisioning + online + watch session. PDC read-only inventory at modem-up:
platform configs 0; software total 25; the carrier config **Pending** (not
Active), all others Inactive.
- Result: **no rtsar / Smart Transmit check anywhere** across ~180 s of watch
  (oops=0). Provisioning succeeded this boot (SIM application read, online set).
- But the modem reported **sim-missing** at the ModemManager layer and never
  registered or attached, so data could not be brought up. The raw QMI card read
  saw the USIM application, yet the higher-level stack did not expose the SIM —
  the pristine copy set lacks the per-registration state the modem had in the
  earlier good run. So this boot avoids rtsar but is not a usable end state, and
  the no-rtsar result is partly confounded by never reaching TX bring-up.
- Partitions: 12/12 unchanged. Phone returned clean to the default kernel.

## Conclusion
The strongest signal is Boot 1 vs the earlier good run on the same bed: the only
difference is whether the carrier config is **active**, and the rtsar check
appears only when it is. Boot 2 adds that a non-active carrier config likewise
produces no rtsar. Consistent with: **Smart Transmit / rtsar enforcement is tied
to the active carrier MCFG; the no-active-config state uses static SAR only.**

Open gap: we do not yet have a single run that both registers/attaches AND omits
rtsar on a deliberately non-carrier config. The runtime PDC deselect cannot apply
without a modem refresh (blocked by the no-mpss-stop rule), and the pristine
restore lands in sim-missing. The earlier good run is the only register-and-no
-rtsar data point, on a carried (not pristine) config set.

## Next candidate (not run; boot budget was 2/2)
Reproduce the earlier good run's exact carried config set (no active carrier
config but with the per-registration SIM state intact) rather than the pristine
set, so the modem both registers and skips rtsar — i.e. identify/snapshot a copy
set that is registration-capable yet has the carrier config deactivated, which
needs a way to clear the active flag that survives a cold boot without a runtime
modem refresh.
