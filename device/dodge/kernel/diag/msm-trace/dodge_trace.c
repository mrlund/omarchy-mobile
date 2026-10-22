// SPDX-License-Identifier: GPL-2.0-only
/*
 * DIAG (dodge, SM8750): one-line read-only snapshot of the MDSS fetch path
 * (VBIF RT, SSPP VIG0, CTL0/1, INTF1, DSI0) at points in msm's bring-up.
 * Mappings are made once from process context, so dodge_trace() is safe
 * from the IOMMU fault handler. Reads are skipped while MDSS_GDSC is off,
 * MDP/VBIF reads while the MDSS AHB or MDP branch clock is off, and DSI
 * reads while the byte0 or esc0 clock is off (an unclocked read hangs the
 * bus: the first trace build without these guards boot-looped the phone).
 */
#include <linux/atomic.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/printk.h>
#include <linux/string.h>
#include "dodge_trace.h"

static void __iomem *dcc, *gdsc, *vbif, *vig0, *ctl0, *ctl1, *intf1, *dsi0;
static atomic_t budget = ATOMIC_INIT(120);
static atomic_t dsi_budget = ATOMIC_INIT(6);

void dodge_trace_map(void)
{
	if (gdsc)
		return;
	dcc = ioremap(0x0af08000UL, 0x100);
	gdsc = ioremap(0x0af09000UL, 4);
	vbif = ioremap(0x0aeb0000UL, 0x300);
	vig0 = ioremap(0x0ae05000UL, 0x100);
	ctl0 = ioremap(0x0ae16000UL, 0x200);
	ctl1 = ioremap(0x0ae17000UL, 0x200);
	intf1 = ioremap(0x0ae36000UL, 0x300);
	dsi0 = ioremap(0x0ae94000UL, 0x200);
}

/* dispcc CBCR bit 31 is CLK_OFF */
#define DCC_ON(off) (!(readl(dcc + (off)) & BIT(31)))

void dodge_trace(const char *tag, u32 arg)
{
	bool mdp, dsi;
	u32 g;

	if (!dcc || !gdsc || !vbif || !vig0 || !ctl0 || !ctl1 || !intf1 || !dsi0)
		return;
	/* the panel init sends ~30 DSI commands: trace only the first few */
	if (!strncmp(tag, "dsi-dma", 7) && atomic_dec_return(&dsi_budget) < 0)
		return;
	if (atomic_dec_return(&budget) < 0)
		return;
	g = readl(gdsc);
	if (!(g & BIT(31))) {
		pr_info("dodge-trace: %s %x gdsc off\n", tag, arg);
		return;
	}
	mdp = DCC_ON(0xb0) && DCC_ON(0x10);
	dsi = DCC_ON(0xb0) && DCC_ON(0x34) && DCC_ON(0x44);
	if (!mdp) {
		pr_info("dodge-trace: %s %x mdp clk off (ahb %08x mdp %08x)\n", tag, arg,
			readl(dcc + 0xb0), readl(dcc + 0x10));
		return;
	}
	pr_info("dodge-trace: %s %x | vbif xh1 %08x axi1 %08x pnd %x src %x | vig0 addr %08x op %08x fetch %08x | ctl0 l0 %08x fl %08x st %x fpa %08x | ctl1 l0 %08x fl %08x st %x fpa %08x | intf1 tg %x ar %08x ln %x\n",
		tag, arg,
		readl(vbif + 0x204), readl(vbif + 0x20c), readl(vbif + 0x190), readl(vbif + 0x194),
		readl(vig0 + 0x14), readl(vig0 + 0x38), readl(vig0 + 0x48),
		readl(ctl0), readl(ctl0 + 0x18), readl(ctl0 + 0x1c), readl(ctl0 + 0xfc),
		readl(ctl1), readl(ctl1 + 0x18), readl(ctl1 + 0x1c), readl(ctl1 + 0xfc),
		readl(intf1), readl(intf1 + 0x2b4), readl(intf1 + 0x2b0));
	if (dsi) {
		pr_info("dodge-trace: %s dsi st0 %08x ctrl %08x dma %08x\n", tag,
			readl(dsi0 + 0x08), readl(dsi0 + 0x04), readl(dsi0 + 0x48));
		/* 6G: xml offset + 4 (DSI_6G_REG_SHIFT) */
		if (!strncmp(tag, "mdss-", 5))
			pr_info("dodge-trace: %s dsierr ack %08x timeout %08x dln0 %08x lane_st %08x lane_ctrl %08x clk_st %08x clk_ctrl %08x errmask %08x intr %08x trig %08x\n",
				tag, readl(dsi0 + 0x68), readl(dsi0 + 0xc0), readl(dsi0 + 0xb4),
				readl(dsi0 + 0xa8), readl(dsi0 + 0xac), readl(dsi0 + 0x120),
				readl(dsi0 + 0x11c), readl(dsi0 + 0x10c), readl(dsi0 + 0x110),
				readl(dsi0 + 0x84));
	}
	else
		pr_info("dodge-trace: %s dsi clk off\n", tag);
}

