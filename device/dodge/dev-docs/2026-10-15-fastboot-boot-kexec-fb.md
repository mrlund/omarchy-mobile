<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — simple-framebuffer on ABL's splash buffer: no change on screen

**Goal.** A console on the panel, so stage 2's log (and the init's USB
report before it panics) can be read off the screen. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 1 `6.16.0-gf71c365a86e2` (`out-dodge-rdinit`),
stage 2 the `out-dodge` `Image`, `dodge-try` initramfs.
**Result.** Fail. Watched by hand: the fastboot frame did not change.
OxygenOS back at 136 s, no USB, as on the two tries before.

## What we did

Facts first, from the stock captures:

- The panel is `mdss_dsi_panel_AA569_P_3_A0019_dsc_cmd` (rooted
  `dmesg`): a DSC **command-mode** panel. 1440×3168
  (`ro.oplus.lcd.display.screen.underlightsensor.screensize`).
- The live FDT's `cont_splash_region` is `reg = <0x00 0xfc800000 0x00
  0x2b00000>`. That range lies inside the live memory map, and nothing
  in our DTB reserved it, so earlier stage 2 kernels were free to
  allocate there.
- `DRM_SIMPLEDRM`, `SYSFB_SIMPLEFB` and `FRAMEBUFFER_CONSOLE` are `=y`;
  `DRM_MSM` is `=m` and was never loaded, and `clk_ignore_unused
  pd_ignore_unused` keep the display clocks and GDSC that ABL left on.

One change from the ramoops try, in stage 2's DTB: a `no-map`
`splash@fc800000` reservation of the whole region, and

```dts
framebuffer@fc800000 {	/* under /chosen */
	compatible = "simple-framebuffer";
	reg = <0x00 0xfc800000 0x00 0x1167000>;
	width = <1440>;
	height = <3168>;
	stride = <5760>;
	format = "a8r8g8b8";
};
```

The ramoops node stayed. `boot-v4-kexec-fb.img`, 58339328 bytes, sha256
`d567efd09b18b87af1d731c268bcee5b8881731e38b9010f195e1d29a73c163d`.

## What happened

| t after `Booting OKAY` | USB |
| --- | --- |
| 0 s | `18d1:d00d` (fastboot) |
| 1 s | nothing |
| 136 s | `22d9:2769`, adb |

The human watched the panel throughout: the OnePlus logo and "fastboot
mode" stayed as they were, then OxygenOS booted. No black frame, no
text, no noise. pstore empty again.

## Learning

On a command-mode panel a frame goes out only when the display
controller is triggered (cheetah's DECON had the same property). Writes
into ABL's buffer did not reach the panel, so ABL did not leave
auto-refresh on, or the buffer it scans is not this region, or the
format is wrong and nothing changed anyway. Without a trigger there is
no screen console; the panel's own image is self-refresh from its RAM.

Both log paths without USB tried today (ramoops, framebuffer) showed
nothing. The next step is a timing-coded probe in stage 2
([../chainload/README.md](../chainload/README.md), Handoff).

The chain-loader build moved from a session scratchpad into the repo
the same day: `tools/dodge-chain` and `device/dodge/chainload/`. Its
`DTB_OPTS="ramoops fb"` rebuilds this try's stage 2 DTB byte for byte;
with no options it rebuilds the live-memory DTB of the 82 s try.
