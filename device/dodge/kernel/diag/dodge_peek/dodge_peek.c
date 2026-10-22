// SPDX-License-Identifier: GPL-2.0-only
/* dodge: read-only peek at apps SMMU, MDSS and DSI0 state (diagnostic). */
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/module.h>

#define SMMU_BASE 0x15000000UL
#define SMMU_SIZE 0x100000UL
#define MDSS_BASE 0x0ae00000UL
#define DSI0_BASE 0x0ae94000UL

static void peek_smmu(void)
{
	void __iomem *s = ioremap(SMMU_BASE, SMMU_SIZE);
	u32 idr0, idr1, pgshift, numpage, numcb, nsmr, i;

	if (!s)
		return;
	idr0 = readl(s + 0x20);
	idr1 = readl(s + 0x24);
	pgshift = (idr1 & BIT(31)) ? 16 : 12;
	numpage = 1 << (((idr1 >> 28) & 7) + 1);
	numcb = idr1 & 0xff;
	nsmr = idr0 & 0xff;
	pr_info("dodge-peek: smmu idr0 %08x idr1 %08x pgshift %u numpage %u numcb %u nsmr %u gfsr %08x gfsynr0 %08x gfsynr1 %08x sCR0 %08x\n",
		idr0, idr1, pgshift, numpage, numcb, nsmr, readl(s + 0x48),
		readl(s + 0x50), readl(s + 0x54), readl(s + 0x0));
	for (i = 0; i < nsmr; i++) {
		u32 smr = readl(s + 0x800 + 4 * i), s2cr = readl(s + 0xc00 + 4 * i);
		u32 id = smr & 0xffff, mask = (smr >> 16) & 0xffff;

		if ((smr & BIT(31)) && ((id ^ 0x800) & ~mask & 0xfffc) == 0)
			pr_info("dodge-peek: smr[%u] %08x s2cr %08x (cb %u)\n", i, smr, s2cr, s2cr & 0xff);
	}
	if (((numpage + numcb) << pgshift) > SMMU_SIZE) {
		pr_info("dodge-peek: cb space beyond map\n");
		goto out;
	}
	for (i = 0; i < numcb; i++) {
		void __iomem *cb = s + ((numpage + i) << pgshift);
		u32 sctlr = readl(cb + 0x0), fsr = readl(cb + 0x58);
		u32 cbar = readl(s + (1 << pgshift) + 4 * i);

		if (fsr || (sctlr & 1))
			pr_info("dodge-peek: cb%u sctlr %08x fsr %08x far %016llx fsynr0 %08x cbar %08x cbfrsynra %08x ttbr0 %016llx\n",
				i, sctlr, fsr, readq(cb + 0x60), readl(cb + 0x68), cbar,
				readl(s + (1 << pgshift) + 0x400 + 4 * i), readq(cb + 0x20));
	}
out:
	iounmap(s);
}

static void peek_block(const char *name, unsigned long base, u32 len)
{
	void __iomem *p = ioremap(base, len);
	u32 off;

	if (!p)
		return;
	for (off = 0; off < len; off += 32)
		pr_info("dodge-peek: %s +%03x: %08x %08x %08x %08x %08x %08x %08x %08x\n", name, off,
			readl(p + off), readl(p + off + 4), readl(p + off + 8), readl(p + off + 12),
			readl(p + off + 16), readl(p + off + 20), readl(p + off + 24), readl(p + off + 28));
	iounmap(p);
}

static int act;
module_param(act, int, 0444);
static uint xm = 0x81;
module_param(xm, uint, 0444);
MODULE_PARM_DESC(act, "0 peek only; 1 clear TRIG_CTRL BLOCK_DMA_WITHIN_FRAME; 2 clear TRIG_CTRL TE; 3 re-write DMA trigger");

/* 6G registers sit 4 bytes above the dsi.xml offsets */
#define D_STATUS0 0x08
#define D_TRIG_CTRL 0x84
#define D_TRIG_DMA 0x90

