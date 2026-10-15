<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — stage 2 ramoops at OxygenOS's address: nothing came through

**Goal.** Get stage 2's kernel log without USB. Put a `ramoops` node in
stage 2's DTB at the address and layout OxygenOS's ramoops uses, so
that after stage 2's reset OxygenOS shows our console log in
`/sys/fs/pstore`
([2026-10-15-fastboot-boot-kexec-ssh.md](2026-10-15-fastboot-boot-kexec-ssh.md),
Learning). Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 1 `6.16.0-gf71c365a86e2` (`out-dodge-rdinit`),
stage 2 the `out-dodge` `Image`, `dodge-try` initramfs.
**Result.** Fail. Stage 2 ran as before (OxygenOS at 136 s, no USB),
and OxygenOS's `/sys/fs/pstore` was empty.

## What we did

OxygenOS, as root, before the try:
`/sys/module/ramoops/parameters` gave `mem_address` 36507222016
(0x880000000), `mem_size` 0x240000, `record_size` 0, `console_size`
0x40000, `pmsg_size` 0x200000, `ftrace_size` 0, `ecc` 0, `mem_type` 0.
`/sys/fs/pstore` was empty.

One change from the previous try, in stage 2's DTB, under
`/reserved-memory` (2 address cells, 2 size cells):

```dts
ramoops@880000000 {
	compatible = "ramoops";
	reg = <0x08 0x80000000 0x00 0x240000>;
	record-size = <0x00>;
	console-size = <0x40000>;
	ftrace-size = <0x00>;
	pmsg-size = <0x200000>;
	ecc-size = <0x00>;
	no-map;
};
```

No reserved region in our DTB overlaps it, and 0x880000000 starts a
range of the live memory map that stage 2's DTB already carries. With
record and ftrace sizes 0, ramoops puts the console zone at the start
of the region, which is where OxygenOS's identical parameters put it.
`PSTORE`, `PSTORE_RAM`, `PSTORE_CONSOLE` and `PSTORE_PMSG` are `=y`.
`dtc -s` against the `boot-ids` DTB differs in the `memory` `reg`
(as before) and this node only.

`~/android/mainline/out-dodge-rdinit/images/boot-v4-kexec-ramoops.img`,
58339328 bytes, sha256
`9dc32403d619478c3e5f5d9c7199f27180901d09c5eccca6811a83178eff54df`.
Embedded DTB and initrd checked against their sources with `cmp`.
`adb reboot bootloader`, fastboot in 12 s, slot `a`, product `sun`,
`fastboot boot`.

## What happened

| t after `Booting OKAY` | USB |
| --- | --- |
| 0 s | `18d1:d00d` (fastboot) |
| 1 s | nothing |
| 136 s | `22d9:2769`, adb |

No `1d6b:0104`, no laptop address. OxygenOS: slot `_a`, `magiskd`,
uptime 14 s after adb appeared. `/sys/fs/pstore` empty. Its `dmesg`:

```text
printk: console [ramoops-1] enabled
pstore: Registered ramoops as persistent store backend
ramoops: using 0x240000@0x880000000, ecc: 0
```

Same address as before the try. `qcom_dynamic_ramoops` is among the
loaded modules. `ro.boot.bootreason` read `bootloader` again.

## Learning

136 s against 137 s: the no-UDC path again, so the boot is repeatable.

OxygenOS looked at the right address and found no record. Either stage
2 did not leave one there that survived the reset, or this phone does
not keep that RAM across a reset unless something asks for it.
`qcom_dynamic_ramoops` suggests the second: Qualcomm's dynamic ramoops
tells the boot firmware which region to keep, and our kernel never
does. A plain `adb reboot` of OxygenOS answers it: if OxygenOS cannot
read its own previous console after that, ramoops is not a log path
for us on this firmware.
