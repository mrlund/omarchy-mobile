<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — short USB probe also did not return

**Goal.** Same three USB facts, with a shorter hold and a panic if the
reboot request is ignored. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked.
**Kernel.** Stage 1 chain-loader. Stage 2 `out-dodge` image, probe
initramfs.
**Result.** Fail. No USB device for 280 s after `Booting OKAY`.

## What we did

The init waits 20 s, encodes v = b0 + 2·b1 + 4·b2, sleeps 25 + 15·v
seconds, writes `b` then `c` to sysrq. A background sleep of 210 s
writes `c` as well. `panic=10` is on the stage 2 command line. The
image is `out-dodge-rdinit/images/boot-v4-kexec-probe2.img`, sha256
`8c760ba2112a7a5e973964d5ff9d8199d1fcc3730211363d9e555f70604cf306`.
`Booting OKAY` at 20:33:27.

## What happened

No adb and no fastboot for the next 280 s. The panic backup should
have reset the phone inside that window even if the timed sleep never
finished. It did not show up on USB.

## Learning

`sysrq b` and a later panic are not a reliable way back from stage 2
on this boot. The three-key hold (Volume Up, Volume Down, Power) is
what powered the phone off after the previous probe. Do not send
another `fastboot boot` until the phone is on the cable again.
