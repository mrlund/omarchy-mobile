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
- Superseded by Round 4 below. Then: ramoops via `DTB_OPTS='ramoops splash fb'` for the death, and the
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
Step 2 result: the unit did **not** fire when Martin unplugged at about
09:56. The UDC stayed `configured` after the unplug (no carrier loss on
usb0 in the journal). This is the same open bug as the USB gadget not
noticing a replug. Martin powered off from the Omarchy menu instead
(normal poweroff at about 746 s), waited 30 s and cold-started: 6.16 was
clean (0 `tx failed`). The flag has been removed. Tally: a cold start
after 7.3 gave 1 clean 6.16 of 1, against 4 bad of 6 warm.

**Green flashes (Martin, cold 6.16 boot about 09:58):** during the console
text, quick green flashes in a band about 5 mm wide, first down one side
and then along the bottom, then gone. They look like a scan-out of the
wrong memory, stride or format (DSC slice/pitch, or a stale splash fetch)
during the handover from simpledrm to msm. Not reproduced or captured.

## Round 4: memory-bus lead (7.3 boots 12-15, 2026-10-22, CEST)

`omamobile-display-diag` now also logs the `interconnect_summary` nodes on
the display path (`qnm_mdp`, `qns_mem_noc_hf`, `qnm_mnoc_hf`, `ebi`,
`qhs_display_cfg`, `qns_gem_noc_cnoc`, `qnm_gemnoc_cnoc`) at pre-bind,
after the panel and 4 s later, plus every device with `state_synced`. On
7.3 the node names carry an `@provider` suffix.

| boot | time | change | display | notes |
|---|---|---|---|---|
| 12 | 10:04 | icc diag (regex missed 7.3 names) | bad | died at about 20 s |
| 13 | 10:07 | icc diag fixed | good | |
| 14 | 10:11 | same | bad | early SMMU fault at 0.40 s, died at about 27 s |
| 15 | 10:16 | fix 1: `dodge_dpu_handover()` (0028): dump ABL CTL/INTF/SSPP at DPU init, reset any active CTL | bad | -110 at 9.24 s, alive to at least 77 s |

Findings:
- **Interconnect is ruled out.** The DT paths are the same on both kernels
  (`mdp0-mem` MASTER_MDP to EBI1, `cpu-cfg` APPSS to DISPLAY_CFG). icc
  `sync_state` is unchanged in 7.3 and never completes globally on either
  kernel, so the init bandwidth (INT_MAX) stays on every display node, good
  boot and bad, and on 6.16 too. The votes are the same (mdss peak 400000,
  dpu peak 800000, cpu-cfg 57000, `reg_bus_bw` 57000). The only difference
  is the DPU average vote: 2903040 on the good boot and 0 on the bad one,
  because the CRTC is never enabled there (a consequence). sm8750 icc has no
  QoS on either kernel. `mmss_noc` reaches `state_synced` at 8.1-8.4 s on
  both.
- **The DPU is idle at DPU init.** On bad boot 15, CTL0-5 read top f0000000
  with flush/start/intf_active/fetch_active/layer 0, INTF0-3
  status/frame/line 0, no SSPP has a source address, and autorefresh is
  off. So the reset in 0028 never ran. Caveat (Claude): `msm_mdss` already
  resets `DISP_CC_MDSS_CORE_BCR` at probe, before this dump (6.16 does the
  same), so the dump cannot show what ABL left running.
- **The splash handover matches 6.16.** Same reserved `splash` region,
  simple-framebuffer, and the same `msm_mdss_reset`. The `mdp` core clock
  reads off (`en 0`) at mdss probe on good and bad boots alike.
- The early SMMU faults (SID 0x800, inside the splash, at 0.40-0.43 s
  when arm-smmu probes) appear on only 2 of the 6 saved bad boots (7, 14) and
  on none of the good ones. ABL's MDP is sometimes still fetching when the
  kernel starts, but bad boots 8, 10, 12 and 15 have no fault, so that
  alone does not explain them.