static void dsi_act(void)
{
	void __iomem *d = ioremap(DSI0_BASE, 0x300);
	u32 t, st;
	int i;

	if (!d)
		return;
	t = readl(d + D_TRIG_CTRL);
	st = readl(d + D_STATUS0);
	pr_info("dodge-peek: act %d before: status0 %08x trig_ctrl %08x\n", act, st, t);
	if (act == 1)
		writel(t & ~BIT(12), d + D_TRIG_CTRL);
	else if (act == 2)
		writel(t & ~BIT(31), d + D_TRIG_CTRL);
	else if (act == 3)
		writel(1, d + D_TRIG_DMA);
	else if (act == 4 || act == 5) {
		/* DSI soft reset, as msm's dsi_sw_reset (absolute offsets) */
		u32 ctrl = readl(d + 0x04), cdma = readl(d + 0x3c);

		writel(ctrl & ~1, d + 0x04);
		writel(readl(d + 0x11c) | 0x3f, d + 0x11c);
		wmb();
		writel(1, d + 0x118);
		msleep(20);
		writel(0, d + 0x118);
		wmb();
		writel(ctrl, d + 0x04);
		pr_info("dodge-peek: act %d after soft reset: status0 %08x cmd_dma_ctrl %08x int_ctrl %08x\n",
			act, readl(d + D_STATUS0), readl(d + 0x3c), readl(d + 0x110));
		if (act == 4) {
			/* one DCS NOP (05 00 00) from the TPG DMA FIFO: no memory fetch */
			writel(0, d + 0x15c);
			writel(1, d + 0x1ec);
			udelay(1);
			writel(0, d + 0x1ec);
			writel(BIT(1) | BIT(2) | (3 << 16), d + 0x15c);
			writel(0x80050000, d + 0x17c);
			writel(0, d + 0x17c); /* odd dword count: pad */
			writel(cdma | BIT(28) | BIT(26), d + 0x3c);
			writel(4, d + 0x4c);
			writel(readl(d + 0x110) | 1, d + 0x110); /* ack old CMD_DMA_DONE, masks kept */
			wmb();
			writel(1, d + D_TRIG_DMA);
		}
	}
	for (i = 0; i < 20; i++) {
		msleep(5);
		st = readl(d + D_STATUS0);
		if (!(st & 2))
			break;
	}
	pr_info("dodge-peek: act %d after %d ms: status0 %08x trig_ctrl %08x clk_status %08x lane_status %08x int_ctrl %08x tpg_fifo_status %08x\n",
		act, (i + 1) * 5, st, readl(d + D_TRIG_CTRL), readl(d + 0x120), readl(d + 0xa8),
		readl(d + 0x110), readl(d + 0x1dc));
	if (act == 4) {
		writel(0, d + 0x15c);
		writel(1, d + 0x1ec);
		udelay(1);
		writel(0, d + 0x1ec);
	}
	iounmap(d);
}

#define VBIF_BASE 0x0aeb0000UL
static void vbif_state(void __iomem *v, const char *tag)
{
	pr_info("dodge-peek: vbif %s: clkon %08x pnd_err %08x src_err %08x err_info %08x xin_halt0 %08x xin_halt1 %08x axi_halt0 %08x axi_halt1 %08x\n",
		tag, readl(v + 0x4), readl(v + 0x190), readl(v + 0x194), readl(v + 0x1a0),
		readl(v + 0x200), readl(v + 0x204), readl(v + 0x208), readl(v + 0x20c));
}

static void dsi_reset_and_dma(const char *tag)
{
	void __iomem *d = ioremap(DSI0_BASE, 0x300);
	u32 ctrl, st;
	int i;

	if (!d)
		return;
	ctrl = readl(d + 0x04);
	writel(ctrl & ~1, d + 0x04);
	writel(readl(d + 0x11c) | 0x3f, d + 0x11c);
	wmb();
	writel(1, d + 0x118);
	msleep(20);
	writel(0, d + 0x118);
	wmb();
	writel(ctrl, d + 0x04);
	pr_info("dodge-peek: %s after soft reset: status0 %08x clk_status %08x\n", tag,
		readl(d + D_STATUS0), readl(d + 0x120));
	writel(readl(d + 0x110) | 1, d + 0x110);
	wmb();
	writel(1, d + D_TRIG_DMA);	/* memory DMA, last command (base/len unchanged) */
	for (i = 0; i < 20; i++) {
		msleep(5);
		st = readl(d + D_STATUS0);
		if (!(st & 2))
			break;
	}
	pr_info("dodge-peek: %s memory DMA after %d ms: status0 %08x clk_status %08x int_ctrl %08x\n",
		tag, (i + 1) * 5, st, readl(d + 0x120), readl(d + 0x110));
	iounmap(d);
}

static int poll_bits(void __iomem *r, u32 mask, int ms)
{
	int i;

	for (i = 0; i < ms * 10; i++) {
		if ((readl(r) & mask) == mask)
			return 0;
		udelay(100);
	}
	return -ETIMEDOUT;
}

/* act 7: drain VBIF (xin halt for xm + AXI halt), release, DSI reset, memory DMA.
 * act 8: xin identification: halt xm only, then memory DMA while halted, release, reset. */