/*
 * DIAG fix (dodge): stop ABL's continuous-splash scanout cleanly before
 * msm_mdss_reset() pulses the MDSS core BCR, so no splash fetch is in
 * flight in the VBIF/NoC when the reset (and later msm's CB9 domain)
 * lands. Mirrors dpu_hw_intf_disable_autorefresh(): TE off, autorefresh
 * off, wait for the write pointer to leave the frame; then unstage VIG0
 * (SRC0_ADDR 0, CTL0 fetch-pipe-active 0, CTL0 flush VIG0|CTL), clear the
 * VBIF xin error latches and halt xin0/xin4 until acked, then release.
 * Only runs while the MDSS GDSC and AHB/MDP branch clocks are on.
 */
#define VDISPLAY 3168
void dodge_stop_splash(void)
{
	u32 ar, te, wr = 0, h0, ack = 0;
	u32 w0, cs0 = 0, cs1 = 0;
	int i, t_wr = -1, t_ack = -1, t_nf = -1;

	if (!dcc || !gdsc || !vbif || !vig0 || !ctl0 || !intf1)
		return;
	if (!(readl(gdsc) & BIT(31)) || !DCC_ON(0xb0) || !DCC_ON(0x10)) {
		pr_info("dodge-stop: skipped, mdss off\n");
		return;
	}
	/* 0. variant B: if the splash frame already finished (idle gap, the
	 * bad-boot predictor), wait for the next autorefresh frame to start so
	 * the stop lands right after an active transfer, like the good boots */
	wr = readl(intf1 + 0x2b0) & 0xffff;
	w0 = wr;
	if (wr == 0 || wr >= VDISPLAY) {
		cs0 = (dsi0 && DCC_ON(0x34) && DCC_ON(0x44)) ? readl(dsi0 + 0x120) : 0xdead;
		for (i = 0; i < 1000; i++) {
			wr = readl(intf1 + 0x2b0) & 0xffff;
			if (wr > 0 && wr < VDISPLAY) {
				t_nf = i;
				break;
			}
			udelay(50);
		}
		cs1 = (dsi0 && DCC_ON(0x34) && DCC_ON(0x44)) ? readl(dsi0 + 0x120) : 0xdead;
		pr_info("dodge-wait: entry wr %x clk_st %08x -> wr %x after %d (x50us) clk_st %08x\n",
			w0, cs0, wr, t_nf, cs1);
	}
	ar = readl(intf1 + 0x2b4);
	te = readl(intf1 + 0x288);
	/* 1. TE off, autorefresh off */
	writel(te & ~BIT(20), intf1 + 0x288);
	writel(0, intf1 + 0x2b4);
	/* 2. wait for the frame in progress to finish (<= 50 ms) */
	for (i = 0; i < 1000; i++) {
		wr = readl(intf1 + 0x2b0) & 0xffff;
		if (wr == 0 || wr >= VDISPLAY) {
			t_wr = i;
			break;
		}
		udelay(50);
	}
	/* let the last burst of the frame drain */
	udelay(500);
	/* 3. unstage the splash pipe */
	writel(0, vig0 + 0x14);
	writel(0, ctl0 + 0xfc);
	writel(0, ctl0 + 0x0);
	writel(BIT(0) | BIT(17), ctl0 + 0x18);
	/* 4. VBIF: clear error latches, halt xin0/xin4, wait for ack, release */
	writel(BIT(0) | BIT(4), vbif + 0x19c);
	h0 = readl(vbif + 0x200);
	writel(h0 | BIT(0) | BIT(4), vbif + 0x200);
	for (i = 0; i < 200; i++) {
		ack = readl(vbif + 0x204);
		if ((ack & (BIT(16) | BIT(20))) == (BIT(16) | BIT(20))) {
			t_ack = i;
			break;
		}
		udelay(50);
	}
	writel(h0, vbif + 0x200);
	pr_info("dodge-stop: ar %08x te %08x -> wr %x after %d, vbif ack %08x after %d, pnd %x src %x\n",
		ar, te, wr, t_wr, ack, t_ack, readl(vbif + 0x190), readl(vbif + 0x194));
}
