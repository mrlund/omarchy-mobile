<!-- SPDX-License-Identifier: MIT -->
# 2026-10-25: Chromium hung on every page (no default keyring), blurry PNG icons, SDDM login staged

Martin saw Chromium time out on google.com (`ERR_TIMED_OUT`, later an
endless spinner) while Wi-Fi was connected, with and without USB.

## Cause: no default keyring

- The network was fine: DNS, the default route via Wi-Fi and HTTPS worked as
  root and as ml; no firewall. Chromium started from ssh with Martin's
  profile and flags loaded google.com.
- A net-log of the GUI Chromium: every request that carries cookies stopped
  at `COMPUTED_PRIVACY_MODE` and never went out. Cookie-less background
  fetches went through.
- Chromium runs with `--password-store=gnome-libsecret` (chromium-flags.conf)
  and needs the Secret Service to decrypt its cookie store.
- `~/.local/share/keyrings` was empty. gnome-keyring-daemon answered the
  first Secret Service call with a "create keyring" prompt; the journal
  shows gcr-prompter `BeginPrompting` / `creating new GcrPromptDialog prompt`
  / `PromptReady` (07:43 CET). The dialog never showed on the phone, so the
  cookie-key lookup waited forever.

## Why dodge had no keyring

- Stock Omarchy creates an unencrypted "Default keyring" in
  `install/user/default-keyring.sh`, part of `omarchy-provision-user`, which
  `omamobile-firstboot` runs as the user (`s_user_setup`). The login itself
  never creates it: `pam_gnome_keyring` (in `sddm-autologin`) only starts
  the daemon, and an autologin has no password to create one with. So this
  is not SDDM vs tty1 as such; the provisioning step was missing.
- dodge's rootfs never ran firstboot, and `omarchy-provision-user` never ran
  for ml (no `~/.local/state/omarchy/done/finalize-user`).

## What else of omarchy-provision-user is missing on dodge

Checked on the phone; the rootfs came with a pre-provisioned home (Sep 25),
so almost everything is present:

| step | state on dodge |
|---|---|
| skill symlinks, xdg-user-dirs, gtk bookmarks | present |
| theme.sh (Tokyo Night, btop link) | present |
| chromium.sh (copy-url, yt-dlp native hosts) | present |
| git.sh (identity) | present |
| xcompose.sh | present (rerunning it would blank the identity lines: it takes the name from installer env) |
| mise-work.sh (`~/Work/.mise.toml`) | present |
| **default-keyring.sh** | **missing**, now applied |
| **mise.sh** (node + AI CLI stubs: codex, claude, gh, ...) | **missing**: `mise` has no installs, no `~/.config/mise`. Downloads from the network; not applied, for Martin to decide |
| x86 hardware fixes (asus, framework, dell, nouveau) | not applicable |
| default browser, mailto, migrations marked | present |
| `finalize-user` marker | missing (would be set by a full run) |
| install/user/first-run/* | done (`first-run-user`, Sep 25) |

A full `omarchy-provision-user --force` is not run: xcompose.sh would
overwrite `~/.XCompose`, and mise.sh downloads tools.

## Fix

- Live (morning of 2026-10-25): Omarchy's `default-keyring.sh` as ml, then
  gnome-keyring-daemon restarted. `secret-tool store/lookup` works with no
  prompt; Martin confirmed browsing works.
- `desktop/setup-stock` step 1b runs the same script as the user
  (idempotent: it writes only missing files). Re-run on the phone: no change
  to the existing keyring, and a scratch HOME gets both files.
- `setup-stock --revert` keeps the keyring: by then it may hold Chromium's
  cookie key and other secrets. Remove it by hand if really needed.

## Stock login: SDDM autologin staged (not yet booted)

Martin asked for the stock login path. `desktop/login-sddm` (root) mirrors
firstboot's `s_login`:

- `/etc/sddm.conf.d/autologin.conf` (`User=ml`, `Session=omarchy.desktop`,
  i.e. `uwsm start -g -1 -e -D Hyprland hyprland.desktop`) and
  `/var/lib/sddm/state.conf`.
- `sddm.service` drop-in: `After=omamobile-display-msm.service
  omamobile-touch.service` (those order only `Before=omamobile-hyprland`).
- `/etc/xdg/uwsm/env.d/50-dodge-software-gl`: `LIBGL_ALWAYS_SOFTWARE=1`,
  which `omamobile-hyprland.service` set for the session. Hyprland itself
  renders on the GPU either way; apps keep llvmpipe, so only the login
  path changes at this boot.
- `omamobile-hyprland.service` disabled, `sddm.service` enabled, default
  target `graphical.target`. dodge booted to `multi-user.target`, which is
  why the already-enabled sddm never started. sddm `Conflicts=getty@tty1`.
- Nothing was started or stopped live. `login-sddm --status` shows the
  next-boot path; `login-sddm --revert` restores tty1 (default target from
  the saved state, omamobile-hyprland enabled).
- The deadline check needs no change: it tests `pgrep -x Hyprland`, dpms and
  the DSI error count, not the process tree.

Expected next boot: no greeter (SDDM autologin starts the session
directly), Hyprland then lock-on-start locks with the PIN pad, as on the
2026-10-24 boot. If the session exits, SDDM shows its greeter (Relogin=false).

## Blurry Chromium icon

- Omarchy's shell (`/usr/share/omarchy/shell/services/AppLibrary.qml`,
  omarchy 4.0.4) builds an icon index with `find`, SVGs first, and keeps
  the first file per name. PNG-only icons get whatever size `find` lists
  first: `chromium.png` resolved to `hicolor/16x16`, scaled to 52 x 3 =
  156 px on the home grid. 15 other PNG-only icons (web apps, imv) got
  48x48. SVG icons are sharp.
- Upstream bug; the fix belongs in AppLibrary (prefer the largest PNG).
- dodge workaround in `desktop/setup-ui`: link the largest hicolor PNG
  (512 or 256) of each icon without an SVG into `~/.local/share/icons`,
  which the index scans first. 27 links; listed in
  `~/.local/state/dodge-setup-ui/icon-links`, removed by `--revert`.
- Applied on the phone; the index now resolves chromium to the 256 px PNG.
  The running shell picks it up when the launcher opens (`refreshIcons`) or
  after a shell restart. Visual check pending (the panel was off).
