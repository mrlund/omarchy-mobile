<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20: Wi-Fi datapath: peach uses the QCC2072 register layout

Follows [2026-10-20-wifi-boot-nm.md](2026-10-20-wifi-boot-nm.md). The
network name and password are `<redacted>` everywhere. The NM profile lives
only on the phone (`/etc/NetworkManager/system-connections/dodge-wifi.nmconnection`,
mode 600).

## Result

Not connected. Authentication and association work. The 4-way handshake
never completes, because the data rings are programmed at WCN7850 offsets
and peach has the QCC2072 register layout. That is now shown by a
read-only register dump on the phone. Fixing it means porting the QCC2072
HAL variant (registers, descriptors, 32-bit REO TLVs, RX descriptor ops)
to 6.16. That has not been started.

## Attempts

| # | Time (CEST) | Change | Result |
|---|---|---|---|
| dp-1 | 15:30 | NM profile with the right SSID (no module change) | Station add fails with `-ENOENT`: "failed to setup rx defrag context", because `crypto_alloc_shash("michael_mic")` finds nothing; nothing autoloads crypto modules here. Peer cleanup then gets `HAL_REO_CMD_UPDATE_RX_QUEUE ... (-105)`: the REO command ring is full and never consumed. `WARNING` in `ath12k_mac_op_unassign_vif_chanctx` on every retry. |
| dp-2 | 15:31 boot | Boot script also loads `ctr ccm ghash-generic gcm cmac michael_mic` | Authenticated and associated (2.4 GHz). After about 4 s the AP deauths (reason 2) because no EAPOL went either way; rx/tx counters stay 0. At about 38 s the firmware enters RDDM and ath12k restarts it. Autoconnect then switched off to stop the crash loop. |
| consult | 15:34 | Claude (required after two failures) | Agreed: the signature fits wrong data-ring offsets (mgmt and scan use WMI over the copy engines, so they work). Said not to swap in only `qcc2072_regs`: with correct offsets the hardware would parse WCN7850-format descriptors and could crash the host. Proposed a read-only register readback first. |
| dp-3 | 15:36 boot | Diagnostic build `034552311` (reads only): dump REO registers `0x280-0x2dc` before and after REO command ring setup | See below. Decisive. |

## Evidence (dp-3)

`HAL_SEQ_WCSS_UMAC_REO_REG + 0x280 ...` before ring setup:

```
0x280: deadc0de deadc0de deadc0de deadc0de deadc0de deadc0de deadc0de deadc0de
0x2a0: 00000000 00000000 00000000 00000000 00000000 00000000 00000080 deadc0de
```

after ring setup (the driver writes the ring at the WCN7850 base `0x28c`):

```
0x280: deadc0de deadc0de deadc0de deadc0de deadc0de deadc0de deadc0de deadc0de
0x2a0: 00000000 00000000 0ffff050 00000000 00000000 00000000 00000080 deadc0de
```

- `0x280-0x29c` read `0xdeadc0de`: there is no register there. The ring
  base, size, ID and MISC (enable) writes at `0x28c-0x29c` go nowhere.
- `0x2a8` is the QCC2072 `reo_cmd_ring_base`. It holds `0x0ffff050`,
  the low half of the host tail-pointer address. That value is what the
  driver writes at WCN7850 base `+ 0x1c` (`TP_ADDR_LSB`), which lands
  exactly on the real QCC2072 base register. The ring base the hardware
  sees is that address, with size 0, and the ring is never enabled.
- The same `+0x18` (TCL) and `+0x1c` (REO, SW2REO, REO status) shifts
  apply to the data rings, so EAPOL can't be sent or received.
- `0x3278` as the window register (already needed to read the version)
  is also QCC2072's (`WINDOW_REG_ADDRESS_QCC2072`).

## What the fix needs (next slice)

A peach `hw_params` entry built from upstream QCC2072 (ath-next / linux-next,
`wifi7/hal_qcc2072.c` and `wifi7/hw.c`) and ROCKNIX SM8750 patch 0039:

1. `qcc2072_regs`, including the PCIe QSERDES/PCS, `gcc_pcie_hot_rst` and
   `qrtr_node_id` addresses, with no `wbm_sw1_release` and no
   `reo1_qdesc_lut`.
2. The RX descriptor variant (`hal_rx_desc` QCC2072 layout and its
   accessor ops), `rxdma_ring_sel_config_qcc2072`, and
   `srng_create_config_qcc2072`.
3. 32-bit TLV headers for REO commands and REO status.
4. RX TID queue setup without the qdesc LUT.
5. The QCC2072 ring masks.

All five together, as one change; not the registers alone.

## Also fixed in this slice

- `wifi/omamobile-wifi-ath12k` loads the crypto modules mac80211 and
  ath12k ask for by name (`michael_mic`, `ccm`, `gcm`, `cmac`, and the
  `ctr`/`ghash-generic` templates). The `.ko` files come from the same
  build and are not committed.

## State left on the phone

- `ath12k.ko` = diagnostic build `034552311` (only adds log lines). The
  previous build is `ath12k.ko.wmi`.
- `dodge-wifi` profile exists with autoconnect **off**, so the firmware
  does not crash-loop on every boot. Re-enable it with
  `nmcli connection modify dodge-wifi connection.autoconnect yes` once
  the datapath is fixed.
- USB SSH was never interrupted; `usb0` stays outside NM.
