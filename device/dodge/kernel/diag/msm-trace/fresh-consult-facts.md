FACT SHEET: intermittent DSI command-mode DMA hang after warm reset
Qualcomm SM8750 phone (OnePlus 13), mainline Linux 6.16 msm DRM (DPU + DSI 6G)
Observations only. Times are local. Raw register values as read.

1. SETUP
- SoC SM8750. Panel: 1440x3168 command-mode DSI panel with DSC (aa569 driver), one DSI (DSI0 @0xae94000), INTF1, CTL0/CTL1, SSPP VIG0. TE used.
- Linux runs as a guest under the Gunyah hypervisor (Gunyah watchdog present).
- Boot chain (every boot, flashed or one-shot): XBL -> ABL (shows a continuous splash, then starts a "stage 1" Linux kernel with the stock vendor DTB) -> stage 1 initramfs does kexec_load + kexec -e -> "stage 2" mainline 6.16 kernel with a mainline DT. The fastboot one-shot path ("fastboot boot") uses the same chain image.
- ABL splash: reserved region 0xfc800000 size 0x2b00000. Frame 1440x3168x4 B starting at 0xfc800000, ends at 0xfd966000. At stage-2 handover: SSPP VIG0 SRC0_ADDR 0xfc800000 (op 0x80000000, fetch 0x87), CTL0 fetch-pipe-active 0x30000, INTF1 TEAR/AUTOREFRESH config 0x80000001 (autorefresh enabled) on every boot, tear check on, CTL0 flush/start 0.
- simpledrm/simple-framebuffer runs on the splash until msm loads (msm is a module, loaded by a systemd service ~5-7 s after kernel start).
- msm probe: msm_mdss asserts/deasserts DISP_CC_MDSS_CORE_BCR (DT "resets"). After it, VIG0/CTL/INTF/autorefresh read 0. msm then attaches its own IOMMU domain for the display SID (apps SMMU SID 0x800 -> SMR[3] -> CB9, SCTLR 0x67 = translate, fault report, terminate (CFCFG=0)). The splash is not mapped in that domain unless we add it.
- DSI on every host power-on: DSI soft reset. DSI cmd DMA config at the failure: CMD_DMA_CTRL 0x14000000 (FROM_FRAME_BUFFER, LOW_POWER), DMA_BASE iova 0x1000, TRIG_CTRL 0x80001004.
- VBIF (RT) @0xaeb0000. xin numbering measured: xin0 = SSPP VIG0, xin7 = DSI command DMA (halting xin7 on a good boot reproduces the exact failure signature; halting xin0 does not block the DSI DMA). xin4: unidentified.
- Display-path QTB500 instances in the stock DT (apps-smmu): mdp_hf_qtb @0x17d0000, sf_qtb @0x17d1000 (inside the mmss_noc register range). Mainline does not touch them.
- Interconnect: mdp0-mem (MASTER_MDP -> EBI1), cpu-cfg. icc sync_state never completes globally, so every display node aggregate stays at INT_MAX (keepalive) on good and bad boots. Votes identical good/bad (mdss peak 400000, dpu peak 800000, cpu-cfg 57000). mmss_noc state_synced at 8.1-8.4 s both. No icc QoS programming on sm8750 in mainline.
- Supplies: DSI vdds 880 mV, vdda 1.2 V, identical good/bad. Panel rails vddio L12B 1.8 V, vci L13B 3.0 V, vdd L11B 1.0 V (only consumer is the panel). DSI clocks good and bad: byte 182159985, pix 194303984, esc 19200000 Hz; DSI PLL COMMON_STATUS_ONE 0x51 (locked). "DSI PLL(0) lock failed" (x2-4) plus a "dsiclk already disabled" WARN appear on every boot, good and bad.
- The same failure also happens on a 7.3-rc6 kernel (5 of 7 boots, all via fastboot one-shot).

