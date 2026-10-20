<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20: Bluetooth on dodge (WCN7860 / peach, hci_qca on UART14)

Follows [2026-10-20-wifi-qcc2072-port.md](2026-10-20-wifi-qcc2072-port.md).
Device names from scans and the BD address are left out on purpose.

## Result

`hci0` comes up at boot, `bluetoothd` powers it (`Powered: yes`), and a 20 s
`bluetoothctl scan on` sees nearby devices (3). This survives a reboot
(checked 16:35 CEST). Wi-Fi stays connected the whole time. Pairing is not
tested: it needs a device in pairing mode, so it waits for Martin.

## Hardware

- BT is the "Ganges" side of the WCN7860 (peach) combo on QUP UART14
  (`serial@898000`; stock: `qcom,msm-geni-serial-hs`, wakeup byte `0xfd`).
- Power comes from the same `qcom,wcn7850-pmu` power sequencer as Wi-Fi,
  target `bluetooth`. BT enable is `pm8550ve_f` GPIO 3, sw-ctrl GPIO 18,
  as in stock's `bt_peach` node.
- Controller: product id `0x21`, SOC `0x40210200`, ROM `0x200`, patch
  `0x6d58`, controller version `0x02000200`. HCI version 14, manufacturer 29.

## Firmware

From the phone's own `bluetooth_a` partition (vfat), mounted read-only from a
copy: `image/gngbtfw20.mbn` (ELF rampatch, `BTFW.GANGES.2.0.0-00343`) and
`gngbtnv20.bin` plus its `.bXX` board variants, 27 files, copied to
`/lib/firmware/qca/`. Not committed. `bluetooth/install` does the copy when the
files are missing. No persist data is needed: the NVM in `bluetooth_a` is
enough for setup and scanning.

## Kernel (wt-dodge, branch `omamobile-dodge`, local only)

| Commit | What |
|---|---|
| `ff4e23cc6` | Bluetooth: qca: add WCN7860 support. ROCKNIX SM8750 patch 0045 (Teguh Sobirin) ported to 6.16: `QCA_WCN7860`, ELF rampatch `qca/gngbtfw%02x.mbn`, NVM stem `gngbtnv` with board id, the peripheral baud packet before the speed change. Five hunks redone by hand; the soc data has no `HFP_HW_OFFLOAD` (not in 6.16). |
| `b78a51b77` | arm64: dts: qcom: sm8750-oneplus-dodge: enable Bluetooth (`qcom,wcn7860-bt`, node enabled). |

Both build. The stage 2 DTB differs from the previous one only in that node.
The Image and initramfs are unchanged; BT modules (`bluetooth`, `btqca`,
`btbcm`, `hci_uart`, `ecc`, `ecdh_generic`) sit in
`/usr/local/lib/omamobile/bt/`.

## BD address: placeholder

The controller registers **unconfigured** (`missing options: public-address`):
the real address lives in persist, which we do not read. `omamobile-bt`
generates one random, locally administered address (first octet `02`) once,
keeps it in `/var/lib/omamobile/bt-public-addr` (mode 600, on the phone only)
and sets it with `btmgmt -i 0 public-addr` at every boot, so pairings survive
reboots. The Wi-Fi MAC is a placeholder too.

## Attempts (CEST)

1. **bt-1, 16:24, failed (procedure).** Packed the chain image with the
   default `STAGE2_CMDLINE` and `DTB_OPTS`. Stage 2 stayed in the initramfs (no
   root mount; SSH worked). Repacked with `DTB_OPTS='splash fb'` and the
   cmdline from the previous image (`... omamobile.ufs-probe
   omamobile.userdata-rw`), flashed `boot_a` at 16:27, `set_active a`.
2. **bt-2, 16:29, worked (manual).** insmod chain, rampatch and NVM download,
   setup done in about 1.5 s, public address set, `bluetoothd`, scan: 3
   devices.
3. **bt-3, reboot 16:31, failed.** Services active, firmware loaded, but the
   script logged "hci0 configured" and skipped the address: the
   `/sys/class/bluetooth/hci0` node exists before `hci_qca` setup ends, so
   `btmgmt config` did not yet report the missing address. No controller in
   `bluetoothctl show`.
4. **Claude consulted, 16:33** (two failures). Agreed with polling mgmt
   instead of sysfs, keeping the address stable, not chasing `-84` now, and
   asked for a BT power-cycle test with Wi-Fi up.
5. **bt-4, reboot 16:34, worked.** The script now polls up to 30 s until
   `btmgmt info` lists hci0 as a configured controller or `btmgmt config`
   reports the missing public address. Up at 16:35: address set, `Powered:
   yes`, scan 3 devices, Wi-Fi connected.
6. **Coexistence, 16:36.** Three `btmgmt power off/on` cycles (each
   re-downloads the firmware) during a 20-packet gateway ping: 0 % loss, no
   new ath12k line in dmesg.

## Notes

- One `Frame reassembly failed (-84)` right after the peripheral baud packet,
  every boot and every power-on. Bytes at the old rate across the speed
  change; the download that follows always succeeds. Chase it only if setup
  starts failing.
- `bluetooth/install` installs `omamobile-bt` and its unit, enables it and
  `bluetooth.service`, and copies the firmware if missing (checked: after
  moving `/lib/firmware/qca` away it restored 27 files with identical md5;
  the second run changed nothing).

## For Martin (pairing)

Put headphones or a phone in pairing mode near the dodge, then on the dodge:
`bluetoothctl`, `scan on`, wait for the device, `pair <addr>`, `trust
<addr>`, `connect <addr>`. If you want the phone's real BD address instead of
the random one, read it from OxygenOS (Settings, About device, Status) and
write it to `/var/lib/omamobile/bt-public-addr` on the phone; it is not
committed.
