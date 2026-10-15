<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — OSS firmware around the OnePlus 13

**Goal.** Find bootloaders, kernels and images other people already run
on dodge, and pick the one that gives a fast, recoverable loop.
**Phone.** Named, not attached. CPH2653, 16 GiB / 512 GB, hardware
CPH2653_11, baseband Q_V1_P14, SOTA B100P01(BRB1GDPR).
**Kernel.** None of ours.
**Result.** Useful pieces: `fastboot boot` over the USB cable, and
`sm8750-mainline`'s dodge DTB. The USB stick in his write-up is his
workaround, not our loop. Superseded on that point by
[2026-10-15-cable-not-stick.md](2026-10-15-cable-not-stick.md).

## What we did

Searched for dodge / CPH2653 / SM8750 Linux, UEFI and custom-ROM work, and
read the install and status pages far enough to see which partitions each
project writes. The postmarketOS wiki itself is behind a bot check, so
that device page is from search snippets of the May 2026 revision and
should be opened in a browser before we trust a feature cell.

The goal changed in the same conversation. Brick avoidance stays. Keeping
OxygenOS, and keeping the data on the phone, does not. The plan was
rewritten to match: [../PLAN.md](../PLAN.md).

## What is actually usable

### Temporary UEFI, then a kernel on a stick

Daniel Abrecht, XDA "My attempts to boot linux" (November 2025), on a
CPH2653. This is the only published end-to-end Linux desktop on this
model that names its commands.

- `fastboot boot Mu-dodge.img` (Mu-Silicium 3.0.9) showed a debug console
  and did not flash.
- A later `fastboot boot` of an Android-packed mainline kernel
  (`sm8750-mainline` v6.16, dtb `qcom/sm8750-oneplus-dodge.dtb`) hung.
  `fastboot reboot` from the laptop cleared it. So `fastboot boot` can
  stick, and the laptop can still unstick it, as long as the bootloader
  itself was not replaced.
- USB host is missing in upstream Mu. His branch
  `Daniel-Abrecht/Mu-Silicium` `dodge-host-mode`, commit `577cf37`,
  tested on firmware `CPH2653_16.0.2.402`, boots a USB stick through a
  powered hub. The phone does not power the stick. He booted Devuan with
  Plasma Mobile that way, and wrote that he flashed nothing.
- He also got Mu's USB mass-storage gadget up, after disabling a host
  udev rule that modeswitches vendor `05c6` product `f000`.

Mu-Silicium's own status page (`Platforms/OnePlus/dodgePkg`) marks Linux
boot, display, internal storage, buttons and USB device mode working, and
USB host, GPU and WLAN not. Project state: inactive. We use the image as
a temporary bootloader. We do not install it.

His firmware is `16.0.2.402`. This phone reports SOTA `B100P01(BRB1GDPR)`,
which is the August 2026 OxygenOS 16 EU update, so it is almost certainly
a newer bootloader. Phase 2 re-tests `fastboot boot`. It does not assume
his image still matches.

### A dodge mainline tree with a board DTB

`github.com/sm8750-mainline/linux`, branch `v6.16`, is the tree Abrecht
built, and the dtb path in his `mkbootimg` line is
`qcom/sm8750-oneplus-dodge.dtb`. That is the kernel checkout to try first.
Packing it as an Android boot image was the path that hung. Feeding it to
GRUB from the stick was the path that reached a session.

Upstream Linus has `sm8750.dtsi` and the MTP and QRD boards, not a dodge
board. Adreno 830 DRM support was a patch series in August 2026 (Akhil P
Oommen / Jie Zhang), with zap firmware `qcom/sm8750/gen80000_zap.mbn`.

### LineageOS, for the partition map and the key combo

`wiki.lineageos.org/devices/dodge` lists official support for CPH2649,
CPH2653, CPH2655 and PJZ110. Kernel 6.6. The install page flashes:

```text
boot, dtbo, init_boot, vbmeta, vendor_boot, recovery
```

