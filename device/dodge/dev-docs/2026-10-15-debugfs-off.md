<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — debugfs summaries, screen off

**Goal.** Read the same four debugfs files with the panel off.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`. The
human had turned the screen off.
**Kernel.** No kernel of ours. Stock OxygenOS, Magisk `su`.
**Result.** Saved, then debugfs was unmounted. The regulator summary
matches the awake copy.

## What we did

Same mount as [2026-10-15-debugfs.md](2026-10-15-debugfs.md):
`mount -t debugfs debugfs /sys/kernel/debug`, read
`clk/clk_summary`, `regulator/regulator_summary`, `gpio`, and
`pinctrl/*/pinmux-pins`, then `umount`. The laptop did not change the
panel.

## What happened

Saved under
`~/android/reference/dodge-cph2653/rooted-2026-10-15-debugfs-off/`,
out of git. Sizes match the awake set: clk 178824, regulator 28268,
gpio 15780, pinmux 20968. Checksums: `regulator_summary.txt` and
`pinmux-pins.txt` are identical to the awake files. `clk_summary.txt`
differs by 10 lines and `gpio.txt` by 4. After unmount,
`/sys/kernel/debug` is empty again.

The regulator file names the DSI rails, including
`soc:qcom,dsi-display-primary-vddio`,
`soc:qcom,dsi-display-primary-vci`, and the mdss DSI phy and ctrl
supplies. Their lines did not change with the screen off.

## Learning

Blanking the panel did not change the regulator summary. The rails are
still in the state they had while the screen was awake, or this "screen
off" does not drop them. That is the comparison the two captures were
for.
