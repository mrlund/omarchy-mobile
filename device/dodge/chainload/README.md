<!-- SPDX-License-Identifier: MIT -->
# dodge kexec chain-loader

How we start our own kernel, DTB and initramfs on the OnePlus 13 with
one `fastboot boot` and no flash. The why is in
[../PLAN.md](../PLAN.md) §5.3 and the dev-docs of 2026-10-15.

## How it boots

1. ABL starts a kernel-only header v4 `boot.img` (it refuses header v2,
   and it ignores a ramdisk in the uploaded v4 image). It hands that
   kernel stock's DTB from the flashed `vendor_boot` and unpacks
   `vendor_boot`'s and Magisk's `init_boot` ramdisks.
2. Stage 1 is our kernel with `CONFIG_CMDLINE_FORCE`
   `rdinit=/omamobile/init panic=10` and a built-in initramfs. The
   kernel unpacks the built-in one first and ABL's over it, so
   everything of ours lives under `/omamobile/`.
3. [init](init) runs `kexec -l --dtb` (the `kexec_load` path;
   `kexec_file_load` cannot change the DTB on arm64) and `kexec -e`.
4. Stage 2 is our kernel on our DTB with our initramfs, by default
   `tools/dodge-try`'s.

[stage2-dtb.py](stage2-dtb.py) makes stage 2's DTB: the dodge DTB with
the phone's own memory map in `memory` (ABL fills that node, kexec does
not), plus `ramoops`, `fb`, or `peripheral` if asked. `peripheral` sets
the dwc3 node to `dr_mode = "peripheral"` and drops `usb-role-switch`.

```sh
tools/dodge-try pack                    # stage 2: Image, DTB, initramfs in out-dodge
tools/dodge-chain pack                  # out-dodge-chain/images/boot-chain.img
# phone in fastboot, human's go:
tools/dodge-chain boot                  # pack, fastboot boot, timeline
```

Variables: `STAGE2_INITRD`, `STAGE2_CMDLINE`, `DTB_OPTS`, `CHAIN_OUT`,
`LIVE_DTB` (the rooted capture's live FDT, never committed). The first
`pack` in a fresh `CHAIN_OUT` builds a whole kernel.

## Reading the result

There is no log yet. Every try ends with a reset into OxygenOS, and the
time from `Booting OKAY` to adb says where it stopped. OxygenOS takes
about 13 s from a reset to adb. Measured on 2026-10-15:

| adb after `Booting OKAY` | Meaning |
| --- | --- |
| stays in fastboot | ABL refused the image (header v2, or something new) |
| about 12 s | ABL ran the stock kernel or ignored ours |
| about 23 s | our kernel started without our init and panicked |
| about 35 s | stage 2 panicked before its init |
| 63 / 82 / 108 s | a stage 1 or 2 hold of 45 / 60 / 90 s ran out (tries passed) |
| about 108 s | dodge-try init: a UDC bound, the host never configured it |
| **136-137 s** | dodge-try init: **no UDC in 30 s**, its panic fallback (seen 3 times) |
| about 218 s | stage 1: `kexec -e` returned |
| about 248 s | stage 1: `kexec -l` failed |
| never | a hang without panic: the human holds Power about 30 s |

A new stage 2 init must keep its own bands clear of these.

## Handoff: next steps (written 2026-10-16)

State: stage 2 runs our init on our DTB, and USB never registers a
device controller. Tried and closed, do not repeat as the next boot:

- ramoops at 0x880000000: OxygenOS pstore stayed empty after that boot.
  A later plain reboot does leave `console-ramoops-0`, and the bytes
  are not a readable log.
- simple-framebuffer on the splash: command-mode panel did not change.
- `peripheral` alone, then HS-only plus peripheral, then that plus no
  dwc3 `iommus`: all no gadget, OxygenOS back at 125–137 s.
- timing probes that stat `a600000.usb`: did not return on USB. Recovery
  was Volume Up + Volume Down + Power (powers off), then plug in the
  cable. Do not boot those inits unless someone is there.

One change per boot, the human's go before each `fastboot boot`, a
dev-docs entry after each. Nothing is flashed. The init that only
sleeps and writes sysrq does return. The open question is why the glue
never publishes a gadget, without reading those USB sysfs nodes from
stage 2.

Once SSH answers: `dmesg` into `logs/`, quote the USB lines in the
dev-doc after checking them for identifiers.
