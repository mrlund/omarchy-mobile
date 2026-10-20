<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20: ath12k at boot, NetworkManager on Wi-Fi, regulatory

Follows [2026-10-20-wifi-scan.md](2026-10-20-wifi-scan.md).

## Boot-time load, once

- `wifi/omamobile-wifi-pcie` + `.service`: the existing power sequence and
  PCIe rescan, now in git (installed in `/usr/local/sbin/` and
  `/etc/systemd/system/`).
- `wifi/omamobile-wifi-ath12k` + `.service` (enabled): after
  `omamobile-wifi-pcie.service` it waits up to 30 s for `17cb:110e`.
  It then loads `libsha256-generic`, `sha256`, `rfkill`, `libarc4`,
  `cfg80211 ieee80211_regdom=DK`, `mac80211`, `mhi`, `qrtr` and `qrtr-mhi`,
  skipping any that are already loaded, and then `ath12k.ko`.
- **Never twice:** the script exits if `/sys/module/ath12k` exists or
  `/run/omamobile-ath12k.tried` exists. The stamp is written before the
  insmod and stays even if the insmod fails. The unit also has
  `ConditionPathExists=!/run/omamobile-ath12k.tried` and no `Restart=`.
- Reboot at 15:22 CEST (`systemctl reboot`, ath12k loaded): shutdown was
  clean and SSH was back in 32 s. On the new boot:
  - the unit ran once and the stamp exists;
  - one firmware bring-up in dmesg (`qmi qdss config sent` once);
  - `wlp1s0` registered at 7.7 s;
  - no oops or call trace;
  - `dodge-boot-success` ran at 15:24:52 and slot A is still marked
    successful.

## NetworkManager

- Removed `/etc/NetworkManager/conf.d/90-dodge-wlan-unmanaged.conf` (backup
  in `/root/dodge-backup/` on the phone). It was never in git.
- `usb0` is still unmanaged: `/usr/lib/NetworkManager/conf.d/10-omamobile-usb.conf`
  (`unmanaged-devices=interface-name:usb0`) is untouched, and systemd-networkd
  still owns `usb0`. SSH over USB kept working through the change and the
  reboot.
- `nmcli dev`: `wlp1s0 wifi disconnected`, `usb0 ethernet unmanaged`.
  `nmcli dev wifi list` shows 16 BSS on channels 1, 6 and 11.

## Regulatory

- **cfg80211 rejected `regulatory.db`** ("malformed or signature is
  missing/invalid"). The database is signed with sha256/RSA, and
  `CONFIG_CRYPTO_SHA256=m` was never loaded (there is no `/lib/modules`
  tree for `request_module`). With `crypto/sha256.ko` and
  `lib/crypto/libsha256-generic.ko` (copied from the same build to
  `/usr/local/lib/omamobile/`, not committed) the database verifies, and
  `ieee80211_regdom=DK` makes the global domain `DK: DFS-ETSI`.
- **The phy is self-managed:** ath12k sets `REGULATORY_WIPHY_SELF_MANAGED`,
  and the firmware's domain applies: `phy#0 country US: DFS-FCC`. User
  hints (`iw reg set DK`) only reach the firmware with
  `CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS`, which is off, so they are
  ignored.
- **"Failed to set the requested Country regulatory setting" is not
  fatal.** It is printed when a firmware regulatory event has a failure
  status. The firmware keeps its current domain (US), and scanning and NM
  keep working. Here it comes twice (one event per phy) at about 14 s,
  after the firmware's 11d scan, so the firmware rejected the country it
  learned from beacons. Why it rejects it is not known.

## 5 GHz: not seen

- The phone sees no 5 GHz BSS, with full scans, 5 GHz-only scans and NM
  rescans. The laptop in the same room sees three networks on 5240 MHz
  at about 55 % signal.
- `iw survey dump` shows the radio dwells on 5180-5825 and on 6 GHz (about
  50 ms each, 149 ms on 5745). The US rules allow active scan on 5180-5240.
  Regulatory is therefore not the reason: the 5 GHz receive path finds
  nothing.
- Hypotheses, most likely first:
  1. The hw mode is DBS_OR_SBS (mode 5, phy map `0x3`) and the 5 GHz
     phy/MAC mapping is wrong for peach with WCN7850 parameters. Pinning
     mode SINGLE, or parsing the second phy's caps, is the test.
  2. The board data (`bdwlan.b0e`) or the missing calibration (stock ran an
     8 s cold-boot cal; mission-mode-only here) leaves 5 GHz uncalibrated.
     Stock's CalDB was 0.
  3. Antenna switching or front-end GPIOs owned by the firmware or the SoC
     side that stock sets and this kernel does not.
  4. QCC2072/WCN7860 HAL/register differences (see below), if 5 GHz
     frames come in on a different ring.

## Connecting

The SSID given (`<redacted>`) is not among the networks the phone or the
laptop can see. The nearby networks with a similar name are 2.4 + 5 GHz
mesh SSIDs. The connection is created on the phone
(`/etc/NetworkManager/system-connections/dodge-wifi.nmconnection`,
`-rw------- root root`, autoconnect yes), and activation fails with
"The Wi-Fi network could not be found". Nothing about it is in git.

## Datapath risk (WCN7850 vs QCC2072 offsets)

Not tested, because nothing has associated yet. ath12k uses the WCN7850 `hw_regs`. Upstream QCC2072
moves the TCL rings by `+0x18` and the REO, SW2REO, REO command and REO status rings by
`+0x1c`, and has no `wbm_sw1_release` and no `reo1_qdesc_lut`. It also uses other PCIe QSERDES,
PCS, `gcc_pcie_hot_rst` and `qrtr_node_id` addresses, 32-bit REO
command/status and different HAL descriptors. Scan results arrive over WMI
(copy engine), not the data rings, so a working scan does not prove the
datapath. If peach follows QCC2072, expect TX completions or RX to fail or
corrupt once associated.
