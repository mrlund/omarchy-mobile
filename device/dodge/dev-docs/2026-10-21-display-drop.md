<!-- SPDX-License-Identifier: MIT -->
# 2026-10-21: intermittent display drop at bind (both kernels)

Symptom: the first panel commands time out (`dsi_cmds2buf_tx: cmd dma tx
failed ... -110`), then kickoff/frame-done timeouts and vblank WARNs.
Times CEST. 7.3 boots are one-shot (`fastboot boot`); boot_a never flashed.
Budget for this investigation: 6 boots; used 4 (7.3 boots 6-9).

## Tools (7.3 only)

- `msm.ko` DIAG (trial `206e7f214`): at the first DCS transfer, before and
  after, dumps the DSI ctrl (0x300), PHY, lane and PLL registers, the PHY
  and DSI supplies (enable, uV), every DSI clock (rate, enable, prepare,
  parent) and the runtime-PM state. At MDSS init it logs which MDSS clocks
  ABL left on.
- `kernel-7.3/rootfs/omamobile-display-diag(.service)`: logs the MDSS GDSC
  state and its collapse count from early boot until the panel is up, then
  the clk/regulator/genpd summaries. `ConditionKernelVersion=7.3*`.
- `kernel-7.3/rootfs/omamobile-kmsg-sync(.service)`: copies dmesg to
  `/var/log/omamobile/kmsg-<R>-<boot>.txt` and fsyncs it every second
  for 3 min. Needed because the stage 2 DTB has no ramoops and journald
  loses the last ~20 s on a reset. Same condition.
- A first DIAG build also read VBIF registers from the DSI path. That
  boot (6) hung before any log reached disk (probably an unclocked read
  with the DPU suspended). It was removed for boot 7.

## Boots

| # | time | msm.ko | display | notes |
|---|---|---|---|---|
| 6 | 16:21 | diag1 (with VBIF read) | ? | no log; hung, back on 6.16 by itself |
| 7 | 16:33 | diag2 | **bad** | tx1 ok, tx2 -110; SMMU fault at splash end; died ~28 s |
| 8 | 16:42 | + splash identity map | **bad** | no SMMU faults at all, still -110 (after a few good commands); died ~28 s |
| 9 | 16:47 | + autorefresh stop | good | autorefresh was already off (cfg 0) at handover, so a lucky boot; survived |

## Findings

- **DSI/PHY config, supplies and clocks are identical in good and bad
  boots.** At tx1-pre: vdds 880 mV and vdda 1.2 V enabled, byte 182.16 MHz,
  pclk 194.30 MHz, esc 19.2 MHz, parents the DSI PLL, same DSI and PHY
  registers. Only PLL calibration readbacks (pll+0x1b8..0x1cc,
  0x274..0x27c) differ, and they differ between bad boots too.
- **The failure signature is the same as the 6.16 GDSC wedge of 2026-10-20
  (display-msm.md 39):** `STATUS0 00020003`, `CLK_STATUS 008037c3`, no DSI
  error IRQ. The first command goes through; a later one stalls in the DMA
  fetch. So it is the AXI path (MDP/VBIF/NoC), not the DSI or PHY.
- **The GDSC does not collapse before bind** (bad boots 7, 8: `on
  collapses=0` from dispcc load to panel up), so it is not a repeat of
  the GDSC wedge.
- **The PLL lock message is not a marker.** `DSI PLL(0) lock failed` (2x)
  is in every boot, good or bad.
- **ABL's INTF autorefresh is off at handover** (`intf1/intf2 cfg
  00000000`).
- **SMMU faults on the splash:** msm attaches its own domain, which drops
  the splash identity map. Every bad 7.3 boot has a fault at
  `iova 0xfd965800` (the last 6 KiB of the 1440x3168x4 frame), and good boot 2
  did not. With the splash identity-mapped read-only in msm's domain
  (`ef1155422`), boot 8 had no faults but still failed. So the fault is
  a symptom, not the cause. The map is kept on the trial branch because it
  removes the noise.
- **Boot 5 and the deaths:** with no ramoops, pstore is empty. Boots 7
  and 8 stopped writing kmsg between 27.4 and 28.4 s, right after the
  `sync_state() pending` lines. Those are informational in strict mode
  (`FW_DEVLINK_SYNC_STATE_TIMEOUT` is off), so they are not the cause. Only
  bad-display boots die (5, 6?, 7, 8). Good boot 9 survived, and bad boot 4
  lived 5 min. It returns to 6.16 by itself, so this is the Gunyah
  watchdog or panic=10. Cause not captured. The next step there is the
  `ramoops` stage2-dtb option (needs a chain repack).
- **The previous kernel matters on 6.16.** Of 6.16 boots today, 4 of 5 that
  followed a 7.3 boot failed: after 5, 6 and 7 (all three died), and
  after a clean reboot from good 7.3 boot 9; only the one after boot 8 was
  clean. 3 of 3 boots that followed a 6.16 boot by warm reboot were clean
  (16:11, 16:30, 16:55). So state that survives a warm reset through ABL
  (panel, PMIC rails, or display/NoC hardware) seems to carry over.
  7.3 itself fails 5 of 7 although it always starts from a 6.16 boot via
  fastboot.

## Next

- Cold vs warm, which needs Martin: full power-off, then 6.16 and 7.3 from
  cold. If cold boots are clean, the carried-over state is the lead
  (panel reset/power sequencing on shutdown, or ABL reinit).
- Then: ramoops via `DTB_OPTS='ramoops splash fb'` for the death, and the
  shutdown path (what 7.3 leaves in the panel and DSI at reboot).

## Round 3: cold vs warm (2026-10-22, CEST)

Martin's cold-start controls on 6.16 (0 `tx failed` each): R1 09:33, a
poweroff with USB attached (the phone powers itself back on, so it is
effectively warm), clean. R2 09:35, USB unplugged, off 30 s, power key,
a true cold start, clean.

| # | time | from | display | notes |
|---|---|---|---|---|
| 7.3 boot 10 | 09:39 | cold-started 6.16 (R2), via fastboot | **bad** | tx1 ok, then -110 (same signature). Died at about 96 s, back to 6.16 by itself |
| 6.16 | 09:40 | warm (watchdog) after bad 7.3 boot 10 | clean | so 6.16 after 7.3 is now 4 of 6 bad |
| 7.3 boot 11 | 09:44 | that 6.16, via fastboot | good | `omamobile-unplug-poweroff` armed |

So a cold start before 7.3 does not prevent the 7.3 drop. Limitation:
7.3 can never be cold-started directly, because a one-shot always goes
through fastboot (a warm path) from a running 6.16.

`rootfs/omamobile-unplug-poweroff(.service)`: 7.3 only, and only with
`/etc/omamobile/unplug-poweroff.enable`. Once the gadget has been
configured, unplugging USB for 3 s runs `systemctl poweroff --force`. This
is needed because a poweroff with USB attached powers the phone back on.
Step 2 (Martin unplugs 7.3, waits 30 s, cold-starts into 6.16) is pending.
Display budget: 6 of 6 boots used.