No `vendor_kernel_boot`. Fastboot from power-off is Volume Up + Volume
Down + Power. Their kernel tree
(`LineageOS/android_kernel_oneplus_sm8750`, and ItsVixano's trees) is a
downstream reference. ItsVixano is both a Lineage dodge maintainer and
named on the postmarketOS dodge page.

We do not flash their `vbmeta` as part of the fast loop. Abrecht never
needed to. We do not install Lineage. It would replace the OS with
Android, which is a slow detour, and their `vbmeta` is the one partition
in that list we do not yet understand.

### Vendor GPL trees

OnePlusOSS, branches `oneplus/sm8750_b_16.0.0_oneplus_13` and the matching
common and modules/DT repos. Commits are tagged with the build they match,
including `CPH2653_16.0.3.501`, `16.0.5.703`, `16.0.8.301` and
`16.0.9.401` (July 2026). Read these for the board DT. Do not compile
them as the kernel we iterate. A GKI build is the slow loop, and flashing
it is how `super` gets broken.

### The sibling phone

`renhiyama/pagani-linux` commit `c49d202` is a real mainline port of the
OnePlus 13s/13T: DSC command-mode panel driver, Synaptics touch, ath12k
on WCN7880. Panel is 1216x2640. Use the shape of the driver. Leave the
timings and the GPIOs.

### postmarketOS's report

The dodge page says the device has been booted (the photo is KDE Plasma
on Arch Linux ARM) and is not packaged. Reported working: USB networking,
internal storage, screen, touch, camera flash. Battery reads 0% and still
charges. Wi-Fi, Bluetooth, audio, modem, GPS, NFC and 3D are untested
there. Contributors named on the page include Index986 (a 16/512 daily
driver, model unstated) and ItsVixano. The SoC page is more optimistic
than the device page, and it describes Qualcomm's reference boards as
much as this phone.

Arch on the screen is the interesting part. It means the userspace we
want has already run, on somebody's dodge, on the UEFI path rather than
through Omarchy's installer.

## What we will not use as a method

- Android custom kernels (OPlus Kernel Lab, ReSukiSU, susfs builds).
  They boot OxygenOS or Lineage. They do not teach a mainline userspace,
  and they are flashed.
- `spiral009/dodge-dualboot`. It is a working dual-boot of AOSP and
  ColorOS, and its own guide says it writes `abl`, `tz`, `modem` and
  `dsp` per slot, and that an ARB mismatch bricks the slot. On dodge it
  records `16.0.2.x` as ARB index 0. That is a map of the hazard, not a
  procedure we run.
- EDL / "stock ROM" download sites, and guides that recover fastboot by
  flashing `abl.img` from another build. That is a bootloader write on
  the wrong side of the fuse.
- Emptying `vbmeta` because a forum post says it unlocks boot images.
  `fastboot boot` already works without it on this model.

## Learning

What we keep from his write-up is `fastboot boot` over the cable, and the
dodge DTB in `sm8750-mainline`. The stick and the powered hub were how he
got past a hung boot image by turning the phone into a USB host. This
machine already holds the other end of the cable, so the laptop sends the
image and, once the gadget is up, SSHs over it. That correction is
[2026-10-15-cable-not-stick.md](2026-10-15-cable-not-stick.md).

Flashing starts only after `fastboot boot` of our own kernel has printed
a banner and returned the cable to fastboot.

OxygenOS being expendable does not move the brick line. It means we may
wipe `userdata` and, later, both slots' boot images. It does not mean we
may write XBL or ABL.

Next session on the phone, after a go-ahead: `fastboot getvar all`, note
the build id beside `B100P01(BRB1GDPR)`, then unlock, then `fastboot boot`
of a Mu image and confirm a cold boot still reaches fastboot.

> **Superseded 2026-10-15** on the next steps. The first `fastboot boot`
> is stock's own `boot.img` from the OTA, and Mu is a fallback console
> only. "Both slots' boot images" is also withdrawn: the active slot
> only ([../PLAN.md](../PLAN.md) §3.3). Follow the plan's §6, and see
> [2026-10-15-plan-review.md](2026-10-15-plan-review.md).
