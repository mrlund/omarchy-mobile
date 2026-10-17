<!-- SPDX-License-Identifier: MIT -->
# 2026-10-17 — the simpledrm desktop starts at boot

**Goal.** The next boot should return to the Hyprland session that is
on the glass now. No reboot in this step.
**Phone.** OnePlus 13 CPH2653. Omarchy 4.0.4. User `ml`.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Pass. `omamobile-hyprland.service` is enabled for
multi-user. It was left running.

## What we did

The unit was `WantedBy=graphical.target`, and the default target is
multi-user, so enabling it would not have started it. `WantedBy` is
now multi-user. `OnFailure=getty@tty1.service` brings the console
back if Hyprland itself fails. `systemctl enable` installed the
multi-user wants symlink. The service was not restarted.

## What happened

`systemctl is-enabled` is `enabled`. `is-active` stayed `active`.
Monitor scale 2 and the screensaver font size 9 are in `ml`'s config,
so this boot's picture is what the next one starts with. The module
directory stays held.

## Learning

The session does not need graphical.target. A failure of the unit
returns tty1 to getty. The panel driver is still not part of this
boot.
