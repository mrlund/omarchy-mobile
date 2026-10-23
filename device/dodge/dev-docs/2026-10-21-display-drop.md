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

## Round 8: rails v2 (0053) and the warm series (2026-10-22, CEST)

**The two boots after 0051 (v1, rails off on every unprepare):**
- Boot 14:32:08 started 6 s after the bad U1 boot ended (14:32:02), so it was a
  warm reset, and that shutdown still ran the old module. **It failed at
  its first init (7.43 s)**, before any idle or unprepare. So this was the known
  warm-sticky failure, not an idle regression of 0051. The later -110s
  (backlight, wake re-init `ff 5a a5 07`) are the same dead host.
- Boot 14:44:05 (started 14 s after the previous one ended) was clean. At 15.6 s,
  v1 powered the panel off on unprepare (Hyprland's takeover modeset), and the
  power-up and re-init after it worked (0 errors, rails `users=1`).
- Lane dump on every failure: `status0 00020003 lane_status 00001f1f
  lane_ctrl 01000000 clk_status 008037c3 dln0_phy_err 00088888`.
  `LANE_STATUS` 0x1f1f means all four data lanes and the clock lane are in
  stop state (LP-11), none in ULPS. **The panel is not holding a lane.** The
  host's command DMA never starts transmitting, so this is a host-side
  stall (DMA fetch, as with the GDSC wedge), not the panel.

**0053 (v2):** rails are taken at probe (`users=1`) and stay on across
unprepare/prepare (unprepare and failed init only assert reset, as
before). They are cut only at shutdown and remove (reset asserted, vci,
vdd, vddio off, 200 ms). Installed `dda4e21c`; v1 kept as `*.ko.rails1`,
the original as `*.ko.pre-rails`.

Each boot below: a plain warm `systemctl reboot` of flashed boot_a, then 3
Hyprland `dpms` disable/enable cycles, then about 175 s without input
(idle-off is 150 s) and a wake.

| # | reboot | previous shutdown | display | dpms 3x | idle + wake | notes |
|---|---|---|---|---|---|---|
| R1 | 14:49:30 | v1, panel already off (idle) | clean | ok | ok | |
| R2 | 14:54:57 | v2, first cut of powered rails | clean | ok | ok | **Martin: a brief full-colour flash during the console, then back to the console** |
| R3 | 15:00:16 | v2 | clean | ok | ok | gate +53 mA at 100%, full-battery rule |
| R4 | 15:05:36 | v2 | clean | ok | idle-off did not fire (dpms stayed On); wake ok | |
| R5 | 15:10:54 | v2 | **bad** | - | - | first -110 at 7.57 s; 10 SMMU splash faults |
| R6 | 15:18:35 | v2, from bad R5 | **clean** | ok | ok | **first bad -> warm clean ever** (0 of 3 before) |
| R7 | 15:24:05 | v2 | **bad** | - | - | first -110 at 6.94 s |
| R8 | 15:37:11 | v2, from bad R7 | **bad** | - | - | no recovery; the series stopped |

- **Result: not fixed.** 6 clean of 8 warm boots, at most 4 in a row. The
  old baseline was about 60% bad warm. Bad -> warm was 1 of 2 clean,
  against 0 of 3 before. Cutting the rails at shutdown may help, but it
  does not prevent the stall, which matches the lane dump: the host is stuck
  with idle lanes.
- Runtime is fine with v2: 18 dpms transitions and 4 idle-off/wake
  cycles on clean boots, 0 errors.
- The shutdown log line can't be checked: journald stops before the
  kernel's device shutdown, so `dodge: panel power off (shutdown)` never
  reaches the journal. The R2 flash (the first ABL start after v2 cut powered
  rails) shows the panel did lose power. ABL's re-init of an
  unpowered panel shows garbage or a colour frame once.
- The phone ended dark on R8 (flashed 6.16, v2 module); it needs a cold start.

## Round 9: poweroff-with-USB, and the stuck host read live (2026-10-22, CEST)

**Track 1: does `systemctl poweroff` with USB attached (the phone powers itself back on) act like a cold start?**

| # | time | path | from | result |
|---|---|---|---|---|
| C | 15:56 | Martin: power off from the fastboot menu, 30 s, power on | bad R8 | clean (baseline) |
| P1 | 15:59:58 | `systemctl poweroff`, USB attached, self power-on | clean | clean, dpms 3x ok |
| P2 | 16:02:25 | same | clean | clean, dpms 3x ok |
| P3 | 16:04:40 | same | clean | **bad**, first -110 at about 5 s (16:04:45) |
| P4 | 16:08:12 | same | bad | **bad** |
| W1 | 16:14:22 | warm `reboot` | bad | **bad**, unrecovered; stopped here |

**Verdict: not a workaround.** A poweroff with USB attached behaves like
a warm reboot (1 bad of 3 from clean, no recovery from bad). The
self power-on doesn't remove enough power. Only a power-off with USB
unplugged has cleared the state so far.

**Track 2: the stuck controller, read live** (`kernel/diag/dodge_peek`,
an out-of-tree module whose init does its work and returns -EAGAIN, so
nothing stays loaded). It must only run while `ae94000.dsi` and
`ae00000.display-subsystem` are runtime-`active`: while the display
was idle-suspended it read all zeros (unclocked; it did not hang, but
don't rely on that).

- **Apps SMMU at the stall:** SID 0x800 maps to SMR[3], then CB9. CB9
  `SCTLR 0x67` (translation on, fault reporting, **terminate**, not
  stall). `FSR 0x400` (FORMAT bits only, no fault), `GFSR 0`. CB9's
  `FAR fd965800` is the old splash fault. **The SMMU is not holding the
  DSI read.**
- **DSI host** (6G offsets +4): `STATUS0 00020003`, `CMD_DMA_CTRL
  14000000` (FROM_FRAME_BUFFER, LOW_POWER), `DMA_BASE 0x1000`, `LEN 8`,
  `TRIG_CTRL 80001004`, `LANE_STATUS 1f1f`, `CLK_STATUS 008037c3`.
- **Live writes on the stuck controller, no effect** (DMA busy stays
  set): clearing `BLOCK_DMA_WITHIN_FRAME`, clearing the `TE` bit,
  writing `TRIGGER_DMA` again.
- **Already in place and not enough:** msm resets `DISP_CC_MDSS_CORE_BCR`
  at every probe (`resets` in sm8750.dtsi), and does a DSI soft reset
  (`DSI_RESET`) on every host power-on. Every dpms retry fails the same
  way, so neither reset clears the state.
- **While stuck and active:** DSI PLL `COMMON_STATUS_ONE` 0x51 (bit 0,
  locked). The byte0/byte0_intf/pclk0/esc0/mdp CBCRs read on
  (`08000001`). The `mdp_lut` CBCR reads `08000000` (enable bit clear)
  although Linux counts it enabled once. The PHY CMN registers are saved
  in `logs/peek3-616-bad-W1.txt`. Comparing against a good boot is still
  to do.
- Claude consult 4 (`logs/claude-consult-dma-stuck.txt`): a warm reset
  clears on-chip digital state, including the NoC, TBU and GCC
  handshakes. So it favours analog/off-chip state, the PHY/PLL rails left
  on by the PMIC. Next tests: (1) the same peek on a good boot at the
  same point; (2) on a stuck boot, send one DCS NOP through the
  TPG DMA-FIFO path (no memory fetch). If that completes, the fetch path
  is guilty (then ATOS on CB9); if it hangs too, the link/PHY is.
- The phone is dark on W1 (flashed 6.16, v2 panel module); it needs a cold start.

## Round 10: three-button reset, good-vs-bad peek, TPG NOP, VBIF (2026-10-22, 17:52-18:20 CEST)

**Three-button reset (Martin, USB in, no fastboot power-off):** it acts as
a warm reset, not a cold start.

| boot | window (CEST) | path | result |
|---|---|---|---|
| W1 | ~16:15-16:53 | my warm reboot | bad (my dpms wakes failed); log ends abruptly at 16:53 |
| 1st 3-button | 17:13-17:45 | three-button reset | **bad at boot** (first -110 at 7.1 s), not a later idle failure |
| 2nd 3-button | 17:45 | three-button reset | clean |

**Good-vs-bad peek (both with the display runtime-active):** the only
differences are `STATUS0` (0 vs 00020003), `CLK_STATUS` (2343 vs 008037c3)
and the DSI PLL calibration readbacks (pll +0x1c4/0x1c8/0x1cc/0x1f4/0x274/
0x27c). The PLL is locked in both. DSI config, PHY CMN and lanes are the
same, and so are the dispcc CBCRs, including `mdp_lut` (08000000 in both, so
not a lead). MDSS +0x90..0xcc read 1 after any runtime resume, good or
bad. Logs: `peek-616-good-b0*.txt`.

**TPG NOP (`dodge_peek act=4`):** DSI soft reset, then one DCS NOP
(`0x80050000`) from the TPG DMA FIFO, so no memory fetch. Offsets are from
downstream `dsi_ctrl_reg.h` / `kickoff_fifo_command()`.
- On a good boot (positive control), it completes: `INT_CTRL` bit 0 is
  set, busy clears, and the display is unaffected.
- On bad boot T2 (warm reboot 17:58), the soft reset clears the stall
  (`STATUS0 00020003` -> `00020000`, `CLK_STATUS` back to 2343). The FIFO NOP
  then **completes** (DMA_DONE).
- A memory DMA right after (`act=3`, the normal path) stalls again
  (`00020003`/`008037c3`), with no new SMMU fault.
- **The link/PHY and panel path work; the memory-fetch path is wedged.**

**The SMMU fault correlates 1:1** (6 boots in the journal): each bad boot
has exactly one CB9 fault (`iova 0xfd965800`, the end of the ABL splash,
SID 0x800) about 200 ms before the first -110. The clean boots have none.
The fault itself is old news (Round 3). The identity map (0026, 7.3)
removed it but not the -110.

**VBIF (`act=6`, read-only, 0xaeb0000):** the only difference good vs bad:

| reg | good T3 | bad T2 |
|---|---|---|
| `XIN_HALT_CTRL1` (+0x204, idle/ack bits 16+) | `ffff0000` | `ff7e0000` (xin0 and xin7 not idle) |
| `AXI_HALT_CTRL1` (+0x20c) | `00000030` | `00000000` |

xin0 is `SSPP_VIG0`, the pipe that ABL's splash is scanning from. So VIG0
has reads outstanding that never retire, and the AXI port is not idle. On
a warm boot, ABL's splash fetch is still running when msm attaches its
SMMU domain. The read hits terminate mode and the VBIF/AXI port wedges.
The DSI command DMA fetch (xin7?) then queues behind it. A cold start
has no running splash, so there is nothing to wedge.

**Side note:** on T2 the phone froze for ~6 minutes (18:00:31-18:06:53, no
SSH, USB gadget dropped). Kernel boottime advanced only ~1 min over that
span, so it was not a suspend. It recovered by itself. This is probably
the "locks up" Martin saw on the first three-button boot.

**Next:**
1. On the next bad boot, in place: request a VBIF xin0/xin7 halt (and an
   AXI halt), wait for ack, release, DSI soft reset, then memory DMA.
2. As the fix: stop the ABL VIG0/CTL fetch and drain the VBIF (xin halt)
   *before* msm attaches its IOMMU domain. Or keep the 1:1 splash map
   until the first commit, and check the VBIF with 0026-style mapping.

Logs: `tpg-616-good-b0.txt`, `tpg-616-bad-T2.txt`, `vbif-616-{bad-T2,good-T3}.txt`,
`smmu-fault-timeline.txt`, `tpg-T2-hang.txt`.

## Round 11 (2026-10-22, 18:15-18:45 CEST): xin ID, VBIF drain, pre-msm snapshot

**Boots** (warm `systemctl reboot`, battery gate each time; "full-battery
rule" = capacity 100%, only the current-sign check failed, treated as pass):

| boot | reboot (CEST) | result | notes |
|---|---|---|---|
| T1 | 17:56:54 | clean | |
| T2 | 17:58:09 | bad | ~6-min freeze (see Round 10) |
| T3 | 18:11:50 | clean | full-battery rule; xin ID test |
| T4 | 18:17:18 | bad | drain test, rebind test |
| T5 | 18:25:35 | bad | full-battery rule; pre-msm hook live from here |
| T6 | 18:28:36 | clean | full-battery rule |
| T7 | 18:30:20 | bad | |
| T8 | 18:32:02 | clean | full-battery rule |
| T9 | 18:33:33 | clean | left running, display on |

**xin of the DSI cmd DMA (good boot T3, `dodge_peek act=8`):** halting
xin7 (`xm=0x80`) reproduces the exact bad signature (STATUS0 `00020003`,
CLK_STATUS `008037c3`, no DMA_DONE). After release, a reset and memory DMA
completes in 5 ms. Halting xin0 does not block the DMA. **xin7 = DSI cmd
DMA.**

**In-place drain on bad boot T4 (`act=7 xm=0x81`): failed.** The xin0 and
xin7 halt requests never ack (the other xins do). The AXI halt never acks
(CTRL1 stays 0). All VBIF error registers are 0. After release, a DSI soft
reset and a memory DMA still stall at `00020003`.

**Rebind on T4:** stopped Hyprland, unbound msm-mdss (mdss_gdsc went to
off), rebound (the BCR reset runs in probe). The result was `ctl 1 reset
failure` ×3, then -110 again. The VBIF still read `ff7e0000` after the GDSC
collapse plus BCR. **The wedge survives MDSS power collapse**, so the lost
transactions sit outside MDSS (TBU/MNoC side). Runtime recovery is not
possible; only prevention can work.

**Claude consult** (`claude-consult-vbif-wedge.txt`): the lost reads are in
the TBU/MNoC. The identity map removed the fault but not the cause. Its
proposal: quiesce ABL's autorefresh/VIG0, then halt the xins and AXI
*before* the msm BCR and SMMU attach. It also suggested logging the state
right before the BCR.

**Pre-msm snapshot (`act=9`, read-only):** a systemd drop-in
(`omamobile-display-msm.service.d/90-dodge-premsm.conf`) runs it before
dispcc and msm load. It reads MDSS_GDSCR first and skips the MDSS reads
if that is off:

| boot | xin_halt1 | axi_halt1 | pnd/src_err | CB5 faults | outcome |
|---|---|---|---|---|---|
| T5 | `ffee0000` | `0` | `11/11` | 6 | bad |
| T6 | `ffff0000` | `30` | `0/0` | 0 | clean |
| T7 | `ffee0000` | `0` | `0/0` | 0 | bad |
| T8 | `ffff0000` | `30` | `11/11` | 6 | clean |
| T9 | `ffff0000` | `30` | `11/11` | 6 | clean |

All boots: VIG0 SRC0_ADDR `fc800000` (splash), INTF1 autorefresh
`80000001` (enabled), tear check on, CTL0 flush/start 0.

- **The wedge already exists before msm or dispcc load.** xin0 (VIG0) and
  xin4 are not idle, and the AXI port is not idle. This predicts the bad
  boot 2/2, and the good boots are 3/3 idle. msm's BCR and SMMU attach do
  not create it; they only expose it (xin7 queues behind it later).
- The CB5 faults (SID 0x800, a pre-msm domain, splash iova) are not the
  cause. They come on good boots too; the VBIF logs them as xin0/xin4
  errors and the reads retire. T7 wedged without any of them.
- ABL leaves autorefresh on in every boot, so that alone does not
  separate good from bad. It is still the thing keeping the fetch running
  across the handover.

**Fix status:** no msm fix was written. Draining does not unstick a
wedged VBIF, and the wedge is set before msm probes. A probe-time drain
in msm would be too late.

**Next lead:** find the stage where the wedge forms and quiesce before it.
1. Take the same read-only snapshot earlier: in the stage-1 initramfs
   before kexec, and in stage 2 before arm-smmu probes (initramfs or
   early module). That tells whether ABL, stage 1, kexec or the stage-2
   SMMU takeover causes it.
2. Prevention at that point: write INTF1 `TEAR_AUTOREFRESH_CONFIG`=0, wait
   one frame, then halt xin0/xin4 with ack before the SMMU/kexec handover.
   Most likely this goes in stage 1 right before kexec.

Logs: `xinid-616-good-T3.txt`, `drain-616-bad-T4.txt`,
`rebind-616-bad-T4.txt`, `claude-consult-vbif-wedge.txt`, `pre-T5..T9.txt`.

## Round 12: where does the wedge form? (18:40-19:15 CEST, 2026-10-22)

**Tooling.**
- `dodge_vbif` is a built-in stage-1/stage-2 `early_initcall` (source in
  `kernel/diag/dodge_vbif/`). It is local to the 6.16 kernel and not in the
  flashed image.
- Snapshot format: `gdscr,xin_halt1,axi_halt1,pnd,src,autoref,line,vig0addr`.
  The `snap` param takes another snapshot.
- The chain init now writes `snap` right before kexec. It passes the stage-1
  early and pre-kexec values to stage 2 as `dodge_vbif.s1e=`/`s1k=`.
- `quiesce=1` does three things: clears INTF1 autorefresh bit31, waits 2x20 ms,
  then halts xin0|xin4 with ack and releases them.
- All of this was tested as one-shot `fastboot boot` images on slot a
  (`boot-chain-diag.img`, `boot-chain-q1.img`). Nothing was flashed.
- After that, the `act 9` pre-msm peek also dumps DSI0 `+0x00..0xbf` and the
  SMMU SID 0x800 SMR/S2CR/CB state. It is read-only.

| Boot | Time | Path | Stage-1 early | Stage-1 pre-kexec | Stage-2 early / pre-msm | Result |
|---|---|---|---|---|---|---|
| D1 | 18:48 | fastboot, diag | idle (ffff0000/30), ar on | busy ffee0000/0 | busy ffee0000/0 | **bad** (CB9 fault, -110) |
| Q1 | 18:53 | fastboot, quiesce | n/a | n/a | idle, ar off | **bad** (CB9 fault, -110) |
| Q2 | 18:55 | fastboot, quiesce | busy ffee0000/0 | idle after halt ack, ar off, line frozen c60 | idle | **bad** (CB9 fault, err=24) |
| W1 | 19:06 | warm, flashed boot_a | n/a | n/a | idle, ar on, DSI DMA_BASE d35f6000 | **bad** (CB9 fault, -110) |
| W2 | 19:09 | warm | n/a | n/a | idle (pnd/src_err 0x11, CB5 faults) | **bad** (CB9 fault, err=26) |
| W3 | 19:13 | warm | n/a | n/a | idle, same DSI values as W1 | clean (err=0, no faults) |

**Findings.**
- **The wedge does not form at one point.** In D1 xin0/xin4 went busy during
  stage 1. In Q2 they were already busy at the stage-1 `early_initcall`, so
  either ABL hands over busy or it happens in the very early kernel.
- **The VBIF busy bits are a symptom, not the cause.**
  - Q2 drained them before kexec (halt acked, AXI idle, no fetch running). It
    still went bad.
  - W1 and W2 were idle with autorefresh on before msm, and both went bad.
  - So Round 11's pre-msm predictor (5/5) is broken: it is now 5/7.
  - The pre-msm VBIF, INTF, SSPP, CTL and DSI values for the good W3 and the bad
    W1 are the same.
- **The decision happens at msm init.** Every bad boot has the same single
  CB9 fault at `0xfd965800` about 120 ms after `Initialized msm`, then DSI
  DMA -110. `0xfd965800` is the last 2 KiB burst of the 1440x3168x4 splash
  frame (`fc800000 + 0x1165800`, the frame ends at `0xfd966000`).
- **Fastboot hypothesis (Round 5: 3/3 clean) is not supported.** This round's
  fastboot one-shots were 3/3 bad. That gives 3/6 overall, so one-shots do
  reproduce the drop. They are a fine test path for stage-1/chain changes.
- `DSI PLL(0) lock failed` in `mdss_probe` happens on good boots too (W3: 4).
  It is noise.

**Fix status:** the stage-1 prevention (autorefresh off, wait a frame, halt
xin0/xin4 with ack) failed 2/2 (Q1, Q2). That makes two failed attempts
with the Round 11 drain. Nothing was flashed: boot_a is unchanged and the
fallback `boot_a-dump-1022.img` is ready.

**Claude consult 3** (`logs/claude-consult-stage1-quiesce.txt`). We checked its
suggestions against the data:
- **Theory: stale ABL DSI cmd DMA reads `0xfd965800`.** Not supported. Pre-msm
  `DMA_BASE` is ABL's `d35fxxxx` buffer (it changes per boot), and msm's
  `DMA_CMD_OFFSET` is `0x1000`.
- **Theory: CB9 stalls on the fault.** Refuted. CB9 `SCTLR` is `0x67`
  (CFCFG=0, so terminate), and FSR is `0x402` -> `0x400`, with SS clear.
- **Fix 2 (map the splash 1:1 in msm's domain).** Already tried in 7.3
  (`ef1155422`, Round 3). The fault went away but the failure did not.

**Next lead.** The stray final-burst read and the -110 both start at msm's
first DPU commit or kickoff, not before.
1. Trace inside msm with the DIAG msm.ko. Snapshot VBIF xin and STATUS0
   right after `dpu_kms_hw_init`, after the first CTL flush, and before the
   first DSI DMA. That finds the exact register write that starts it.
2. Candidate: msm's first commit re-enables SSPP VIG0 (still `fc800000`) or
   restarts INTF1 autorefresh before its own plane setup.
   - Test: have msm clear VIG0 `SRC0_ADDR` and `SSPP_FETCH_CONFIG`, and
     disable the autorefresh in `dpu_kms_hw_init` before the first flush.
     This is a msm.ko swap, so warm reboots can test it.

Logs: `s1-D1.txt`, `s1-Q1.txt`, `s1-Q2*.txt`, `s1-W1..W3*.txt`,
`claude-consult-stage1-quiesce.txt`.

## Round 13: msm first-commit trace, splash stop, 1:1 splash map (19:16-20:40 CEST, 2026-10-22)

All tests used msm.ko swaps on 6.16 (`6.16.0-gbd9587d65`) with gated warm reboots. Nothing was flashed. The tools are in `kernel/diag/msm-trace/`. The local kernel commits are `27f1383b0` (dodge_vbif) and `12312b75a` (trace, stop, map), both in `wt-dodge` and not pushed.

| Boot | Time (CEST) | msm.ko | Prereset INTF1 line | CB9 fault | tx failed | Result |
|---|---|---|---|---|---|---|
| M1 | 19:19 | wrong older build | - | 0 | 0 | clean, no data |
| M2 | 19:22 | trace (unguarded) | - | - | - | **boot loop** (MMIO with MDP clocks off after the BCR). Rescued 19:35 from the stage-2 initramfs |
| R1 | 19:36 | fallback 2c86 | - | 0 | 0 | clean |
| M3 | 19:38 | trace2 (guarded) | 0 | 0 | 0 | good |
| M4 | 19:41 | trace3 | c60 | 1 (0xfd965800) | 21 | bad |
| F1 | 19:46 | stop1 (attempt 1) | c60 | 1 (0xfd965800) | 2 | bad. Left running, it **froze** (~19:53-20:07, SSH banner timeouts, ping 65 % loss, USB stayed up) and rebooted by itself at about 20:07 |
| -  | 20:07 | fallback 2c86 | - | 0 | 0 | clean, the self-recovered boot |
| F2 | 20:10 | stop2id (attempt 2) | be4 | 0 | 0 | good. Screen off/on 3/3 and idle-off wake OK |
| F3 | 20:17 | stop2id | c60 | 1 (**0xfd966400**, PLVL3) | 23 | bad |
| R2 | 20:20 | fallback 2c86 | - | 1 | 6 | bad (recovery boot) |
| G1 | 20:25 | stop3id (attempt 3) | 5d8 | 0 | 0 | good. Screen off/on 3/3 and idle-off wake OK |
| G2 | 20:31 | stop3id | c60 | **0** | 2 | bad: -110 **without** any fault |
| R3 | 20:33 | fallback 2c86 | - | 0 | 0 | clean. The phone was left here |

F1, R2 and R3 had gate BATT_FAIL at 100 % (mean +85/+124/+133 mA, charging) and passed under the full-battery rule. Every other gate was BATT_OK.

Findings:

1. **The BCR resets the splash.** At prereset the splash is live (VIG0 0xfc800000, CTL0 fetch 0x30000, INTF1 autorefresh 0x80000001). By `dpu-hwinit`, VIG0, autorefresh and fetch are all 0. The domain attach (`attach-pre`/`post`) is clean, with no fault.
2. **The fault fires on the first DSI cmd DMA trigger.** That is before any CTL flush (VIG0 then holds msm's 0x2000). DMA #1 and #2 complete and #3 times out (-110, STATUS0 0x20003, VBIF xh1 ffff0000 -> ff7f0000, LANE_STATUS 1f1f, DLN0_PHY_ERR 0x88888).
3. **Attempt 1 failed (F1).** Before the BCR it turned off autorefresh and TE, waited for wr_ptr, cleared VIG0 src and CTL0 fetch/layer, flushed, and halted VBIF xin0/xin4. Every ack was immediate, and the fault and -110 stayed.
4. **Attempt 2 failed (F3).** It added a 1:1 read-only map of the frame (0xfc800000+0x1166000) after `msm_iommu_disp_new`, with GEM iovas kept below 0xfc800000. The fault moved to just past the mapped end (0xfd966400, PLVL3). So the reader is sequential and its reads are newly translated in msm's domain.
5. **Claude consult** (`logs/claude-consult-r13.txt`): the reader is a line fetch running less than one line past the frame end, and the terminate-mode error wedges the shared MDSS AXI port. It recommended mapping the whole 0x2b00000 reserved region. It also suggested DT `iommu-addresses` plus mapping the resv regions in msm, an AXI-port halt, and waiting until the line count is off c60.
6. **Attempt 3 partly worked (G2).** It mapped the whole region (0xfc800000+0x2b00000). The **CB9 fault is gone, but the -110 still happens.** The fault is a symptom, not the trigger.
7. **The trigger predictor is the ABL scanout phase at the moment msm takes over.**
   - Prereset INTF1 tear line count 0xc60 (= 3168, the frame finished, DSI STATUS0 0, VBIF xin acks ffff0000 with err latch 0x11 on most) was bad 5/5: M4, F1, F3, G2, plus R2 untraced.
   - Mid-frame or 0 (DSI STATUS0 5, xh1 ffee0000) was good 4/4: M3 0, F2 be4, G1 5d8.
   - Stopping the pipe at that point does not help. The bad state looks like it is already latched in the DSI/PHY/panel link at the end of ABL's last frame: the PHY contention errors 0x88888 point to the panel holding the lanes. It is not an MDP fetch problem.
8. `DSI PLL(0) lock failed` plus a "dsiclk already disabled" WARN shows up 4x on **every** boot, good and bad, so it does not predict anything.

Fix status: **no fix.** Nothing was installed, and the phone's persistent msm.ko is still the fallback 2c86. Keep the splash map (it removes the fault). Next leads:

- After autorefresh off, wait until DSI is idle across a full TE period.
- Reset the panel and DSI (panel reset GPIO plus DSI soft reset and PHY reset) before the first DCS command when the prereset line count is c60.
- Read DSI ERR_INT/ACK_ERR and the PHY error registers at prereset.

Never leave a bad boot running: F1 froze after about 6 minutes.

## Round 14: c60 predictor, DSI state at handover, variants B/C, clock dump (20:37-21:55 CEST, 2026-10-22)

The tools are in `kernel/diag/msm-trace/` (sample.sh does N one-shot boots and prints a summary for each). Patches: 0002 DSI error regs, 0003 variant B, 0004 variant C, 0005 E1 dump. wt-dodge local commits: 16266afba, bdc26a91b, 4c5ec2a77, aac42f150.

| Boot | CEST | Module | Takeover ln | Result |
|---|---|---|---|---|
| D1 | 20:38 | diag4 | 8cf | good |
| D2 | 20:40 | diag4 | c60 | bad, tx 2 |
| D3 | 20:42 | diag4 | 69e | good |
| D4 | 20:45 | 2c86 (one-shot not taken) | - | bad, cb9 1 |
| R4 | 20:47 | 2c86 | - | bad |
| R5 | 20:49 | 2c86 | - | clean, but 6 CB5 faults inside the splash early in boot (new) |
| B1, B2 | 20:53, 20:54 | waitB | c60, c60 | good |
| B3 | 20:56 | waitB | 3cd | good |
| G3 | 20:58 | 2c86 (one-shot not taken) | - | clean at boot, no Hyprland socket, tx +3 during the dpms checks |
| G4-G8 | 21:03-21:21 | waitB | c60, 624, 40c, 6c6, 54e | good, dpms/idle checks OK |
| H1 | 21:25 | waitB | c60 | bad |
| R6 | 21:28 | 2c86 | - | clean |
| C1, C2 | 21:33, 21:34 | resetC | 15f, 0 (idle) | good |
| C3 | 21:36 | resetC | c60 | bad; the reset and the retry failed too |
| C4 | 21:38 | resetC | 63f | good |
| E1-E3 | 21:42-21:45 | clkE1 | 310, 6ac, a42 | good |
| E4 | 21:47 | clkE1 | c60 | bad, tx 19 |
| R7 | ~21:49 | 2c86 | - | bad, tx 26, cb9 1 |
| R8 | ~21:53 | 2c86 | - | aborted (host offline); the phone froze overnight |

The full-battery rule was used on D2, D3, G6 and C4.

Findings:
- At handover, DSI ACK_ERR and TIMEOUT_STATUS are 0. DLN0_PHY_ERR 0x88888 and LANE_STATUS 0x1f1f show up on every boot, good or bad. The only difference is CLK_STATUS: 0x2343 when the splash is idle, 0x8037c3 mid-frame. At c60 the autorefresh is stalled: it reads 0x80000001, but no frame comes within 50 ms.
- B (wait for the next frame) and C (DSI sw reset before the first command, plus a reset-and-retry on -110) both fail. The stuck state survives a DSI controller reset.
- E1: at the first command, bad and good boots match on the link clock branches/RCGs, PLL status 0x51, rates, DSI CTRL, and INTF1/CTL0 (all reset by the BCR). At the -110 the clocks are running (CLK_STATUS 0x8037c3) and the DMA stays busy (STATUS0 0x20003). So the clock tree and a stale DPU stream are ruled out. What is left: the DSI PHY lanes/analog state, the panel controller, or the DMA fetch path.
- c60 is not fully predictive: under B, 4 of 5 idle takeovers were good.
- 2026-10-23 07:35-07:41: the forced restart from frozen (warm) and a warm reboot were bad, and a cable-out cold start was clean.
- Next: a rail cycle of the panel on -110 or c60 (consult #3).

## Round 15: panel rail cycle on the first -110 (07:47-07:58 CEST, 2026-10-23)

Consult r14 #3. The panel driver (wt-dodge 702655734, `diag/panel-rail/0001`) cycles the rails once on a failed first init: reset asserted, vci/vdd/vddio off for 200 ms, on again, reset pulse, re-init. It runs on top of the 2c86 msm, as a one-boot panel module (`92-dodge-panel-oneshot.conf`, `rbp.sh`).

| boot | time | INTF1 line count | result |
|---|---|---|---|
| R1 | 07:49 | 5f7 | clean |
| R2 | 07:52 | c60 | -110. The rail cycle ran (all three rails disabled), the re-init was -110 again, 23 tx failed |
| R2b (2c86) | 07:55 | c60 | bad |
| R2c (2c86) | 07:58 | 8e6 | bad, so the phone was powered off (warm-bad loop) |

Result: not a fix. The stuck cmd DMA (STATUS0 0x20003) survives a full panel power cycle and reset, as it survived the DSI controller sw reset in variant C. The panel controller is not what holds it. What is left is the host DSI PHY/lanes or the DMA fetch path. The next candidate is a DSI PHY power-down and re-init (PHY reset plus PLL relock) on the -110. A mid-frame takeover (8e6) can fail too, so c60 is not needed for a failure.

## Round 16: DSI link/PHY power-down and re-init on the first -110 (08:04-08:14 CEST, 2026-10-23)

This is the second failed fix in this line, after Round 15, so it was followed by a Claude consult. The diag (wt-dodge 5c256bad3, `msm-trace/0006`) runs once on the first -110. It takes the link down the way post_disable does: host disable, PLL state save, host power off, PHY disable. It waits 20 ms. It brings the link back the way pre_enable does: DSI PHY_RESET, PHY enable with PLL restore, host power on (PLL relock), host enable. Then it retries the command once.

| boot | time | result |
|---|---|---|
| P1 (phyR1) | 08:07 | -110. Relink ok; before the retry STATUS0 0x00020000, CLK_STATUS 0x2343, PLL 0x51, clock tree unchanged. Retry -110 (0x20003) |
| P1b (2c86) | 08:11 | bad, so the phone was powered off |

STATUS0 bit 17 survives a controller sw reset, the link clocks off, the host and PHY vregs off, and a PHY reset. Only the MDSS BCR clears it, and the first DMA after the BCR hangs again. LANE_STATUS 0x1f1f shows the engine never drove the lanes. That points at the cmd DMA fetch (AXI read through VBIF/NoC/SMMU) rather than the PHY or the panel. Consult (logs/claude-consult-r16.txt): next, send the command through the DSI TPG DMA FIFO (no memory fetch) to split fetch from link. Then VBIF halt registers at the BCR and at the -110, the interconnect vote, and a clean teardown before warm reboot.

## Round 17: TPG DMA FIFO resend on the first -110 (08:24-08:36 CEST, 2026-10-23)

This is consult step 1. The diag (wt-dodge f3e2991dd, `msm-trace/0007`) runs on the first -110. It does a DSI sw reset, then sends the same command through the DSI test-pattern DMA FIFO. The command words are written into the controller (TEST_PATTERN_GEN_CMD_DMA_INIT_VAL), so there is no AXI memory read. After a success, later commands of 64 bytes or less use the FIFO too. VBIF XIN/AXI halt registers are dumped at the MDSS BCR, at the first command and at the -110.

| boot | time | result |
|---|---|---|
| T1 (tpgR1) | 08:27 | c60, bad. DMA -110. The FIFO resend was DONE, and 10 more FIFO init commands were DONE. The 104-byte PPS (memory DMA) was -110 and the panel init failed |
| T1b (2c86) | 08:32 | bad |
| T1c (2c86) | 08:35 | clean |

On a bad boot the DSI controller, PHY and lanes deliver commands when the payload comes from the FIFO. Only the memory-fetched DMA hangs. STATUS0 bit 17 stays set while the FIFO commands succeed, so it marks the stuck fetch, not a dead engine. At the -110, VBIF XIN_HALT_CTRL1 goes ffff0000 -> ff7f0000 and AXI_HALT_CTRL1 0x30 -> 0x20. That still needs a good-boot comparison. Next: test whether the FIFO accepts the 104-byte PPS (if so, all panel init can bypass the fetch). In parallel, chase the fetch: the dma_base/iova and SMMU mapping, the interconnect vote, and a VBIF/AXI halt+release before the first DMA.

Also: with USB attached, `systemctl poweroff` is a warm restart. The 08:14 self-power-on (boot 58a45297) came up clean.

## Round 18: FIFO depth, good-boot comparison, the DMA #3 count (08:38-09:07 CEST, 2026-10-23)

Diags: r18 (wt-dodge 908cb920c, `msm-trace/0008`) and r18b (9ef8fa8b8, `msm-trace/0009`). Both are read-only apart from the TPG FIFO, which is reset after the probe. No voltages changed, nothing flashed, one-boot msm only.

| boot | variant | result |
|---|---|---|
| R18a | r18 | good. VBIF idle at first-cmd/first-trig/first-done; dma_base 0x1000, iova2phys MATCH |
| R18b | r18 | good, same |
| R18c | r18 | bad. DMA #1, #2 DONE; DMA #3 -110 (xh1 ff7f0000, axi1 0x20, iova2phys MATCH, no fault) |
| R18c-fb, -fb2 | 2c86 | bad, then good |
| S1 | r18b | good (3 identical DMAs, then the rest) |
| S2 | r18b | bad. cmd #1, repeat 1 ok, repeat 2 (DMA #3) -110 |
| S2-fb | 2c86 | good |

**FIFO depth.** With TPG FIFO mode on and no trigger, TPG_DMA_FIFO_STATUS reads 1 after 4 words and goes up by 1 every 2 words to 8 at 18 words. After that it does not change. That is about 8-9 64-bit entries (64-72 B), in line with the downstream `DSI_CTRL_MAX_CMD_FIFO_STORE_SIZE` of 64. The panel's 0x81 write (a 101-byte DSC PPS copy, 104 B packed) and the 128-byte PPS do not fit. A MIPI DSI long packet is one atomic transfer and DCS has no write-continue, so they cannot be split legally. The whole init cannot go through the FIFO, so a bad boot cannot be brought up that way.

**The failure is the 3rd fetch.** Every traced bad boot (13 in logs/) completes DMA #1 and #2 and hangs on DMA #3. The count-shift diag resent cmd #1 twice from the same buffer, and the hang landed on repeat 2, which is DMA #3. So it does not depend on the command content, the iova/phys mapping (still valid at the -110, no SMMU fault) or the ICC vote (keepalive INT_MAX on both good and bad). It looks like a fixed number of read transactions succeed and the next one never gets a response.

**Consult r18** (logs/claude-consult-r18.txt) ranks the causes:
1. Leaked outstanding-transaction credits in the display TBU/QTB or MMNOC port. The MDSS BCR does not reset them, but warm reset leaves them in place.
2. A table walk wedged after a TLBI between #2 and #3. Less likely, because the count follows the fetch, not the time.
3. LLCC/memtype state left from the previous boot.

The next steps are the QTB OT-snapshot/fence registers on a good boot and a bad boot, a clean teardown (VBIF halt with ack / msm unbind) in the outgoing kernel before a warm reboot, and an SSPP fetch before the first DSI DMA (shared pool vs per-xin).

## Round 19: FIFO for every short command, memory DMA only for the two big ones (09:09-09:31 CEST, 2026-10-23)

Variant r19 (wt-dodge b64688f01 on top of the revert of r18b, `msm-trace/0010`; msm.ko 3117af136838). From the first DSI command, on `of_machine_is_compatible("OnePlus,13")` only, every command of 64 B or less goes through the TPG DMA FIFO. Larger ones use memory DMA and are logged (`dodge-r19: mem-dma #n`). The r17 -110 handler and the r18 dumps stay; the first-done FIFO probe was dropped. One-boot msm only, nothing flashed, no voltage change.

Commands over 64 B, from the panel driver: only the 0x81 write in on() (100-byte payload, 104 B packet) and the PPS in prepare() (132 B packet). Everything else in on()/off() is at most 29 B. Runtime: brightness 0x51 (8 B, HS) and the brightness read are short. But prepare() (on() + PPS) runs again on every modeset and every screen wake, so a boot does 2 memory DMAs per panel power-up: 4 by the time Hyprland is up, 12 after the dp.sh cycles.

| boot | prereset ln | result |
|---|---|---|
| R19-1 | 721 | good. 12 FIFO cmds DONE, mem-dma #1-#4 OK. Brightness OK (400 is clamped to 1000 by userspace, 2000 and 1000 apply). dp.sh: 3 screen off/on OK, idle-off at 165 s then wake OK, 0 tx failures, mem-dma #12 at 285 s |
| R19-2 | 0 | good, mem-dma #1-#4 OK |
| R19-3 | c60 | bad. All FIFO cmds DONE, mem-dma #1 (0x81, 104 B) DONE, mem-dma #2 (PPS, 132 B) -110 (xh1 ffff0000 -> ff7f0000, axi1 0x30 -> 0x20, as before). The FIFO resend after sw reset fails -7 (too long). "failed to transmit PPS". Then 167 frame-done and 181 pp:0 kickoff timeouts, plus "ctl 1 reset failure". Hyprland's re-init (mem-dma #3) -110, panel init -110, brightness through the FIFO TIMEOUT (DSI still wedged, STATUS0 0x20003). dpms Off. Still on SSH at 516 s (no freeze yet); rebooted |
| R19-3-fb | - | fallback 2c86, good |

Findings:
- The bad-boot budget is not 2 DSI commands. Earlier bad boots completed two short DMAs (8 B and 4 B) and hung on the third. Here a 104 B DMA completed and the 132 B one hung. That fits a fixed count of AXI read bursts. With 128-byte bursts, 0x81 needs one burst and the PPS two (128 + 4), so the hang lands on the 3rd burst again. A small byte budget also fits. Either way, the two big commands cannot both get through on a bad boot.
- Even a working init would not survive. Each wake does prepare() again, which costs two more memory DMAs.
- Shared vs per-client credit pool: not answered. The frame-done/pingpong timeouts come after the DSI engine is wedged (STATUS0 0x20003) with the PPS missing, so they do not show whether the SSPP fetch itself would hang. Answering it needs an SSPP fetch before the first DSI memory DMA, or a bad boot where the DSI does not wedge.
- Next: the TBU/QTB outstanding-transaction (OT) snapshot and fence registers, good vs bad (offsets still to be verified), and a clean teardown in the outgoing kernel before a warm reboot.


## Round 20: display QTB500 read-only state, and controls (09:40-11:40 CEST, 2026-10-23)

Variants (msm-trace `0011`-`0015`, all on top of the r18 state, one-shot msm.ko per boot): r20 reads mdp_hf_qtb (0x17d0000) and sf_qtb (0x17d1000) SWID_LOW / FENCEREQ 0x410 / FENCEACK 0x418 / OT_SNAPSHOT 0xc10, 0xc20 at every VBIF dump point; r20b skips the mdss-* points; r20d does one hf SWID_LOW read at first-cmd only; r20c maps the QTBs and never reads; r20e is a timing control (dsb + udelay(5) + pr_info where r20d reads, no QTB access). r20c and r20e were run interleaved (`loop20x.sh`) to avoid drift between rounds.

QTB values on every boot that read them: hf SWID_LOW 0035aefc, FENCEREQ/FENCEACK 0, OT snapshots 0 on both QTBs and both ports. All of those boots were good, so there is no good-vs-bad OT comparison. Without a fence the OT snapshot may not be a live view, so the zeros are not evidence of "no leaked credits".

Outcome on c60 boots (stalled splash at takeover, the bad-boot predictor):

| arm | c60 boots | good | bad |
|---|---|---|---|
| any QTB read before the first DSI DMA (r20 R20-3, R20-12; r20b R20b-7; r20d R20d-1, R20d-3) | 5 | 5 | 0 |
| no QTB read (r20c R20c-0, R20c-2; r20e R20e-8; R18c, R19-3, R18b) | 6 | 1 | 5 |

Across about 39 QTB-read boots there was no bad boot (baseline warm-bad rate about 30%). Non-c60 boots are good in every arm. Fisher exact on the c60 table: one-sided p about 0.013. The r20e c60 boot (R20e-8) was bad with 35 tx failures, so a 5 us delay plus a printk at the same point does not cure. That points to the QTB read itself, not timing. Not yet shown: the read arms and the no-read arms were not all interleaved (r20/r20b/r20d ran before r20c/r20e), so drift is not fully excluded.

Bad detection in `rbt.sh`: R20-16 and R20b-6 were first flagged bad on 1-2 "frame done timeout" lines with 0 tx failures. That is a known transient. BAD now needs tx failed / failed to initialize panel / kickoff timeout / 5 or more frame-done timeouts / dpms not On. Both boots are good under that rule.

Downstream (sm8750 arm-smmu-qcom.c qtb500): halt (FENCEREQ) / poll / resume are used only for ATOS/ECATS and testbus debug; write_sync is a readl of SWID_LOW; there is no credit clear or invalidate, and nothing runs at display handoff or reboot. A fence on a QTB with leaked OT would never ack, so a halt is not a candidate fix. The stock DT QTB nodes have no clocks and no power-domains, only `interconnects` mmss_noc -> mc_virt (hf: mmss_noc 0x15, sf: 0x20), which the display already votes (votes identical good/bad).

Next: r21a (`0016`, one sf_qtb SWID_LOW read only), to test whether the cure is specific to hf. Then VIG1 at takeover (fresh consult, `fresh-consult-facts.md`): ABL scans out with VIG0 and VIG1 (CTL0 fetch 0x30000), and stop-splash only clears VIG0.

## Round 21 (2026-10-23, 11:40-12:31 CEST): interleave, VIG1, kick-on-hang

Arms, interleaved per round (logs/loop21b.txt): r21s (VIG dump + stop-splash also clears VIG1 SRC0 and flushes it), r21k (VIG dump; one hf QTB read + 10 ms wait + resend only after a first -110), r21v (VIG dump only, no QTB access), r21a (one sf QTB read), r20d (one hf QTB read).

- 0 bad boots in 20. The kick never fired because r21k never saw a -110, so kick-on-hang is still untested.
- VIG1 is a live splash pipe at takeover. ABL scans the left half with VIG0 and the right half with VIG1 (VIG1 src0 fc800000, x=720, 720x3168, stride 0x1680; CTL0 fetch-active 0x30000). Our stop-splash leaves VIG1 SRC0 pointing at fc800000. The earlier CB9 fault iova 0xfd965800 falls in the right half of the last line, so it was a VIG1 fetch, made after the splash buffer was unmapped.
- c60 boots, all of 2026-10-23 (gate = mean battery current in the boot before):

| arm | c60 boots | bad |
|---|---|---|
| no QTB read (P1, T1, R18b, R18c, S2, R19-3, R20c-0, R20c-2, R20e-8) | 9 | 8 |
| no QTB read, VIG-dump builds (R21s-4, R21k-4) | 2 | 0 |
| one QTB read, hf or sf (R20, R20b, R20d, R21d, R21a2) | 10 | 0 |

  No bad boot at all after 11:37. The two good no-read c60 boots are both r21v-based, and that build reads SSPP registers at stop-splash entry, so a plain MMIO read-back is a confounder. Loop22 has a pure no-read arm (r20c) next to r21k.
- Lead, not yet tested: 4 of 5 c60 boots that followed a positive (charging) gate current were bad, against 4 of 16 after a negative one. Charging state, or something that tracks it, could be a covariate.

Candidate fix (kernel/candidate/0001-*.patch, wt-dodge 2c93e5f48): msm_mdss reads mdp_hf_qtb SWID_LOW (0x017d0000) on every MDSS enable. This copies the downstream qtb500 "write_sync" read. The proper upstream layer would be a qcom,sm8750-tbu node plus arm-smmu-qcom TBU handling. It sits in msm_mdss for now because ARM_SMMU is built in, while msm is a module and can be one-shot tested.

## Round 22 (2026-10-23, 12:31-13:42 CEST): fix1 vs no-read interleave, r22n

| arm | read before first fetch | c60 boots good/bad | non-c60 good/bad |
|---|---|---|---|
| fix1 (F2, F2b) | hf QTB SWID_LOW | 4/0 (F2b-3 ran right after a bad boot) | 6/0 |
| r20c (R22c) | none | 1/1 (R22c-3 bad, txfail 32) | 3/0 |
| r21k (R22k, loop22 + loop22b) | none | 0/1 (loop22 R22k-1 bad, kick fired, no recovery) | 5/0 |
| r22n (N23) | mmss_noc base 0x1780000 | invalid: synchronous external abort in mdss_runtime_resume | - |

- Bad boots cluster: after R22k-1 the next three fallback boots were bad too; the arm right after a bad boot is biased toward bad.
- fix1 is 4/4 on c60, controls 2 bad of 3 on c60 since 12:30. Round 21 had no-read 2/2 good on c60, so the evidence for fix1 is suggestive, not conclusive (target ~8 c60 per arm).
- r22n does not answer the "clock/power wake vs QTB" question: the mmss_noc base is not CPU-readable from the AP (abort). The host reboot after that oops hung in shutdown and the phone needed a forced restart.

## Round 25/26 (2026-10-23, 14:02-14:31 CEST): fix1 vs control vs icc vote vs VBIF read

After a cable-out cold start at ~13:56. All arms are one-shot msm.ko on the same fix1 tree; r25v and r25b replace the QTB read at the same call site (msm_mdss_enable, after the clocks).

| arm | change at MDSS enable | c60 good/bad | non-c60 good/bad |
|---|---|---|---|
| fix1 (F5, F6) | hf QTB SWID_LOW read | 2/0 (6/0 cumulative since 12:52) | 2/0 |
| r21k (R25k, R26k) | none (control) | 0/0 | 3/0 (+1 invalid, no one-shot) |
| r25v (V26) | icc_set_bw mdp0-mem avg 400 MB/s, peak 1.6 GB/s | 0/0 | 2/0 (V26-2 right after a bad boot) |
| r25b (B26) | guarded VBIF RT read (dodge_vbif_dump) | 0/1 (B26-1 bad) | 1/0 |

- The VBIF read ran on the bad B26-1 boot and did not prevent the hang. One point, but it argues that the cure is specific to the QTB/TBU path, not "any MDSS register read".
- The vote arm has not met a c60 boot yet, so it says nothing about a clock/power wake.
- Patches: kernel/diag/msm-trace/0020 (r25v), 0021 (r25b).

## Round 27: r25v / fix1 / r21k interleave (2026-10-23 14:35-15:01 CEST)

- Round 27 (14:35-15:01 CEST, loop27 "r25v fix1 r21k", 15 boots): V27-1 c60 BAD (vote logged "extra mdp-mem vote on 1 paths", still -110, txfail 30), all others good; F7-3/F7-4 c60 good, R27k-3 c60 good.
- After the loop, the fallback (2c86) boot at 15:01 was BAD (-110); ended at about 100 s; the next fallback boot at 15:04 is clean.
- Cumulative since 12:30:

| arm | c60 good/bad | non-c60 good/bad | notes |
|---|---|---|---|
| fix1 (QTB SWID_LOW read) | 8/0 | 11/0 | c60: F2-1, F2-3 (post-bad), F2b-3, F2b-4, F6-1, F6-2, F7-3, F7-4 |
| r21k (no read) | 1/1 | 12/0 | R22k-1 bad (kick no recover); R27k-3 c60 good |
| r20c (no read) | 1/1 | 3/0 | R22c-3 bad |
| r25v (mdp0-mem icc vote, fired) | 0/1 | 6/0 | V27-1 bad (txfail 30, not post-bad); V26-2, V27-2 post-bad |
| r25b (guarded VBIF read) | 0/1 | 1/0 | B26-1 bad (txfail 34) |
| r22n (mmss_noc read) | invalid | invalid | sync external abort, never rerun |

- Conclusion: the icc vote does NOT cure (c60 bad with the vote in place), and neither does a VBIF read; only the QTB read does. fix1 reached 8 c60 / 0 bad. Controls are 2 bad of 4 c60 (small n).
- Recommendation: keep fix1 (msm_mdss_enable -> msm_mdss_qtb_sync, a QTB500 TBU SWID_LOW read after clk enable): an SMMU/TBU wake, not bandwidth.
- Phone: fallback (msm 2c86 + panel v2), nothing staged, no loop. Next: more c60 controls to firm up the bad rate.

## Round 28: clean fix (0054) installed persistently, soak (2026-10-23 15:10-15:36 CEST)

- Clean fix module: wt-dodge branch dodge-qtbfix = bd9587d65 (flashed base: product series 0001-0050 incl. the 0050 GDSC workaround) + 12048bd2c (QTB read only). No DIAG; 0052 lanediag dropped (it is DIAG and the persistent 2c86 module was the 0052 build). Exported as kernel/patches/0054. msm.ko a153ae874f75 (stripped, md5 a93bc1a3), copy in ~/android/mainline/msm-variants/qtbfix/. Panel module unchanged (v2, 0053).
- QTB address: hard-coded 0x017d0000 as sm8750 match data (devm_ioremap). Mainline sm8750.dtsi has no TBU nodes, so there is nothing to take from DT yet; upstream form is a TBU phandle or an arm-smmu-qcom hook.
- Install: /usr/local/lib/omamobile.6.16.0-gbd9587d65/display/msm.ko (seen as /usr/local/lib/omamobile/display/ via a bind mount); previous 2c86 kept there as msm.ko.pre-qtbfix.
- Rollback: on the phone `cd /usr/local/lib/omamobile/display && cp msm.ko.pre-qtbfix msm.ko && sync`, then a gated reboot (`tools/dodge-battcheck && tools/phone-ssh 'systemctl reboot'`).
- Drop-ins: 91/92 one-shot moved to /root/dropins-disabled/ (inert without a staged file; move back to re-enable one-shots). 90-premsm kept (read-only dodge_peek act=9, no QTB access, gives the premsm INTF1 line count). 93-deadline kept.
- Soak (Round 28, 15:10-15:32 CEST, warm reboots, battery gate, 240 s deadline armed): 15 of 15 good, 0 tx failed. Q1 was a one-shot of the same module, Q28-1..14 the persistent install. premsm INTF1 line_count c60 on Q28-9 and Q28-13 (both good); other boots 0, 282, b20, ac, 586, bc. Note: premsm ln is read before msm loads, earlier than the old takeover "pre:ln" from the msm trace, so the two counts are not strictly the same measure.
- Function check on Q28-14: 3 screen off/on cycles OK, idle-off at 165 s then wake OK, brightness 2000/1000 set and read back exactly, 0 tx failures over 248 s.
- Gate slip (15:03): a reboot ran after BATT_FAIL because it was chained with ;. Always chain with &&.
- idcheck reports "serial" hits on the module path: the USB gadget serial is the string "omamobile" (the distro name), not a device identifier; pushed with that noted.
- Phone: persistent qtbfix msm.ko + panel v2, nothing staged, no loop running. Next: longer soak and a few cold starts; then try dropping the GDSC workaround with the QTB read in place.