2. FAILURE SIGNATURE (bad boot)
- At msm init the panel driver sends DCS commands with DSI command-mode memory DMA. DMA #1 and #2 complete; the 3rd memory DMA never completes: "cmd dma tx failed -110", then "Failed to initialize panel", kickoff/frame-done/pingpong timeouts, vblank WARNs, "ctl 1 reset failure". Screen stays black. First -110 typically at 6.9-7.6 s after kernel start.
- At the -110: DSI STATUS0 0x00020003, CLK_STATUS 0x008037c3 (good idle: 0x2343), LANE_STATUS 0x1f1f (all lanes + clock lane in stop state; never driven), LANE_CTRL 0x01000000, DLN0_PHY_ERR 0x00088888 (same value on good boots, sticky from ABL), ACK_ERR 0, TIMEOUT_STATUS 0. No DSI error IRQ.
- After DSI soft reset: STATUS0 0x00020000 (bit 17 stays set), CTRL 0x1f5, CLK_STATUS 0x2343. Bit 17 also survives: link clocks off + host/PHY vregs off + PHY_RESET + PLL relock (full post_disable/pre_enable), and a panel rail power-cycle (200 ms off) + panel reset. Only the MDSS BCR clears it, and the first memory DMA after BCR hangs again.
- VBIF at the -110: XIN_HALT_CTRL1 ffff0000 -> ff7f0000 (xin7 ack bit drops), AXI_HALT_CTRL1 0x30 -> 0x20. On good boots at the same points (first-cmd, 50 us after trigger, first-done): ffff0000 / 0x30. VBIF error registers 0.
- Requesting a VBIF halt of xin0/xin7 (and AXI halt) on a bad boot: xin0 and xin7 halt never ack (other xins ack), AXI halt never acks. Afterwards the DMA still hangs.
- msm unbind (MDSS GDSC goes off) + rebind (BCR again): VBIF still reads not-idle (ff7e0000), DMA hangs again.
- SMMU at the hang: CB9 FSR 0x400 (format bits only), GFSR 0, no fault pending. iommu_iova_to_phys(DMA_BASE iova) still matches the GEM page at the -110. No new fault.
- Live writes on the stuck DSI (no effect): clear BLOCK_DMA_WITHIN_FRAME, clear TE, re-write TRIGGER_DMA.
- DSI TPG DMA-FIFO path (command words written into TEST_PATTERN_GEN_CMD_DMA_INIT_VAL, no memory fetch) on a bad boot after DSI soft reset: DMA_DONE. 10 more short LP init commands through the FIFO: DMA_DONE (STATUS0 stays 0x00020000 throughout). The next memory DMA: -110 again (0x20003).
- TPG FIFO depth measured: ~8-9 x 64-bit entries (64-72 B). Panel init needs two long packets: 0x81 write (104 B packet) and PPS (132 B packet), so not all init fits the FIFO.
- Count test: every traced bad boot (13+) completes DMA #1 and #2 and hangs on DMA #3. Sending cmd #1 (8 B) three times from the same buffer: the hang lands on the 3rd copy. With all short commands via FIFO and only the two long ones via memory DMA: DMA #1 (104 B) completes, DMA #2 (132 B) hangs. (Earlier: 8 B and 4 B complete, then the 3rd hangs.)
- SMMU fault: on most bad boots (stock code) exactly one CB9 context fault at iova 0xfd965800 (last 2 KiB burst of the splash frame), SID 0x800, ~120-200 ms after "Initialized msm", at the first DSI cmd DMA trigger, before any CTL flush. Also seen on some clean boots. With a 1:1 read-only map of the frame only, the fault moves to 0xfd966400 (just past the frame end). With the whole 0x2b00000 region mapped 1:1, no fault, but the -110 still happens. Separately, at arm-smmu probe (~0.40 s) some boots show CB5 faults (SID 0x800, inside the splash) on good and bad boots.
- INTF1 tear line count at msm takeover (just before BCR): 0xc60 (=3168, frame finished; autorefresh enabled but no new frame within 50 ms; DSI CLK_STATUS 0x2343) vs mid-frame values (CLK_STATUS 0x8037c3, STATUS0 5). With the stock code path: c60 takeovers bad 9 of 9 (Rounds 13/14). With a "wait up to 50 ms for the next frame" variant: 4 of 5 c60 takeovers good. Mid-frame takeovers can also fail (line 0x8e6, 0x9bd seen bad). Overall warm-boot bad rate ~30%; ~7 of 8 when c60.
- Pre-msm read-only snapshot (before dispcc/msm load): on some bad boots xin0+xin4 not idle (ffee0000), AXI_HALT_CTRL1 0, pnd/src_err 0x11; but other bad boots are fully idle (ffff0000/0x30) and identical to good boots. Stage 1 early_initcall already sees ffee0000 on some boots.
- Bad boots left running: at ~6 min the phone freezes (no SSH, USB gadget gone, ping loss; kernel boottime advanced only ~1 min over a 6-min wall span on one capture), then recovers or reboots itself. Some bad boots ran 516 s+ without freezing. 7.3 bad boots died at ~20-35 s (cause not captured, no ramoops).

3. BOOT-TYPE STATISTICS
- Cold start with USB cable unplugged (power off from the fastboot menu, wait 30 s, power on, replug at logo): clean every time it was confirmed (about 8-10 starts over 2 days). One disputed morning boot after an overnight freeze came up bad; it was probably a forced restart from the frozen state.
- Three-button reset (USB in): bad 1, clean 1.
- "systemctl poweroff" with USB attached (phone powers itself back on): P1 clean, P2 clean, P3 bad, P4 (after bad) bad; one more later clean.
- Warm "systemctl reboot": bad at a base rate of ~30%, runs vary (e.g. 2 bad of 8, 4 bad of 9). Bad -> warm reboot: often bad again (3 of 3 on day 1, 2 bad in a row several times), but bad -> clean also seen many times.
- fastboot one-shot boots: 3/3 clean in one round, 3/3 bad in another (3/6).
- The first warm boot right after a cold start was bad on several occasions.
- After a 7.3 boot, the next 6.16 boot was bad 4 of 5 (day 1).

