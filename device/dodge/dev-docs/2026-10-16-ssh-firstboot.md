<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — SSH works, the setup screen was first-boot

**Goal.** Log in to the Omarchy root without the timezone screen and
without a keyboard.
**Phone.** OnePlus 13 CPH2653. Omarchy 4.0.4 on `userdata`.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Pass. `ssh root@172.16.42.1` lands on Omarchy. The
first-boot prompt does not run.

## What we did

The glass still showed the timezone screen while the cable was already
fastboot. `boot-stay-avb.img` was flashed to `boot_a`, the ramdisk
mounted `sda15`, and `boot-chain-avb.img` was flashed back afterwards.
Nothing else was written. The module directory stayed
`6.16.0-gb3ee311dab85.held`.

The early sshd from the previous ramdisk pass had logged
`User root not allowed because account is locked` and
`sshd-session: unknown [priv]`. Root's password is locked. That config
had `UsePAM no`, and OpenSSH 10.6 then refuses the account before it
tries the key. `openssh` 10.6p1-2 also ships no `sshd` user, so the
privilege-separated child exits. A `sysusers` snippet created that
user. With `UsePAM yes`, the stock `sshd_config` accepted the laptop
key on a test port while the root was still mounted from the ramdisk.

`/etc/machine-id` was the 14-byte marker `uninitialized`, so
`systemd-firstboot` (`Initial Setup`, `ConditionFirstBoot=yes`) was
waiting on the console for a locale, a keymap, a timezone and a root
password, before `sysinit`. That is the screen. It was seeded with
timezone `Europe/Copenhagen`, keymap `us`, and a real machine-id. The
root password stayed locked. `LANG` stayed `C.UTF-8`. The early unit
and the `sshdgenkeys` mask were removed.

## What happened

After the chain image was restored, the gadget was up about 24 s from
the reboot and port 22 answered at once. `sshd` is the packaged unit
and is active. `systemd-firstboot` is inactive. `systemctl
is-system-running` is `running`, with no failed units. `/` is
`/dev/sda15`. `persist` and `super` are read-only, and `/dev/sda` is
absent. `soc@0` is present. tty1 is `agetty`.

## Learning

A locked root and `UsePAM no` is a refused login, not a missing key.
The next image needs the `sshd` sysusers entry. `systemd-firstboot` on
a phone with no keyboard blocks the boot on the glass for as long as
machine-id is uninitialized. The device package now ships the user and
masks that unit.
