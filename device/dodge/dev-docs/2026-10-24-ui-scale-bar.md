<!-- SPDX-License-Identifier: MIT -->
# 2026-10-24: display scale and status bar to the stock phone setup, with dodge insets

Martin found the top-bar icons too small to hit, and some sat in the
rounded corners. The dodge user had never had the stock phone setup
(`omamobile-setup-user`), so it ran Omarchy's desktop shell at scale 2,
where the bar is 26 lp = 2.6 mm on this 510 ppi panel.

- **Stock (Pixel 1440x3120, same density):** scale 3, the `omamobile.bar`
  profile (at least 44 lp, inset `spacing.huge` 18 lp) and the phone
  plugins.
- **Dodge:** `device/dodge/desktop/setup-ui` does the display part of the
  stock setup (plugins, profile, scale 3, same omarchy-done markers).
  `desktop/shell.toml` adds the dodge overrides: bar 48 lp (7.2 mm) and
  inset 22 lp (3.3 mm, clear of corner arcs up to about 220 px; the radius
  isn't published).
- Applied live at 19:51 CEST (`hyprctl reload`, `omarchy-restart-shell`).
  Bar 480x48 lp, home and dock up.
- Revert: `setup-ui --revert`, then `hyprctl reload` and
  `omarchy-restart-shell`.
- Next: Martin tries tapping. The lock, PIN and power-key parts of the stock
  setup are still to decide.
