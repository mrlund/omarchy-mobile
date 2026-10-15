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
not), plus `ramoops` or `fb` if asked.

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

## Handoff: next steps (written 2026-10-15)

State: stage 2 runs our init on our DTB, and USB never registers a
device controller. Two log paths without USB showed nothing:
ramoops at OxygenOS's address, and a simple-framebuffer on the
command-mode panel. One change per boot, the human's go before each
`fastboot boot`, a dev-docs entry and a `logs/dodge-tries.tsv` row
after each. Nothing is flashed; stage 1 stays as it is.

1. **Does OxygenOS keep its own pstore across a plain reboot?** As
   root, `ls /sys/fs/pstore` after a plain `adb reboot` (a reboot: ask
   first). Stock loads `qcom_dynamic_ramoops` and found nothing after
   our resets. If `console-ramoops-0` is there, go to 2; if not, skip
   to 3.
2. **Stage 2 reset as a warm reset.** `DTB_OPTS=ramoops` and
   `STAGE2_CMDLINE` plus `reboot=warm`, which makes arm64 use PSCI
   `SYSTEM_RESET2` warm reset where firmware supports it. Pass:
   OxygenOS's `/sys/fs/pstore/console-ramoops-0` holds stage 2's
   kernel log. Read the USB lines from it and go to 4.
3. **A timing-coded USB probe as stage 2's init.** Replace
   `STAGE2_INITRD` with a small cpio whose `/init` mounts `proc`,
   `sysfs` and `debugfs`, waits 40 s, reads three facts and holds
   `20 + 15 × v` s before `echo b > /proc/sysrq-trigger`, where
   v = b0 + 2·b1 + 4·b2:
   - b0: the dwc3 core device `/sys/bus/platform/devices/a600000.usb`
     exists (the qcom glue `a6f8800.usb` probed);
   - b1: it has a `driver` link (dwc3 bound);
   - b2: `/sys/class/udc` is not empty.
   adb then lands at about 83 + 15 × v s (83 to 188 s), clear of the
   other bands. Second run, same scheme: whether
   `/sys/kernel/debug/devices_deferred` names `a6f8800.usb`, the HS PHY
   (`88e3000.phy`), the QMP PHY (`88e8000.phy`), or the PMIC eUSB2
   repeater (`phy@fd00` under the pmih0108 SPMI node). Check the device
   names in sysfs format against the built DTB before trusting a bit.
4. **The fix the facts point to**, one per boot, as a
   `stage2-dtb.py` option:
   - dwc3 bound but no UDC: `usb_1_dwc3` to `dr_mode = "peripheral"`
     without `usb-role-switch`. Its role comes from `pmic_glink`,
     which is `=m`, needs the ADSP, and is never loaded here.
   - dwc3 unbound: the PHY or repeater that `devices_deferred` names
     (supplies, SPMI, `apps_smmu` after kexec).
   - glue not probed: its clocks, GDSC, interconnects or
     `required-opps`.
5. **Once SSH answers:** `dmesg` into `logs/`, quote the USB lines in
   the dev-doc (check them for identifiers), then let
   `tools/dodge-try` build the chain image so phase 3's loop is one
   command.
