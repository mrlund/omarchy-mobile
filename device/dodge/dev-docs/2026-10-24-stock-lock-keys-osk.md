<!-- SPDX-License-Identifier: MIT -->
# 2026-10-24: the rest of the stock phone setup (lock, PIN, power key, keyboard)

Martin asked (19:57 CEST) for "basically the same experience" as stock
Omarchy Mobile: PIN lock, power key, on-screen keyboard and the rest of the
stock setup. This replaces his earlier "screen off on idle, no lock" choice.

## What stock does, and what dodge never had

Stock gets its setup from `omamobile-firstboot` (system part, then the user
part) on the first boot. Dodge's rootfs never ran firstboot (there's no
`/var/lib/omamobile/firstboot`, no `/var/log/omarchy-install.log`), so:

- the user had only `first-run-user` in `~/.local/state/omarchy/done`.
  `omamobile-setup-user` had never run; setup-ui (earlier today) did only
  its display part.
- `/etc/pam.d/omarchy-lock-password` was missing (Omarchy's
  `install/config/lockscreen-pam.sh` → `omarchy-apply-lock`). Without it
  the lock refuses to engage: `omarchy-shell lock lock` answers
  `missing-pam` and the power key does nothing visible.
- the user account's password was locked (`passwd -S`: L). On stock the PIN
  *is* the account password (`omamobile-set-pin` runs `passwd`; lock, sudo
  and polkit check it through PAM). `~/.config/omamobile/credential` holds
  only the type (`pin`), never the secret.

The omamobile-omarchy patches (lock number pad, lock wake IPC for hardware
keys, bl_power following dpms, PIN input) were already applied by the
pacman hook (`/var/lib/omamobile/omarchy-patches/state.json`), as were
squeekboard 1.43.1 and wtype from the omamobile repo. Nothing was installed;
nothing was upgraded.

## `desktop/setup-stock` (run as root)

1. `omarchy-apply-lock` for the user: the lock's PAM service.
2. The packaged `omamobile-setup-user` as is. It runs the phone shell
   plugins (fingerprint, keyboard, home, update, access), hides the dev tools,
   sets the credential type, hides the cursor, enables the OSK (gsettings and
   squeekboard autostart), adds the squeekboard terminal layout, unmasks
   fcitx5, sets the suspend-off toggle, adds the phone window rules and keys
   (`dofile phone.lua`), the Chromium mobile flags, menu entries (PIN,
   fingerprint, update; disk unlock hidden), screensaver branding,
   lock-after-screensaver and lock-keypad.
3. The tail of firstboot's user step: credential `pin`, `lock-keypad`, and
   `lock-on-start` (only once the account has a password, as stock).
4. Idle: dodge's `omamobile-idle-off.service` (screen off at 150 s, no
   lock) is globally disabled and stopped, and the `screensaver-off` toggle
   is removed. The stock idle path runs instead: screensaver at 150 s, lock
   at 300 s, then the lock blanks the panel after 10 s (keypad devices).
5. Live apply: `hyprctl reload`, squeekboard started, `omarchy-restart-shell`.
   No reboot is needed.

The PIN is not set by the script and never stored by it. Set it as root
with `passwd <user>` (digits only, for the number pad), or on the phone with
menu → System → PIN once one exists.

`setup-stock --revert [user]` restores the backed-up configs
(`~/.local/state/dodge-setup-stock/`), toggles and done markers. It puts the
account password back to its state before the PIN, from
`/var/lib/dodge-setup-stock/shadow.<user>` (root-only; that was the locked
hash, not a PIN). It also removes the lock PAM file it created and
re-enables dodge's idle-off service. The result: no lock, no PIN, screen off
on idle.

### Stock steps kept out (they would break dodge)

- **ufw** (firstboot: deny incoming, ssh on `usb0` only). Root ssh over
  Wi-Fi must keep working, so ufw stays inactive.
- **sddm autologin**: dodge starts Hyprland with
  `omamobile-hyprland.service` (`desktop/install`).
- **`usermod -L root`**: no change needed. sshd already allows root by key
  only (`10-omamobile.conf`).
- **The other Omarchy system install steps** that firstboot runs (theme,
  browser policy, faillock limit, ssh tweaks, services, hardware fixes for
  x86 laptops) were not run in this slice. Only the lock PAM step was
  needed for the phone experience. Review is open in NOTES.

## Dodge-specific changes

- **Boot deadline check** (`kernel/diag/msm-trace/dodge-deadline-check.sh`,
  the copy in /root updated, the old one at `.pre-lock`): with lock-on-start
  the lock blanks the panel about 10 s after login. So dpms is Off at the
  80 s check on a healthy boot, and the old check (dpms must be On) would
  have kept the reboot armed. Off now counts as clean when Hyprland is
  running and there are no DSI errors.
- **Power key**: `pmic_pwrkey` (KEY_POWER) maps to XF86PowerOff, which
  phone.lua binds to `omamobile-keys`. A short press locks and turns the
  screen off; when locked it toggles the screen. Holding it for 0.6 s
  opens Omarchy's system menu (Screensaver, Lock, Logout, Reboot,
  Shutdown, PIN). Nothing powers off without a tap in that menu, and
  logind's own power-key handling isn't involved.

## Tests (live, 20:04-20:17 CEST)

These were driven by evdev writes to `pmic_pwrkey` and `touchpanel` (input
injection only) and by `wtype` as the user.

- A short power press locks the phone (`secure:true`), dpms goes Off and
  bl_power is 4. Root ssh over USB and Wi-Fi still worked while locked.
- A power press when locked wakes the panel to the PIN pad
  (`logs/dodge-lockscreen-20261024.png`). It blanks again after about
  10 s.
- Unlock: a wrong PIN by keyboard stays locked; the right one unlocks. A
  touch-tapped PIN on the number pad plus enter unlocks.
- The pad's ABC switch brings up squeekboard above the lock
  (`logs/dodge-lockscreen-osk-20261024.png`). A tap on the launcher's
  search field shows it too (`logs/dodge-osk-20261024.png`).
- A long power press opens the system menu
  (`logs/dodge-powermenu-20261024.png`).
- Idle, no input from about 20:11: the screensaver window
  (`org.omarchy.screensaver`, foot + ttfx) opened at 20:14:08, the lock
  engaged at 20:16:39 (`secure:true`), and dpms was Off with bl_power 4
  by 20:16:51. Root ssh kept working.
- A first idle run (20:08-20:13) showed no screensaver. That was the test's
  fault: `omarchy-launch-screensaver` skips the launch when
  `pgrep -f org.omarchy.screensaver` matches, and the polling loop had that
  string on its own command line. Don't put it in a monitor's arguments.
