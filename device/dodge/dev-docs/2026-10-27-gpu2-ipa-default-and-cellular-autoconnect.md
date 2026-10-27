<!-- SPDX-License-Identifier: MIT -->
# 2026-10-27 — gpu2: IPA in the default kernel, modem on, cellular autoconnect

**Goal.** Fold IPA (mobile data) into the flashed default kernel, turn the
modem flag on by default, and let NetworkManager bring up cellular data on its
own, with Wi-Fi still preferred.
**Phone.** OnePlus 13 (dodge). No serial, IMEI, IMSI, ICCID, number or MAC.
**Kernel.** `7.3.0-rc6-dodge-gpu2` (gpu1 + IPA, patches 0067-0074), flashed
to boot_a. It replaces `7.3.0-rc6-dodge-gpu1` (usbfix1 initramfs).
**Result.** Pass. gpu2 matches gpu1 with the flag off. With the flag on it
registers, NM autoconnects and data flows, a graceful reboot with the MPSS
running is clean, and two flag-on reboots of the flashed default each passed.
The flag is now **on** by default.

Rules as before. rmtfs serves writable copies only. The 12 real partitions
(modem a/b, modemst1/2, fsg, fsc, both NV backups, qweslicstore a/b, persist)
were hashed before and after every boot and never changed. persist was not
mounted and the MPSS was never stopped. Auto-restart stayed off. There were no
PDC writes, no SMS or calls, and no faked license responses. The battery gate
ran before every reboot. Every EFS snapshot set was kept in three places and
checked with sha256. Only boot_a was written, and slot a was set active.

## What we did

1. Built `dodge-gpu2` on the gpu1 tree (`f08f72d3e`), not on the pr2 branch,
   because pr2 drops `only_adsp` and gpu2 has to behave like gpu1 with the
   flag off. We added Koskovich's four IPA patches (Eliza binding, the v5.5
   data fix, the HW filter stats QMI request, Eliza data) and four of ours
   (SM8750 compatible, IPA and IMEM nodes, enable on dodge, 3-cell GIC
   interrupts). The config is byte-identical to gpu1's. `ipa.ko` is the only
   module that differs. The skip-units file drops `omamobile-mm-netport`.
2. NM profile `omamobile-cellular`: gsm, APN `internet`, autoconnect at
   priority -10 with unlimited retries, route metric 700 (Wi-Fi uses 600), and
   no secrets.
3. Trials by `fastboot boot` (nothing written), each returning to the gpu1
   default:
   - G1: flag off, a feature check against a gpu1 baseline.
   - G2: flag on, the units, then a manual ModemManager connect.
   - G3: flag on, NM autoconnect, then Wi-Fi off and back on.
   - G4: flag on, then `systemctl reboot` while the MPSS was running.
4. Flashed `CANDIDATE-7.3-gpu2-boot_a.img` to boot_a, ran `set_active a` and
   rebooted (F0, flag off). Then we set the flag and ran two graceful reboots
   of the flashed default (F1, F2). Each was followed by a check at about
   50 s and a late check at about 160-180 s.

## What happened

| boot | kernel | flag | result |
|---|---|---|---|
| G1 | gpu2 trial | off | Same as gpu1: GPU (GMU fw, 5 render clients), DSI, Hyprland, touch, USB, Wi-Fi pings, BT, audio sink, sensors. IPA is okay in the DT but not loaded. Same error-level kmsg set. oops 0, rtsar 0. |
| G2 | gpu2 trial | on | All units succeeded. Registered (LTE) 8 s after online. The manual connect on `qmapmux0.0` pinged 4/4 on two targets. Stable for 150 s, rtsar 0. |
| G3 | gpu2 trial | on | NM autoconnected 14 s after registration. With Wi-Fi off, the default route was cellular (metric 700): ping, DNS and HTTPS worked. With Wi-Fi back on, it was the default again within 10 s and cellular stayed up. rtsar 0. |
| G4 | gpu2 trial | on | `systemctl reboot` with the MPSS running: the journal is clean up to "Journal stopped". The next boot started about 2 s later, with no hang and no watchdog wait. Nothing stopped the MPSS. |
| F0 | gpu2 flashed | off | The slot was marked successful (both GPT CRCs verified) and the deadline clean check passed. Full feature parity. |
| F1 | gpu2 flashed | on | Clean graceful reboot. Units OK, good set restored, registered in 8 s, NM autoconnected, cellular ping 4/4. Late check: deadline clean, Wi-Fi was the default, cellular ping 4/4, DNS ok, rtsar 0, no modem crash. |
| F2 | gpu2 flashed | on | Same as F1 (registered in 8 s, ping 4/4, rtsar 0, no modem crash at about 164 s). |

Routes with both links up: Wi-Fi is the IPv4 default (metric 600) and
cellular sits behind it (700, or 20700 while NM is still settling). NM may
make cellular the IPv6 default when the Wi-Fi network has no IPv6.

Two things we saw that don't matter: an occasional lost ping to the Wi-Fi
gateway (internet over Wi-Fi was fine, and a recheck got 5/5), and
`systemd-backlight@` failing, which gpu1 does too.

## Learning

- The worry that a reboot with the MPSS running would hard-reset the phone
  did not come true. IPA's `.shutdown` tears down its modem side but does not
  stop the remoteproc. The modem units have no ExecStop. systemd-shutdown
  finished and the reboot took about 2 s. Keep the units free of any stop
  action.
- With the flag on, a rollback to gpu1, s1 or 6.16 is still safe. Without an
  IPA DT node `omamobile-modem-efs` leaves the copies alone and the MPSS is
  never started.
- Rollback: `tools/dodge-restore-73gpu1u` (gpu1 with usbfix1), then
  `-73gpu1`, `-73s1`, `-616`. `tools/dodge-restore-73gpu2` puts gpu2 back.
- Session logs should also filter IPv6 addresses and BSSIDs. The local
  redaction filter missed both once, and the local logs were scrubbed. No
  identifier is in git.
