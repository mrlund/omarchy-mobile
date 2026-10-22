// SPDX-License-Identifier: GPL-2.0-only
/*
 * DIAG/WORKAROUND for the OnePlus 13 (dodge, SM8750) warm-boot display drop.
 *
 * Read-only snapshot of the MDSS VBIF (RT) and ABL's splash state at
 * early_initcall, before arm-smmu or any clock/genpd driver probes, and on
 * demand through /sys/module/dodge_vbif/parameters/snap. With quiesce=1 it
 * first turns off INTF1 autorefresh, waits for the fetch to stop and halts
 * the VBIF clients of the splash pipe (xin0 = VIG0, xin4) with ack, then
 * releases them. Every step is bounded. MDSS is only touched when
 * MDSS_GDSC reports power on. Addresses are SM8750's.
 */
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/moduleparam.h>
#include <linux/printk.h>

#define MDSS_GDSCR	0x0af09000UL
#define VBIF_BASE	0x0aeb0000UL
#define VIG0_BASE	0x0ae05000UL
#define INTF1_BASE	0x0ae36000UL

#define VBIF_PND_ERR	0x190
#define VBIF_SRC_ERR	0x194
#define VBIF_XIN_HALT0	0x200
#define VBIF_XIN_HALT1	0x204
#define VBIF_AXI_HALT1	0x20c
#define INTF_LINE_COUNT	0x2b0
#define INTF_AUTOREFRESH 0x2b4

#define SPLASH_XINS	(BIT(0) | BIT(4))

static char last[160];
module_param_string(last, last, sizeof(last), 0444);
static char early[160];
module_param_string(early, early, sizeof(early), 0444);
/* Stage 1's snapshots, passed to stage 2 on the kexec command line. */
static char s1e[160];
module_param_string(s1e, s1e, sizeof(s1e), 0444);
static char s1k[160];
module_param_string(s1k, s1k, sizeof(s1k), 0444);
static bool quiesce;
module_param(quiesce, bool, 0644);
static char qres[96];
module_param_string(qres, qres, sizeof(qres), 0444);

static bool mdss_on(u32 *gd)
{
	void __iomem *g = ioremap(MDSS_GDSCR, 4);

	if (!g)
		return false;
	*gd = readl(g);
	iounmap(g);
	return *gd & BIT(31);
}

static void snapshot(const char *tag, char *out, size_t len)
{
	void __iomem *v, *sp, *in;
	u32 gd;

	if (!mdss_on(&gd)) {
		snprintf(out, len, "%08x,off", gd);
		goto print;
	}
	v = ioremap(VBIF_BASE, 0x300);
	sp = ioremap(VIG0_BASE, 0x40);
	in = ioremap(INTF1_BASE, 0x300);
	if (v && sp && in)
		/* gdscr,xin_halt1,axi_halt1,pnd_err,src_err,autorefresh,line_count,vig0_addr0 */
		snprintf(out, len, "%08x,%08x,%08x,%x,%x,%08x,%x,%08x", gd,
			 readl(v + VBIF_XIN_HALT1), readl(v + VBIF_AXI_HALT1),
			 readl(v + VBIF_PND_ERR), readl(v + VBIF_SRC_ERR),
			 readl(in + INTF_AUTOREFRESH), readl(in + INTF_LINE_COUNT),
			 readl(sp + 0x14));
	else
		snprintf(out, len, "%08x,nomap", gd);
	if (in)
		iounmap(in);
	if (sp)
		iounmap(sp);
	if (v)
		iounmap(v);
print:
	pr_info("dodge-vbif: %s %s (gdscr,xin_halt1,axi_halt1,pnd,src,autoref,line,vig0)\n",
		tag, out);
}

static void do_quiesce(void)
{
	void __iomem *v, *in;
	u32 gd, ar, val, lc0, lc1;
	int ret;

	if (!mdss_on(&gd)) {
		snprintf(qres, sizeof(qres), "gdsc-off");
		goto out;
	}
	v = ioremap(VBIF_BASE, 0x300);
	in = ioremap(INTF1_BASE, 0x300);
	if (!v || !in) {
		snprintf(qres, sizeof(qres), "nomap");
		goto unmap;
	}
	ar = readl(in + INTF_AUTOREFRESH);
	if (ar & BIT(31))
		writel(ar & ~BIT(31), in + INTF_AUTOREFRESH);
	/* Let the frame in progress finish: wait until the line count stops. */
	lc0 = readl(in + INTF_LINE_COUNT);
	msleep(20);
	lc1 = readl(in + INTF_LINE_COUNT);
	msleep(20);

	writel(readl(v + VBIF_XIN_HALT0) | SPLASH_XINS, v + VBIF_XIN_HALT0);
	ret = readl_poll_timeout(v + VBIF_XIN_HALT1, val,
				 (val & SPLASH_XINS) == SPLASH_XINS, 100, 50000);
	writel(readl(v + VBIF_XIN_HALT0) & ~SPLASH_XINS, v + VBIF_XIN_HALT0);
	snprintf(qres, sizeof(qres), "ar %08x->%08x lc %x/%x/%x halt %s %08x axi1 %08x",
		 ar, readl(in + INTF_AUTOREFRESH), lc0, lc1,
		 readl(in + INTF_LINE_COUNT), ret ? "TIMEOUT" : "ack", val,
		 readl(v + VBIF_AXI_HALT1));
unmap:
	if (in)
		iounmap(in);
	if (v)
		iounmap(v);
out:
	pr_info("dodge-vbif: quiesce %s\n", qres);
}

static int snap_set(const char *val, const struct kernel_param *kp)
{
	if (quiesce)
		do_quiesce();
	snapshot("snap", last, sizeof(last));
	return 0;
}

static const struct kernel_param_ops snap_ops = { .set = snap_set };
module_param_cb(snap, &snap_ops, NULL, 0200);

static int __init dodge_vbif_init(void)
{
	if (s1e[0])
		pr_info("dodge-vbif: stage1-early %s\n", s1e);
	if (s1k[0])
		pr_info("dodge-vbif: stage1-kexec %s\n", s1k);
	snapshot("early", early, sizeof(early));
	if (quiesce) {
		do_quiesce();
		snapshot("after-quiesce", last, sizeof(last));
	}
	return 0;
}
early_initcall(dodge_vbif_init);
