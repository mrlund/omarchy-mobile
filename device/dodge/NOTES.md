<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge) bring-up notes

Findings from this phone, newest first. The plan is [PLAN.md](PLAN.md).
Attempts live in [dev-docs/](dev-docs/).

## 2026-10-16: SSH, and the timezone screen

- **The timezone screen is `systemd-firstboot`.** Its description is
  `Initial Setup`. `ConditionFirstBoot=yes` while `/etc/machine-id` is
  the word `uninitialized`, and the unit is `Before=sysinit`, so it
  holds the boot on the console (locale, keymap, timezone, root
  password) and `sshd` never starts. This phone has no keyboard and
  the touchscreen driver is not loaded. Seed machine-id, or mask the
  unit. Do not wait for someone to tap it.
- **OpenSSH 10.6 refuses a locked root when `UsePAM` is off.** The
  packaged config has `UsePAM yes` and `PermitRootLogin
  prohibit-password`. An early config with `UsePAM no` logged
  `User root not allowed because account is locked` and never tried
  `authorized_keys`. Leave the root password locked.
- **`openssh` 10.6p1-2 does not create the `sshd` user.** Without it,
  `sshd-session` exits (`unknown [priv]`) and the client sees a
  publickey denial or a connection reset. The device package ships
  `usr/lib/sysusers.d/sshd.conf`.
- **The module tree stays held** (`6.16.0-gb3ee311dab85.held`).
  Loading it, `msm` included, is what blacked the panel. `plymouth-start`
  stays masked.
