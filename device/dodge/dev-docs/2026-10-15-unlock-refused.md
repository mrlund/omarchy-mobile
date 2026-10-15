<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — flashing unlock refused

**Goal.** `fastboot flashing unlock`, after the getvar check matched.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`. On the bootloader
menu, slot A, locked.
**Kernel.** No kernel of ours.
**Result.** Refused. The phone stayed locked and was rebooted to OxygenOS.

## What we did

`getvar` still showed `product:sun`, `unlocked:no`, `current-slot:a`,
slot B unbootable, `is-userspace:no`. Then `fastboot flashing unlock`.

## What happened

ABL answered `Flashing Unlock is not allowed`. A second `getvar unlocked`
was still `no`. Nothing was wiped. `fastboot reboot` was sent so the OEM
unlocking switch can be turned on in OxygenOS. The screen left the
bootloader menu.

## Learning

The unlock ability bit is off. The next attempt is the same command,
after Developer options has OEM unlocking on. Do not substitute
`fastboot oem unlock` or a bootloader flash.
