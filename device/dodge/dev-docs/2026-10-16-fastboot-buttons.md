<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — Volume Down and Power reach fastboot

**Goal.** Phase 3.5 gate 2: from a powered-off phone, with the cable in,
reach fastboot without OxygenOS starting.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Result.** Pass. Volume Down held through the power-off, then Power
added. Fastboot (`product: sun`, slot `a`) about 12 s after the phone
left the cable. adb did not come up.

## What we did

The phone was in OxygenOS with the screen off. The human held Volume
Down. `adb shell reboot -p` ran at 12:38:57. USB dropped at once. The
human then held Power as well, still holding Volume Down. Fastboot
answered at 12:39:09.

## What happened earlier in the same drill

Two tries booted OxygenOS. The phone was powered off (three-key combo,
then `adb shell reboot -p`) and Volume Down + Power was pressed only
after the screen was already black. The cable started a normal boot
before the keys were down. That boot shows the orange-state warning, a
logo that is not the OnePlus mark, a charging icon, then a black
screen, with adb on `22d9:2769`. The black screen was OxygenOS asleep,
not powered off.

On 2026-10-15, Volume Down + Power did nothing while the SoC was hung
behind a stuck fastboot frame. Volume Up + Volume Down + Power powered
that hung phone off. This drill did not repeat the hang. It found the
combo from a real power-off.

## Learning

From a phone that is actually off, with the cable in: hold Volume Down
first, then hold Power, and keep Volume Down down the whole time. The
cable will otherwise start OxygenOS. For a hang, power off with Volume
Up + Volume Down + Power, then use this combo. The phone was left in
fastboot.
