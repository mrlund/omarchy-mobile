<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — simpledrm binds a console on the splash buffer

**Goal.** One devicetree change on the working splash boot: a
`simple-framebuffer` over ABL's splash, so `tty0` has a real console.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** `6.16.0-g02a028467db0` #5, the same build as the UFS probe.
`DTB_OPTS='splash fb'`. Stage 2 cmdline still has `omamobile.ufs-probe`.
**Result.** SSH at 26 s. The panel shows the console: a row of Tux
logos, then the kernel log in the 8×16 font.

## What we did

The 2026-10-15 framebuffer try never loaded this node: stage 2 was still
on stock's DTB. `stage2-dtb.py` `fb` now adds only the `chosen`
framebuffer when `splash` is also set, so the splash reservation and its
identity map stay the one node they already were.

The node is the same guess as that earlier try: 1440×3168, stride 5760,
format `a8r8g8b8`, `reg` covering the first `0x1167000` bytes of
`0xfc800000`.

Image `out-dodge-rdinit/images/boot-chain.img`, sha256
`27cf74aca5211601019a05db19f86d983be4133baeab5ff60ec3366358656e0a`.
`Booting OKAY` at 11:22:55. `dmesg` is
`logs/dodge-fb-20261016-112255.kmsg` (not committed).

## What happened

SSH at 26 s. `soc@0` is present. `/proc/device-tree/chosen` contains
`framebuffer@fc800000`.

```
[drm] Initialized simpledrm 1.0.0 for fc800000.framebuffer on minor 0
Console: switching to colour frame buffer device 180x198
simple-framebuffer fc800000.framebuffer: [drm] fb0: simpledrmdrmfb frame buffer device
```

`/dev/fb0` is `simpledrmdrmfb`, 1440×3168, 32 bpp, stride 5760.
`/proc/consoles` lists `tty0` as the enabled printk console. The splash
identity map is still `0xfc800000-0xff2fffff direct`. This boot logged
no `Unhandled context fault` lines. No disk failed the read-only guard,
and nothing was mounted.

The buffer is not the untouched splash. Sampled scanlines at the top,
the middle and the bottom all contain non-zero pixels, at about the
density of text on a black background. 180×198 is 1440×3168 at an 8×16
font.

## Learning

The panel is scanning this buffer. Watched by eye after SSH was up: a
row of Tux logos along the top, then a lot of very small text. The
logos are the kernel's boot logo, and the text is the 180×198 console,
so `a8r8g8b8` at 1440×3168 is close enough to be readable. The 8×16
font is why it looks tiny on this panel. ABL left the display
controller scanning the splash, command mode or not.

The 2026-10-15 "the panel did not change" result did not test this
node. Phase 3's console line is met. A larger font can wait. A flash
of the boot images is phase 4 and waits for an explicit yes.