static void vbif_act(void)
{
	void __iomem *v = ioremap(VBIF_BASE, 0x300);
	void __iomem *sp = ioremap(0x0ae05000UL, 0x40);
	u32 clkon, h0;
	int rx, ra = 0;

	if (!v || !sp)
		goto out;
	pr_info("dodge-peek: act %d xm %02x vig0 src_size %08x img %08x xy %08x out %08x addr0 %08x fmt %08x\n",
		act, xm, readl(sp), readl(sp + 4), readl(sp + 8), readl(sp + 0xc), readl(sp + 0x14), readl(sp + 0x30));
	vbif_state(v, "before");
	clkon = readl(v + 0x4);
	writel(clkon | 1, v + 0x4);
	h0 = readl(v + 0x200);
	writel(h0 | xm, v + 0x200);
	wmb();
	rx = poll_bits(v + 0x204, xm << 16, 50);
	vbif_state(v, rx ? "xin halt TIMEOUT" : "xin halted");
	if (act == 8) {
		dsi_reset_and_dma("act8 (xin halted)");
		vbif_state(v, "after dma, halted");
	} else {
		writel(1, v + 0x208);
		wmb();
		ra = poll_bits(v + 0x20c, 1, 50);
		vbif_state(v, ra ? "axi halt TIMEOUT" : "axi halted");
		writel(0, v + 0x208);
	}
	writel(h0, v + 0x200);
	wmb();
	udelay(100);
	writel(clkon, v + 0x4);
	vbif_state(v, "released");
	dsi_reset_and_dma(act == 8 ? "act8 (released)" : "act7 (drained)");
	vbif_state(v, "end");
out:
	if (sp)
		iounmap(sp);
	if (v)
		iounmap(v);
}

/* act 9: pre-msm snapshot (read-only), only if MDSS_GDSC reports power on */
static void premsm_snapshot(void)
{
	void __iomem *g = ioremap(0x0af09000UL, 4);
	void __iomem *v, *sp, *c0, *c1, *in;
	u32 gd;

	if (!g)
		return;
	gd = readl(g);
	iounmap(g);
	pr_info("dodge-peek: premsm mdss_gdscr %08x\n", gd);
	if (!(gd & BIT(31))) {
		pr_info("dodge-peek: premsm gdsc off, skipping MDSS reads\n");
		return;
	}
	v = ioremap(VBIF_BASE, 0x300);
	sp = ioremap(0x0ae05000UL, 0x40);
	c0 = ioremap(0x0ae16000UL, 0x40);
	c1 = ioremap(0x0ae17000UL, 0x40);
	in = ioremap(0x0ae36000UL, 0x300);
	if (v && sp && c0 && c1 && in) {
		vbif_state(v, "premsm");
		pr_info("dodge-peek: premsm vig0 src_size %08x out %08x addr0 %08x fmt %08x\n",
			readl(sp), readl(sp + 0xc), readl(sp + 0x14), readl(sp + 0x30));
		pr_info("dodge-peek: premsm ctl0 layer0 %08x top %08x flush %08x start %08x | ctl1 layer0 %08x top %08x flush %08x start %08x\n",
			readl(c0), readl(c0 + 0x14), readl(c0 + 0x18), readl(c0 + 0x1c),
			readl(c1), readl(c1 + 0x14), readl(c1 + 0x18), readl(c1 + 0x1c));
		pr_info("dodge-peek: premsm intf1 tg_en %08x tear_en %08x line_count %08x autorefresh %08x\n",
			readl(in), readl(in + 0x284), readl(in + 0x2b0), readl(in + 0x2b4));
	}
	/* read-only: DSI0 cmd-DMA regs (DMA_BASE/LEN, CMD_DMA_CTRL, TRIG) and SMMU SID 0x800 state */
	peek_block("premsm-dsi0", DSI0_BASE, 0xc0);
	peek_smmu();
	if (in) iounmap(in);
	if (c1) iounmap(c1);
	if (c0) iounmap(c0);
	if (sp) iounmap(sp);
	if (v) iounmap(v);
}

static int __init dodge_peek_init(void)
{
	if (act == 9) {
		premsm_snapshot();
		return -EAGAIN;
	}
	if (act == 7 || act == 8) {
		vbif_act();
		return -EAGAIN;
	}
	if (act == 6) {	/* read-only: DPU VBIF (xin/axi halt, clkon, err) */
		peek_block("vbif", 0x0aeb0000UL, 0x300);
		return -EAGAIN;
	}
	if (act) {
		dsi_act();
		return -EAGAIN;
	}
	peek_smmu();
	peek_block("mdss", MDSS_BASE, 0x100);
	peek_block("dsi0", DSI0_BASE, 0x300);
	peek_block("phy", 0x0ae95000UL, 0x200);
	peek_block("phylane", 0x0ae95200UL, 0x280);
	peek_block("pll", 0x0ae95500UL, 0x400);
	peek_block("dispcc8", 0x0af08000UL, 0x200);
	peek_block("dispccc", 0x0af0c000UL, 0x20);
	return -EAGAIN; /* nothing stays loaded */
}
module_init(dodge_peek_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("dodge read-only SMMU/MDSS/DSI peek");
