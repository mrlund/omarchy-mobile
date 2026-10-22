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
	for (i = 0; i < 20; i++) {
		msleep(5);
		st = readl(d + D_STATUS0);
		if (!(st & 2))
			break;
	}
	pr_info("dodge-peek: act %d after %d ms: status0 %08x trig_ctrl %08x clk_status %08x lane_status %08x\n",
		act, (i + 1) * 5, st, readl(d + D_TRIG_CTRL), readl(d + 0x120), readl(d + 0xa8));
	iounmap(d);
}

static int __init dodge_peek_init(void)
{
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