- Fix attempts that failed: the splash identity map (0026) and the CTL reset
  (0028). Claude consult 2: `logs/claude-consult-dsi-dma2.txt`. Its top
  pick is a pending AXI read left by ABL's pipeline (reset or clock gate
  mid-fetch), which wedges the shared MDP/DSI AXI path. Its suggested E1/E2
  (sample the INTF counters before the BCR reset, and let the frame drain
  before resetting) would have to run with the `mdp` clock already off, so
  they are weak.

**New lead: the fastboot path.** Every 7.3 boot is a `fastboot boot`
one-shot, and every flashed 6.16 boot goes ABL -> boot_a. The only 6.16
one-shots on record (rmtfs, 2026-10-21) lost the display 1 of 2 times. The
"6.16 after 7.3" failures are also the first boot after a fastboot
session. So ABL's fastboot UI (a different panel/MDP state) may be the
carried-over state, not 7.3 code. A cheap test: `fastboot boot` the 6.16
`boot-chain.img` from a cold-started, clean 6.16, 2-3 times. No code change.

Budget: 4 of 6 lead boots used (12-15). The phone is on 6.16, but its
display is **lost** (11 `tx failed` after the warm 6.16 boot at 10:28;
the one before it, after 7.3 boot 15, had 3). It needs Martin's cold start.

## Round 5: fastboot-path test, 6.16 only (2026-10-22, CEST)

Image: a read-only dump of the flashed boot_a (`boot_a-dump-1022.img`,
outside the repo), the exact flashed 6.16 chain, one-shot with `fastboot
boot`. Nothing was flashed, and the slot stayed `a` the whole time. Per boot: 4 samples
of `cmd dma tx failed`, kickoff/frame-done/vblank timeouts and DSI state
over about 2 min, then 5 Hyprland `dpms` transitions. Battery at 100%; the
F1 gate read +11 mA (full, not charging) and passed on the full-battery
rule, all others passed normally.

| # | time | path | from | display | first failure | SMMU faults |
|---|---|---|---|---|---|---|
| B0 | 12:26 | flashed boot_a | Martin's true cold start | clean, dpms ok | - | 1 |
| F1 | 12:37 | `fastboot boot` | B0 | clean, dpms ok | - | 0 |
| W1 | 12:41 | warm reboot, boot_a | F1 | clean, dpms ok | - | 0 |
| F2 | 12:45 | `fastboot boot` | W1 | clean, dpms ok | - | 0 |
| F3 | 12:49 | `fastboot boot` | F2 | clean, dpms ok | - | 6 |
| W2 | 12:53 | warm reboot, boot_a | F3 | **bad** | 7.18 s (`ff`, then `51`, -110) | 1 |

- The fastboot one-shot path itself is **not** the trigger: 3 of 3 clean,
  each surviving the dpms cycles.
- The failure came on a plain warm reboot of the flashed image (W2). So the
  "6.16 after 7.3" pattern is not about 7.3, nor about fastboot. Warm 6.16
  boots fail at some base rate. The tally of warm boots after a one-shot is
  now 5 bad of 8 (W1 clean, W2 bad).
- SMMU faults at the end of the splash (iova 0xfd965800, SID 0x800) also
  appear on clean 6.16 boots (B0, F3), so they do not tell the two apart.
- The phone ended on flashed 6.16 with the display lost; it needs Martin's
  cold start.

## Round 6: 6.16 warm-reboot shutdown path (2026-10-22, CEST)

Start: Martin's true cold start at about 13:02, clean. Each run: battery gate
(full-battery rule where needed), the pre-reboot step, `systemctl reboot` of
the flashed boot_a, then the kernel journal of the new boot.

| # | time | pre-reboot step | from | result | first -110 |
|---|---|---|---|---|---|
| D1 | 13:04 | Hyprland `dpms off` (dpms read Off), 4 s | clean cold boot | **bad** | 7.11 s |
| C1 | 13:07 | none (recovery try) | bad | **bad** | 7.06 s |
| U1 | 13:11 | stop Hyprland, unbind `msm-mdss` (rc 0, `mdss_gdsc` off-0), then reboot | bad | **bad** | 7.03 s |

- C1's gate read +131 mA with the display wedged (Hyprland spinning). It
  passed on the full-battery rule at 100%. U1 was gated after stopping
  Hyprland (-16 mA, OK).
