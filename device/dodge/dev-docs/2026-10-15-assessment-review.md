<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — review of the parked OnePlus 13 assessment

**Goal.** Read the approach already in the repo and decide what the
working plan should keep.
**Phone.** None in this session. No capture, no flash.
**Kernel.** None of ours.
**Result.** The port is on. The assessment stays as a dated snapshot.
The working plan is [../PLAN.md](../PLAN.md). Where this entry says
"slot A is the way back", read
[2026-10-15-plan-review.md](2026-10-15-plan-review.md) §1 and §4: the goal
changed the same day, and the way back is now OxygenOS plus `adb reboot
bootloader`.

## What we did

Read [ONEPLUS-13-ASSESSMENT.md](../../../ONEPLUS-13-ASSESSMENT.md) against
the current tree: [CONTRIBUTING.md](../../../CONTRIBUTING.md) §3 and §5,
[docs/DEVICES.md](../../../docs/DEVICES.md),
[docs/RELEASES.md](../../../docs/RELEASES.md) §3,
[device/cheetah/device.conf](../../cheetah/device.conf),
[kernel/configs/omamobile.config](../../../kernel/configs/omamobile.config),
and the top of [device/cheetah/BRINGUP-M1.md](../../cheetah/BRINGUP-M1.md).

Then checked public SM8750 status so the plan would not repeat "mainline
is early" without looking. Sources are listed in the plan, §10. The
postmarketOS wiki fetch itself was blocked by the site's bot check; the
SoC and device pages are cited from search snippets of those pages
(SoC page revision around March 2026, device page around May 2026) and
should be re-read in a browser before phase 3.

## What the assessment got right

- Omarchy Mobile is a Pixel project today. The multi-device work in
  `docs/RELEASES.md` is several Pixels on one kernel, not a second SoC
  vendor.
- dodge / SM8750 / `sun` is the right identity, and the job is a platform
  port.
- The safety instinct is right: do not flash a daily driver as the first
  experiment, do not reuse cheetah's `devmem` or DECON path, and do not
  start the Omarchy packaging until some Linux has reached a shell.
- OnePlusOSS trees are reference material. That matches how this repo
  treats Google's GPL kernel.

## What we changed our minds on

1. **Waiting on upstream is not a plan.** The assessment's approach A
   parks the work until Omarchy Mobile announces a non-Pixel SoC. Nothing
   in `docs/DEVICES.md` or `docs/ROADMAP.md` suggests that announcement.
   The goal is to add the support, so the plan is the port, with the
   community boot experiments as its second phase.

2. **Display + GPU + Wi-Fi is the wrong first gate.** Cheetah's own
   bring-up treats those as stages 4, 5 and 7, after a framebuffer and
   USB networking. SM8750 mainline already has a SoC DT and, on the
   vendor boards, display and USB. Adreno 830 support was still arriving
   as a patch series in August 2026. Holding the whole port on the GPU
   would stall it on the slowest piece. The plan boots Hyprland on the
   software renderer the repo already carries, and gives the GPU its own
   stage.

3. **The closest board is pagani, not a Pixel.** OnePlus 13s/13T is the
   same SoC with a different panel (1216x2640 against the 13's
   1440x3168) and a published mainline board port. Cheetah is the template
   for how *this repo* does a port: gated plans, a storage guard, slot A
   kept stock. It is not the template for the hardware.

4. **Mu-Silicium stays a probe.** Other people have `fastboot boot`ed
   `Mu-dodge.img` and seen the panel. The same status page shows USB host
   and the GPU down, and one dodge fork edits XBL to get host mode.
   Installing that UEFI, or patching XBL, drops the "slot A is the way
   back" property the rest of the project depends on. Phase 2 may borrow
   the temporary boot. It does not flash it.

5. **Userspace stacks do not come along for the ride.** A sentence in the
   assessment ("rewrite every Tensor-specific stage") is easy to
   under-read. The modem client, the AoC audio path, the sensor proxy and
   the GNSS chroot are Google-firmware programs. Qualcomm equivalents are
   different programs. They are named as later plans, not as ports of the
   cheetah packages.

6. **No descriptor yet.** `device.conf` can express a Pixel boot chain:
   `SOC_IDS`, a board-id dtbo, `vendor_kernel_boot`. Writing one now would
   either lie about dodge or fail `bin/omamobile`'s checks. The descriptor
   is a phase 3 deliverable, filled from the capture. Cheetah's images
   have to stay byte-identical when the tools learn a second shape.

7. **Anti-rollback is a dodge-specific hazard the assessment did not
   mention.** From January 2026, XDA reports that ColorOS 16.0.3.501 (and
   OxygenOS builds of that generation) blow a hardware fuse, after which
   an older firmware flash hard-bricks the phone and older EDL
   programmers do not recover it. Our response is the conservative one
   and does not depend on this phone's fuse state: never flash XBL, ABL,
   modem or any firmware image; never downgrade; if the two slots'
   bootloader versions differ, stop. Recovery is fastboot and slot A.

## Learning

> **Superseded 2026-10-15.** The order below (capture with the live
> device tree, then unlock, with slot A as the way back) is not the
> plan. Stock gives no root, so the live tree comes from the rooted
> capture after unlock, and the way back is OxygenOS plus `adb reboot
> bootloader`. Follow [../PLAN.md](../PLAN.md) §6 phase 1, and see
> [2026-10-15-plan-review.md](2026-10-15-plan-review.md) and
> [2026-10-15-rooted-capture.md](2026-10-15-rooted-capture.md).

The next useful work is still offline or read-only. Phase 1 is
`bin/omamobile capture dodge-cph2653` plus `fastboot getvar all`, after a
go-ahead, into `~/android/reference/`. Unlocking waits until that capture
exists, because unlock wipes `userdata` and because we want the live
device tree from the stock kernel first.

Nothing in this session claimed a row in `docs/DEVICES.md`. The matrix
gets a dodge line when a note can point at something this phone did.
