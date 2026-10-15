<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — rooted capture, screen off

**Goal.** Repeat the rooted capture with the panel off, for the panel
rails. Do not change the panel from the laptop.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
`ro.boot.flash.locked=0`. The human had turned the screen off.
**Kernel.** No kernel of ours.
**Result.** Saved. Same gaps as the screen-on capture.

## What we did

`DEVICE=dodge bin/omamobile capture dodge-cph2653/rooted-2026-10-15-off`.
`su` was already granted, so no new prompt.

## What happened

The directory is
`~/android/reference/dodge-cph2653/rooted-2026-10-15-off/` and stays out
of git. `live.dtb` is 1638203 bytes, the same size as the screen-on
file. `dmesg` is 2422354 bytes. `clk_summary`, `regulator_summary`,
`pinmux-pins` and `gpio` are the same short "No such file" results:
debugfs is still not mounted. The firmware and partition listings are
the same sizes as the screen-on capture.

## Learning

Both halves of the phase 1 capture are on disk. The live ids are the
ones in [2026-10-15-rooted-on.md](2026-10-15-rooted-on.md). The clock,
regulator and pin files still need a debugfs mount, which was not done.