4. CPU READ OF THE QTB (Round 20, today, interleaved/sequential one-shot warm boots, msm.ko swapped per boot only)
Variant | QTB accesses | boots | c60 boots | DMA hangs
r20  | readl SWID_LOW 0x0 + readq 0x410/0x418/0xc10/0xc20 on both QTBs at: before BCR (active splash), after splash stop, after BCR, before DMA #1, 50 us after trigger, after done | 18 | 2 | 0
r20b | same, but none around the BCR (from "before DMA #1" on) | 10 | 1 | 0
r20c | QTBs ioremapped, never read | 3 | 2 | 2 (both c60 boots, classic DMA #3 hang)
r20d | one readl(mdp_hf_qtb + 0x0) just before DMA #1 | 11 valid (+1 lost log) | 1 | 0
r20e | no QTB read; dsb(sy) + udelay(5) at the same point | 2 so far | 0 | 0
- 4 of those r20/r20b boots (R20-4, -6, -16, R20b-6) had 1-2 "frame done timeout" lines at ~4 s after msm load but no DSI tx failure; display came up (dpms On).
- Values read: SWID_LOW 0x0035aefc on every boot at every point; FENCEREQ, FENCEACK, OT_SNAPSHOT port0/port1 all 0 at every point, including during active splash scanout, on both QTBs.
- Baseline before today's QTB rounds (same msm base build without the QTB code): ~30% bad, c60 ~7/8 bad.

5. EVERYTHING TRIED (result)
- Identity map of splash in msm's domain (frame / whole region): fault moves / disappears, -110 stays.
- Reset ABL CTLs at DPU init: no-op (everything already idle after BCR), still bad.
- Stop splash before BCR (autorefresh+TE off, wait wr_ptr, clear VIG0 src + CTL0 fetch/layer, flush, VBIF halt xin0/xin4 with ack - acks immediate): still bad.
- Stage-1 (before kexec) quiesce: autorefresh off, wait 2x20 ms, halt xin0/xin4 with ack: still bad (2/2).
- Hyprland dpms off before warm reboot: bad. Unbind msm-mdss (GDSC off) before warm reboot: bad.
- Panel driver owns its rails, cuts them at shutdown (v2): 6/8 warm clean, not fixed; cutting them on every unprepare (v1): no fix.
- Panel rail cycle on first -110: no recovery.
- Wait up to 50 ms for the next frame when idle at c60: 8 clean in a row, then a c60 failure.
- DSI sw reset before first cmd + reset-retry on -110: no recovery.
- Full DSI link/PHY power-down, PHY reset, PLL relock, retry: no recovery.
- In-place VBIF xin0/xin7 + AXI halt drain on bad boot: halts never ack, no recovery.
- msm unbind/rebind on bad boot: no recovery.
- TPG FIFO for the failing command: works. FIFO for all <=64 B commands, memory DMA for 0x81 + PPS: PPS hangs on bad boot.
- Clock tree / RCG / PLL / link-rate dump good vs bad: identical.
- Interconnect votes good vs bad: identical (INT_MAX).
- CPU read of QTB500 registers before DMA #1: 0 hangs in 39 boots incl. 4 c60 (see 4). Mapped-not-read: 2/3 hang.

6. DOWNSTREAM REFERENCE NAMES (facts from downstream sources, no conclusions)
- OnePlus sm8750 downstream arm-smmu-qcom.c qtb500 impl: SWID_LOW at 0x0 (read by its write_sync), OVR_DBG_FENCEREQ 0x410 (bit0 halt request), OVR_DBG_FENCEACK 0x418 (bit0 ack), NS_DBG_PORT_N_OT_SNAPSHOT(n) 0xc10 + 0x10*n (64-bit "outstanding transactions bitmap"), num-qtb-ports = 2.
- Downstream dsi_ctrl_reg.h / dsi_ctrl_hw_cmn_kickoff_fifo_command(): TPG_CTRL (CMD_DMA_TPG_EN, TPG_DMA_FIFO_MODE, PATTERN_SEL), TEST_PATTERN_GEN_CMD_DMA_INIT_VAL, TPG_DMA_FIFO_STATUS, TPG_DMA_FIFO_RESET; DSI_CTRL_MAX_CMD_FIFO_STORE_SIZE 64.
- Mainline 6.16 arm-smmu-qcom has no qtb500 support; mainline DT for sm8750 apps_smmu has no QTB nodes.
