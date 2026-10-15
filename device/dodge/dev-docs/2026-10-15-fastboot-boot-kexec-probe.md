<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — pstore survives a reboot; the USB probe did not return

**Goal.** See whether OxygenOS keeps a ramoops console across a reboot,
then time-code three USB facts from stage 2. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`.
**Kernel.** Stage 1 chain-loader, stage 2 `out-dodge` image with a
small probe initramfs.
**Result.** A ramoops file appears after an OxygenOS reboot and is not
a readable log. The probe boot left fastboot and had not come back on
USB eight minutes later.

## What we did

Before a plain `adb reboot`, `/sys/fs/pstore` was empty.
`/sys/module/ramoops/parameters/mem_address` was 36507222016
(0x880000000) and `mem_size` was 2359296 (0x240000). After the reboot,
`console-ramoops-0` was 262084 bytes. A scan found the bytes `Linux`
once, inside a garbled run, not a kernel log we can read. Even and odd
bytes were not a second copy of the text.

The probe init waits 40 s, then sets v = b0 + 2·b1 + 4·b2 and sleeps
200 + 25·v seconds before `sysrq b`. b0 is `a600000.usb` existing, b1
is its `driver` link, b2 is a non-empty `/sys/class/udc`. adb was
expected near 263 + 25·v seconds after `Booting OKAY` (263, 288, 313,
338, 363, 388, 413, 438). The image is
`out-dodge-rdinit/images/boot-v4-kexec-probe.img`, sha256
`333ebda8f44a7c636e1ee148b57cba8d64168a4f7ef16e925fb68a32e9bda44d`.

## What happened

`Booting OKAY` at 20:10:29. Fastboot did not stay up. No adb and no
fastboot device for the next 480 s, and none a moment after that. The
screen stayed on the OnePlus logo and "fastboot mode". Holding Power
did not change it, and reseat had not yet been tried. The laptop still
saw no USB device at that report. A later reseat still showed no
OnePlus device on the bus. Power held about 30 s, and Volume Down plus
Power, did not change the frame. The three-key combo had not been tried.

## Learning

`reboot=warm` is not the next try: the file OxygenOS does keep is not
readable. The probe should have reset by 438 s even for v = 7. It did
not return, so either `sysrq b` did not run or the phone came back
without enumerating. Power for about 30 s, and Volume Down plus Power, left the frame
unchanged. Volume Up plus Volume Down plus Power, held together,
powered the phone off. Plugging the cable in then booted OxygenOS.
The panel had been holding the fastboot frame on its own. After that
boot: slot `_a`, `CPH2653_16.0.10.501(EX01)`, `ro.boot.flash.locked=0`,
`magiskd`. No further boot until that recovery was confirmed.
