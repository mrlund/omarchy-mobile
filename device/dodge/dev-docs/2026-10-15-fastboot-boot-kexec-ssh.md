<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — kexec into the dodge-try initramfs: no USB controller

**Goal.** Phase 3 over one `fastboot boot`: the kexec chain-loader
([2026-10-15-fastboot-boot-kexec.md](2026-10-15-fastboot-boot-kexec.md))
with `tools/dodge-try`'s initramfs as stage 2, so SSH comes up on
172.16.42.1 from our kernel on our DTB. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 1 `6.16.0-gf71c365a86e2` (`out-dodge-rdinit`),
stage 2 the `out-dodge` `Image` with the live-memory `boot-ids` DTB.
**Result.** Fail. No USB device from the phone after fastboot let go.
OxygenOS was back at 137 s, the timing of the stage 2 init's own
"USB never configured" panic with no UDC ever found.

## What we did

One change from the 60 s-hold try: stage 2's initrd is
`out-dodge/initramfs.cpio.lz4`, byte-identical to the ramdisk in
`boot-ids.img`, whose `/init` is `device/dodge/initramfs/init` as
committed. Stage 1's failure holds moved from 120/150 s to 200/230 s so
they cannot be mistaken for that init's fallback. Stage 2 command line
unchanged: `rdinit=/init clk_ignore_unused pd_ignore_unused panic=10
console=tty0`.

`~/android/mainline/out-dodge-rdinit/images/boot-v4-kexec-ssh.img`,
58339328 bytes, sha256
`6d496bf073b5d86ed0b6be57520285b1de820e97b9743d8a475633b6496728cc`.
`adb reboot bootloader`, fastboot in 12 s, slot `a`, product `sun`,
`fastboot boot`. The laptop polled every second for `1d6b:0104`, the
`omamobile-phone` address, SSH and adb.

## What happened

```text
Sending 'boot.img' (56972 KB)                      OKAY [  1.297s]
Booting                                            OKAY [  0.378s]
```

| t after `Booting OKAY` | USB | laptop 172.16.42.2 |
| --- | --- | --- |
| 0 s | `18d1:d00d` (fastboot) | no |
| 2 s | nothing | no |
| 137 s | `22d9:2769`, adb | no |

`1d6b:0104` never appeared. OxygenOS came back on slot `_a`, same
build, `magiskd` running. The screen kept the fastboot frame
throughout, as on the earlier tries (watched by hand).

## Learning

The init's timeline after stage 2 starts (about 10 s after `Booting
OKAY`, from the earlier tries): up to 30 s for a UDC, up to 10 s for
`usb0`, 45 s for `configured`, 20 s, then `sysrq c` and `panic=10`.

| Path | Reset at | adb at |
| --- | --- | --- |
| no UDC in 30 s | about 125 s | about 138 s |
| UDC bound, host never configures | about 95 s | about 108 s |
| stage 2 panics before init | about 20 s | about 35 s |

137 s fits the first row, [I]: stage 2 ran our init, and no USB
device controller registered in 30 s. The 200/230 s stage 1 bands rule
out a kexec failure.

Static checks found nothing missing: `SPMI_MSM_PMIC_ARB`,
`REGULATOR_QCOM_RPMH`, `PHY_QCOM_M31_EUSB`, `PHY_QCOM_EUSB2_REPEATER`,
`PHY_QCOM_QMP_COMBO`, `USB_DWC3_QCOM` and `USB_ROLE_SWITCH` are all
`=y`. `usb_1_dwc3` is `dr_mode = "otg"` with `usb-role-switch`, and
its role comes from `pmic_glink`, which is `=m` and needs the ADSP; this
initramfs loads no modules. Which of those holds the controller back
needs the kernel log, not more timing.

A log path with no USB, [I]: OxygenOS's ramoops reads its region at
`mem_address` 0x880000000 (`/sys/module/ramoops/parameters`, read as
root: size 0x240000, console 0x40000, pmsg 0x200000, record 0, ftrace
0, ecc 0). The live memory map's range starting at 0x880000000 is in
stage 2's DTB. A `ramoops` node in stage 2's DTB at that address with
the same sizes lays its console zone out where OxygenOS looks, so if
DRAM survives the reset, OxygenOS's `/sys/fs/pstore` would show stage
2's kmsg.
