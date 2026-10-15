<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — review of the working plan and the iteration setup

**Goal.** Read [../PLAN.md](../PLAN.md) and the other entries here against
the tools the plan wants to reuse, and find what would break or slow the
first sessions on the phone.
**Phone.** Not attached. CPH2653, as in the plan.
**Kernel.** None of ours.
**Result.** The loop's recovery path was wrong for a kernel hang, two
phase 1 steps cannot be done as written, and this machine has none of the
host setup yet. The plan was updated the same day.

## What we did

Read the plan, the three earlier entries and the assessment. Read
`bin/omamobile` (`capture`, `kernel`, `initramfs`, `images`, `fastboot`),
`tools/phone-ssh`, `omamobile.conf`, `device/cheetah/device.conf`,
`device/cheetah/initramfs/init` and the boot-chain part of
`device/cheetah/BRINGUP-M1.md`. Checked the host for the tools the loop
needs. Nothing touched a phone.

## What we found

### 1. A hung kernel cannot be cleared from the laptop

The plan said a failed kernel costs one reboot and that the laptop sends
`fastboot reboot`. That only works while ABL is still running. Abrecht's
`fastboot reboot` cleared a hang in the bootloader's handling of the
image, before a kernel ran. Once our kernel runs and hangs, nothing on
the cable is listening.

Two more facts make it worse. `fastboot boot` is one-shot, so a reset
boots the slot's normal image, not fastboot. And without a watchdog, a
hang just sits there until a human holds the buttons.

The fix is a self-reset plus a way back to fastboot that needs no hands:

- the kernel resets itself: `QCOM_WDT`, `panic=10`, panic on soft lockup
  and hung task;
- the initramfs crashes itself if the USB gadget is never configured
  (cheetah's init already does this, `device/cheetah/initramfs/init`,
  "Self-recovery for bring-up");
- the reset lands in OxygenOS, set up once after unlock with USB
  debugging on and this laptop authorized, and `adb reboot bootloader`
  brings the cable back to fastboot. `bin/omamobile fastboot` already
  does exactly that step.

So OxygenOS's *data* is expendable, but a bootable OxygenOS on the active
slot is the return path of the loop. The plan had said the opposite.

### 2. Abrecht's hang has likely causes we can try one at a time

[I] throughout. On a GKI phone with a header v4 boot image, Qualcomm ABL
combines the uploaded `boot.img` with the *flashed* `vendor_boot`, takes
the DTB from there, and applies `dtbo` on top. A mainline kernel then
starts on stock's downstream DTB, or ABL refuses the merge. Either looks
like a hang.

One `fastboot boot` per item:

1. A header v2 image with `--dtb`, carrying the mainline dodge DTB.
2. `qcom,msm-id` and `qcom,board-id` in the dodge DTS matching stock's.
   ABL selects the DTB by these; this is the Qualcomm form of cheetah's
   `soc_id` gotcha.
3. What ABL does when the stock `dtbo` does not apply to our DTB.
4. The command line ABL appends (`console=`, `androidboot.*`).

### 3. The first `fastboot boot` should be stock's own boot image

`fastboot boot` of this firmware's stock `boot.img` should simply boot
OxygenOS. It proves `fastboot boot` still works, and is still temporary,
on the August 2026 firmware, at essentially no risk. Mu-Silicium and our
kernel come after.

### 4. Switching slots is an anti-rollback hazard

An A/B OTA leaves the older firmware on the inactive slot. If this unit's
fuse has blown, `set_active` to that slot may hard-brick it [I]. The plan
had "both slots can carry our boot images later". New rules: never
`set_active` and never flash the other slot until both slots' firmware is
known to match, and switch off automatic system updates in OxygenOS
right after unlock so an OTA cannot move the bootloader mid-project.

`fastboot getvar version-bootloader` usually reports the current slot
only [I], so "the two slots' bootloaders differ" is not something phase 1
can check by itself.

### 5. Two phase 1 steps cannot be done as written

- **Dumping the boot images "from the phone".** Stock OxygenOS has no
  root, and Qualcomm ABL generally has no `fastboot fetch` [I].
- **The live FDT "if adb is available".** `bin/omamobile capture` reads
  `/sys/firmware/fdt` only with root.

Both come from the OTA instead. The full OTA `payload.bin` for this exact
build holds `boot`, `init_boot`, `vendor_boot`, `dtbo` and `vbmeta`.
Extracting it offline (payload-dumper, output under `~/android/reference/`)
answers most of the plan's open list before anyone touches the phone:
header version and page size, vendor cmdline, msm-id / board-id, the dtbo
entries, the panel compatible, the Wi-Fi chip, reserved memory including
the continuous-splash framebuffer (for `simple-framebuffer`) and a
ramoops region (for pstore after a reset). The build id comes from
Settings, About, read by the human: no `getvar` needed.

The firmware images in the payload are vendor blobs. They stay off-repo.

### 6. The host is not set up

| Missing | Why it matters |
| --- | --- |
| `fastboot`, `adb`, `dtc` | Not installed |
| udev access for OnePlus (`22d9`) and fastboot (`18d1:d00d`) | Otherwise fastboot needs root |
| Docker access | The user is not in the `docker` group; `bin/omamobile kernel` builds in a container |
| `mkbootimg` and clang | `bin/omamobile` takes both from the LineageOS tree (`SRC_DIR`, about 400 GB). The dodge loop should not need that tree. System clang is present |
| NetworkManager profile `omamobile-phone` (172.16.42.2/24) | `tools/phone-ssh` assumes it |

### 7. `bin/omamobile` is Pixel-shaped

`kernel` hard-codes `omamobile.config` and lists `dts/exynos/google`,
`initramfs` builds `reboot-to` from the device package, and `images` is
cheetah's v4 / `vendor_kernel_boot` layout. That matches the plan's "no
descriptor yet", but it means the loop needs its own small script now
(`tools/dodge-try`): build, pack, `fastboot boot`, wait for SSH with a
timeout, save kmsg to `logs/`, append a row to a tries log. It folds into
`bin/omamobile` at phase 4.

The first kernel config should build in everything the loop needs:
dwc3-qcom and the SM8750 USB PHYs, configfs NCM and ACM, simplefb,
pstore/ramoops, the watchdog. With `clk_ignore_unused` and
`pd_ignore_unused` on the command line, the initramfs needs no modules.

### 8. Documentation

- `AGENTS.md` §1 is written for the Pixel ("only slot B is ours",
  `UFS_RW`). An agent working on dodge would apply it or trip over it.
  The plan now says which rules bind here.
- The capture directory had three names. It is now
  `~/android/reference/dodge-cph2653/`.
- [2026-10-15-assessment-review.md](2026-10-15-assessment-review.md)
  pointed at a plan §12 that does not exist, and still said "slot A is
  the way back" from the superseded goal.

## Learning

The pattern behind items 1, 4 and 5: the plan inherited Pixel
assumptions in places it had already said it was leaving them. Cheetah
has a stock slot A that ABL falls back to, a root-capable stock capture,
and tools that know its images. Dodge has none of those yet. Each place
the plan leans on one needs a dodge answer written down.

The plan changes are in [../PLAN.md](../PLAN.md): §3.2, §3.3 and §3.4 (new; the old
§3.3 is now §3.5), §5.1 to §5.5, §6 phases 0 to 2, §7 and §9. The next work is still
offline: host setup, the OTA extraction, the kernel build, then
`tools/dodge-try`.
