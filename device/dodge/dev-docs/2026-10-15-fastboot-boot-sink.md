<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — stock dtbo applies to our DTB, ABL still stayed in fastboot

**Goal.** Remove the one failure we can reproduce on the laptop: stock's
`dtbo` does not apply to our DTB. Change only the DTB in `boot-ids.img`
so every `dtbo` entry applies, then `fastboot boot` it. Do not flash.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** The `boot-ids.img` kernel and initramfs, byte for byte
(`omamobile-dodge` `f71c365a8` on `16cf517b2781`). New DTB only.
**Result.** Fail. `Booting OKAY`, then 63 s in fastboot. `fastboot
reboot` restored OxygenOS. The overlay was a real failure, but not the
only thing that keeps ABL from starting a v2 image.

## What we did

Laptop, no phone. `unpack_bootimg` of `boot-ids.img` and `mkdtboimg
dump` of the OTA's `dtbo.img`, then `fdtoverlay`:

| Base | Overlay | Result |
| --- | --- | --- |
| our ids DTB | entry 3 ("Sun MTP,dodge") | `FDT_ERR_BADOFFSET`, base has no `/__symbols__` |
| stock vendor FDT (`0x26a 0x10000`, 1759 symbols) | entry 3 | applies, rc 0 |

All six entries carry our msm-id pairs and board-id `0x40008`, so ABL
matches one of them. Together they hold 1242 fragments, none with
`target-path`, and refer to 202 labels through `__fixups__` (201 in
entries 3 and 5, 200 in the T0 entries).

The DTB change: a root node `/omamobile-dtbo-sink` with one empty child
per label, and a hand-written `/__symbols__` pointing each label at its
child. The container has no `compatible`, so nothing under it is
populated. `dtc -@` was not used: it would point `tlmm`, `apps_smmu`,
`aliases` and other labels at our real nodes, and stock's downstream
properties would merge into them.

The first build still failed on all six entries with
`FDT_ERR_NOTFOUND`. libfdt resolves each fixup to the target's
phandle, and an empty stub has none. Each stub now has its own phandle,
from `0xf2` (ours end at `0xf1`). Then:

- `fdtoverlay` applied entries 0 to 5 to the sink DTB, rc 0 each.
- Each result, with `/omamobile-dtbo-sink` and `/__symbols__` removed,
  decompiles (`dtc -s`) identical to the `boot-ids` DTB.

`mkbootimg` packed `~/android/mainline/out-dodge/images/boot-sink.img`
with `boot-ids.img`'s kernel and ramdisk and the same geometry and
cmdline: header 2, 45498368 bytes, dtb 105986 bytes, sha256
`3b6946699b18e5dbec688294885312cd966929ee860299fc89c7d9ac3fa0f592`.
`unpack_bootimg` of both images differs only in dtb size.

Phone: `adb reboot bootloader`. The first attempt was lost to a press
of Start in the bootloader menu; slot A's OxygenOS came up and nothing
was sent. Second attempt: fastboot in 12 s, `current-slot` `a`,
`product` `sun`, `fastboot boot`.

## What happened

```text
Sending 'boot.img' (44432 KB)                      OKAY [  1.012s]
Booting                                            OKAY [  0.305s]
```

`18d1:d00d` was the only phone USB device at every 3 s check to 63 s.
No adb, no SSH. `fastboot reboot` brought adb back in 15 s: slot `_a`,
same build, `ro.boot.flash.locked=0`, `sys.boot_completed=1`, `magiskd`
running.

## Learning

| Image | Header | DTB | What ABL did |
| --- | --- | --- | --- |
| `boot.img` | 2 | no ids | stayed in fastboot |
| `boot-ids.img` | 2 | live ids, board-id `0x40008` | stayed in fastboot |
| `boot-sink.img` | 2 | live ids, and every `dtbo` entry applies | stayed in fastboot |
| `boot-v4-kernel.img` | 4 | none (flashed `vendor_boot`) | left fastboot, OxygenOS in 23 s |

This is §5.3 step 3. It does not show that ABL ever reached the overlay
for a v2 image. ABL's own log goes to UART, which we do not have, so a
v2 image that fails before DTB selection looks the same as one that
fails at the overlay.

The question is now whether this ABL starts any header v2 image under
`fastboot boot`, not what is in ours. A v2 image of stock's own pieces
answers that without our kernel: stock kernel, `init_boot`'s ramdisk,
the sun vendor FDT with the dodge `dtbo` entry applied on the laptop.
If that stays in fastboot too, the v2 path is closed and the cmdline
(step 4) is not worth a try. That is a proposal, not yet a decision.

To make a dtbo-compatible DTB, every symbol target needs a phandle:
`-@` labels on real nodes get one, hand-made stubs do not.