- Neither no-code step helped (2 failed attempts). Claude consult 3:
  `logs/claude-consult-warm-sticky.txt`.
- **Warm reboots are sticky.** A bad boot was followed by a bad warm boot
  3 of 3 times (W2 -> D1 was cold in between; C1 and U1 follow bad boots).
  Cold starts are 4 of 4 clean. So the state survives a warm reset but
  not a cold power-off, and MDSS-internal state is ruled out: the GDSC was
  off before U1's reset.
- **Lead: the panel IC is never power-cycled by Linux.** The DT gives the
  panel `vddio` L12B 1.8 V, `vci` L13B 3.0 V and `vdd` L11B 1.0 V, but
  `panel-aa569-p-3-a0019-dsc` never requests them: all three show
  `users=0`, state `unknown` (RPMh, still on ABL's vote). Prepare only
  pulses reset (GPIO 98, active low), and unprepare sends sleep-in and
  asserts reset. A PS_HOLD warm reset leaves PMIC LDOs on, so a wedged
  panel stays wedged until a cold power-off. Because the reset pulse in
  prepare doesn't clear it, holding reset alone (Claude's T1) is unlikely
  to help; cutting the rails (T2) is the test. The three rails are used only
  by the panel in our DT.
- The phone ended on flashed 6.16 with the display lost; it needs a cold start.

Next (one change per boot, kernel module only, nothing flashed): build
`panel-aa569-p-3-a0019-dsc.ko` with the three supplies as a regulator bulk.
Enable them in prepare before the reset pulse. In unprepare and a new
`.shutdown`, assert reset, then turn off vci, vdd and vddio, and wait
about 200 ms. Log `regulator_is_enabled()`. Test from a bad boot (3/3-bad
baseline), then require 5+ clean warm reboots in a row. Also add
`DSI_LANE_STATUS` (0x0a8) to the -110 dump, to tell a stuck lane from a
host/PLL problem.

## Round 7: panel owns its rails (6.16 module only, installed 2026-10-22 13:3x CEST)

Kernel patches `0051` (the panel driver takes `vddio`/`vdd`/`vci` by their
existing DT names; it turns them on one at a time before the reset pulse,
and on unprepare, failed init and shutdown asserts reset, turns off vci,
vdd, vddio and waits 200 ms; no voltage is ever set) and `0052` (DIAG:
`LANE_STATUS` and friends at every `cmd dma tx failed`). Built from
`out-dodge-cfg1` with `KERNELRELEASE=6.16.0-gbd9587d65`, vermagic matches,
and the dependencies (`backlight`, `drm_display_helper`) match
`modules.dep` in the `.held` tree. The loader insmods by path, and there is
no `/lib/modules/<R>`, so depmod does not apply.

Installed in `/usr/local/lib/omamobile.6.16.0-gbd9587d65/display/`
(md5 panel `e4a2cfd8`, msm `9930b870`). The old modules are next to them as
`panel-aa569-p-3-a0019-dsc.ko.pre-rails` (`463dd36b`) and
`msm.ko.pre-lanediag` (`69f90211`); the old panel module is also in
`kernel/fallback/`. Not rebooted: the current boot still runs the old
modules, so the next boot (Martin's cold start) is the first with 0051.

Behaviour changes to expect: every screen-off (dpms off) now powers the panel
down and every screen-on does a full power-up and init, so wake may be slower.
A failed panel init now also cuts the rails, so a retry inside the same boot
starts from an unpowered panel. At reboot or poweroff the log should show
`dodge: panel power off (shutdown): vci 0 vdd 0 vddio 0` (in the
journal of the previous boot, if it gets flushed in time).

Revert (on the phone, then reboot):
`cd /usr/local/lib/omamobile.6.16.0-gbd9587d65/display && cp panel-aa569-p-3-a0019-dsc.ko.pre-rails panel-aa569-p-3-a0019-dsc.ko && cp msm.ko.pre-lanediag msm.ko && sync`

Plan once Martin has cold-started: check the rails came up (`users=1`) and
the display is clean, then a series of warm reboots. Require 5+ clean in a
row. A clean warm boot after a bad boot would be the first ever.
