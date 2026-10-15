<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge, SM8750) — working plan

Status 2026-10-15: plan revised after the device was named. The loop is
one USB cable to this machine (`fastboot boot`, then SSH). A USB stick is
not part of it. Nothing has been run on the phone.
No `device.conf`. The first initramfs is
[`initramfs/init`](initramfs/init). It is packed and has not been booted.
The kernel checkout is `~/android/mainline/wt-dodge`, branch
`omamobile-dodge`. Attempts go in
[dev-docs/](dev-docs/). The OSS survey is
[dev-docs/2026-10-15-oss-landscape.md](dev-docs/2026-10-15-oss-landscape.md).
Revised again the same day after
[dev-docs/2026-10-15-plan-review.md](dev-docs/2026-10-15-plan-review.md):
the way back after a kernel hang, the OTA as the source of stock images,
slot rules, and the host setup. Phase 1 now ends with a rooted capture of
OxygenOS through Magisk, instead of a downstream-kernel track:
[dev-docs/2026-10-15-rooted-capture.md](dev-docs/2026-10-15-rooted-capture.md).
A second review tightened the image format, the OTA, the watchdog and the
Magisk fallback:
[dev-docs/2026-10-15-second-review.md](dev-docs/2026-10-15-second-review.md).
Phase 0a (host), phase 0b (stock images) and phase 0c (the mainline
DTB) are done on the laptop. The phone has not been unlocked, rooted,
rebooted or flashed. The OTA facts are in
[dev-docs/2026-10-15-ota-boot-images.md](dev-docs/2026-10-15-ota-boot-images.md).
The DTB comparison is in
[dev-docs/2026-10-15-mainline-dtb.md](dev-docs/2026-10-15-mainline-dtb.md).
Phase 0d (the loop script, the initramfs and a packed header v2 image)
is done on the laptop. The image has not been handed to fastboot:
[dev-docs/2026-10-15-dodge-try.md](dev-docs/2026-10-15-dodge-try.md).
Phase 0e downloaded Magisk 30.7 and taught `bin/omamobile capture` the
`su -c` path. The APK is not installed:
[dev-docs/2026-10-15-magisk-capture.md](dev-docs/2026-10-15-magisk-capture.md).

Labels: **[V]** checked in a source we can cite. **[I]** an inference, to
be checked on this phone before anyone relies on it. A community report is
[V] for "someone published this", and still [I] for our phone.

## 1. Goal

Run Omarchy (Arch Linux ARM, Hyprland, Omarchy's packages) on this
OnePlus 13, on a mainline kernel.

The phone is a lab device. Its OxygenOS install and its data are
expendable. Unlocking wipes it, and that cost is accepted.

The failure we cannot absorb is a hard brick: a phone that no longer
enumerates in fastboot and no longer reaches a bootloader menu. That ends
the project. Every other failure is a reboot and another try.

"Done" still arrives in pieces. The first piece is a shell we can reach
again in minutes. A desk session (display, touch, Omarchy) comes after
the loop is fast. Calls, cameras and fingerprint stay later plans.

## 2. The phone

| | |
| --- | --- |
| Model | CPH2653 (Global / EU OxygenOS) |
| RAM / storage | 16 GiB / 512 GB |
| Hardware version | CPH2653_11 |
| Baseband | Q_V1_P14 |
| SOTA | B100P01(BRB1GDPR) |
| OxygenOS | `CPH2653_16.0.10.501(EX01)` |
| Package | `CPH2653EEA`, `CPH2653_11.F.93_2930_202608071055` |
| Security patch | 2026-08-01 |
| Codename | `dodge` |
| SoC | Qualcomm SM8750, Snapdragon 8 Elite (`sun` / Pakala), Adreno 830, Oryon |

`B100P01(BRB1GDPR)` is the August 2026 OxygenOS 16 SOTA track for the EU
build, not the full firmware id. [V] for what that string means in
OnePlus's announcement and in older GDPR SOTAs (`V60P01(BRB1GDPR)` and
the like). Settings, About shows
`CPH2653_16.0.10.501(EX01B100P01)`: the firmware id with the SOTA suffix
appended. The OTA's `version_name` is `CPH2653_16.0.10.501(EX01)`,
product `CPH2653EEA`, device `OP5D55L1`, ota version
`CPH2653_11.F.93_2930_202608071055`, Android 16. [V] the human read
About, and the zip metadata and the `boot.img` Linux version
(`6.6.118-android15-8-g2e6b9c3812c5-ab15114928-4k`) match that build.
The catalog name is `CPH2653_11.F.93_…`. The earlier guess
`CPH2653GDPR_11_…` does not appear in this package. `EX01` is the tag on
the EU catalog's version strings. A later EU package,
`CPH2653_16.0.10.600(EX01)` (`F.94`, September 2026 patch), was the
catalog's latest on 2026-10-15 and was left unused. Hardware
`CPH2653_11` matches the `CPH2653_11.F.93` ota version. Anti-rollback
follows the firmware security version, so the SOTA string alone does not
tell us the fuse state. The fuse state of this unit is still [I].

OnePlus 13R and OnePlus 13s/13T (`pagani`) are different phones.

## 3. What "do not brick it" means here

[CONTRIBUTING.md](../../CONTRIBUTING.md) §3 is the Pixel safety model. It
treats stock slot A as the product we must be able to return to. That is
not the goal on this phone. The part of §3 that still binds is the part
that keeps the device recoverable.

### 3.1 The bootloader chain is the brick boundary

These partitions stay as they are, both slots: `xbl`, `xbl_config`, `abl`,
`aop`, `tz`, `hyp`, `keymaster`, `devcfg`, `uefisecapp`, `imagefv`,
`shrm`, `cpucp`, `cmnlib`, `qupfw`, `modem`, `bluetooth`, `dsp`, `ocdt`,
and every `oplus*` / engineering / reserve name the capture shows. The
exact GPT list is [I] until phase 1. Until that list exists, no partition
is written.

A bad `boot` image is recoverable. A bad `xbl` or `abl` often is not.
LineageOS's dodge install page documents the fastboot key combo as Volume
Up + Volume Down + Power from power-off. [V] as their documentation, [I]
on our phone. That combo is the recovery path, and it depends on `abl`.

Community reports from January 2026 (XDA, "ColorOS 16.0.3.501 updates =
permanent anti-rollback") say builds at and after ColorOS / OxygenOS
16.0.3.501 blow a hardware fuse in XBL. Flashing older firmware then
hard-bricks the phone, and the older EDL programmers do not recover it.
This phone's SOTA is from August 2026, so it is newer than that line.
[I] for the fuse state of this unit. The rule does not depend on it:
never flash a bootloader, modem or firmware image, older or newer.

`vbmeta` is in Lineage's flash list. We do not flash it in the fast loop.
Abrecht's `fastboot boot` on a CPH2653 did not need a vbmeta change.

### 3.2 What we are willing to destroy

`userdata` goes away at unlock. OxygenOS's data is expendable.

A bootable OxygenOS on the active slot is not, until our own kernel can
reboot into fastboot by itself. It is the loop's way back: a kernel that
hangs or panics resets into OxygenOS, and `adb reboot bootloader` returns
the cable to fastboot with no hands on the phone (§5.2). OxygenOS
userspace can go once a Linux boot is persistent and has its own path to
fastboot.

The stock boot images for this exact build come from the full OTA, not
from the phone: stock has no root and Qualcomm ABL has no `fastboot
fetch` [I].

Which package: the full firmware OTA for the build in Settings, in this
phone's region. That package is now on disk: product `CPH2653EEA`, ota
version `CPH2653_11.F.93_2930_202608071055` (§2, §6). The SOTA package
(`B100P01`) updates system apps and holds no boot images. An incremental
OTA holds deltas, which give no `init_boot` we could restore from. The
OnePlusOSS kernel trees are source, not images for this phone. `boot`,
`init_boot`, `vendor_boot`, `dtbo`, `vbmeta` and `recovery` are extracted
under `~/android/reference/dodge-cph2653/ota/`. They are what a bad flash
of those partitions is put back from. They are vendor images: they stay
out of git. The payload's firmware images (`xbl`, `abl`, `modem` and the
rest) were not extracted and are never flashed, whatever the OTA's
version.

Calibration partitions (`modemst1`, `modemst2`, `fsg`, `fsc`, `persist`,
and whatever the map adds) stay unread and unwritten until a radio plan
says otherwise. Wiping them does not help iteration and can turn a living
phone into one with no radio identity. [I] on the names.

### 3.3 Slots and updates

An A/B OTA leaves the older firmware on the inactive slot. If this
unit's anti-rollback fuse has blown, booting that slot may hard-brick it
[I]. So:

- Never `fastboot set_active`, and never flash `--slot=other`, until both
  slots' firmware is known to be the same build. On 2026-10-15 slot A
  was current and slot B was marked unbootable (`slot-successful:yes`
  as well, retry count 6). Slot B is not a fallback. `getvar
  version-bootloader` came back empty, so the bootloader version of
  neither slot is known yet.
- Switch off automatic system updates in OxygenOS right after unlock. An
  OTA must not move the bootloader during the project. Taking one is a
  decision with its own dev-docs entry.
- Our boot images go to the active slot only.

### 3.4 How this maps onto AGENTS.md

[AGENTS.md](../../AGENTS.md) §1 is written for the Pixel. An agent on
dodge reads this section before acting, or the workspace rule ("only
slot B is ours") wins by default. [AGENTS.md](AGENTS.md) in this
directory, and a line in the root file, point here. On dodge:

- Still binding: ask before every flash, reboot, unlock or irreversible
  write; announce anything that changes the screen or the feel of the
  phone; no `devmem`, no PMU/PMIC register access from userspace; one
  change per boot; a safety net before each risky step; no identifying
  data or vendor blobs in git; citable sources only.
- Replaced: "only slot B is ours" becomes §3.1 to §3.3 (the bootloader
  chain is untouchable, the active slot's boot images are ours, the other
  slot is untouchable until §3.3 clears it). The `UFS_RW` allowlist and
  `bin/omamobile flash|push` do not exist for dodge yet (§5.4). "Slot A is
  the way back" becomes OxygenOS plus `adb reboot bootloader` (§5.2).
- Not applicable: everything in AGENTS.md §4 is gs201. Dodge gotchas go
  in `device/dodge/NOTES.md`.

### 3.5 How a human stays in the loop

Unlock, the first `fastboot boot`, and every later flash wait for an
explicit go. A read of `fastboot getvar` does too, because the phone is
in someone's hand. Say so before a step that changes the screen.

One change per boot once we are flashing. `fastboot boot` of a throwaway
image is the exception: it is designed to be thrown away.

No `devmem`. No PMU/PMIC dumps from userspace. No `kexec` as a shortcut
until we know USB comes back after it.

## 4. Where the existing OSS work actually helps

Detail and links: [dev-docs/2026-10-15-oss-landscape.md](dev-docs/2026-10-15-oss-landscape.md).
Short version, in the order we will use them.

**The kernel and the boot command already exist, on this model.** Daniel
Abrecht (XDA, "My attempts to boot linux", November 2025) did this on a
CPH2653, over the same kind of USB cable:

- `fastboot boot Mu-dodge.img` puts Mu-Silicium's UEFI on the panel and
  writes nothing. A hung `fastboot boot` cleared with `fastboot reboot`
  from the laptop. The cable stayed the link.
- `sm8750-mainline/linux` branch `v6.16` already ships
  `qcom/sm8750-oneplus-dodge.dtb`. Packing that kernel as an Android
  `boot.img` and `fastboot boot`ing it hung for him. That hang is a bug
  to fix in the image, not a reason to add hardware.
- He later booted Devuan from a USB stick, using a powered hub, because
  Mu's USB *host* mode does not power a disk. That was his way around the
  hang. We do not copy it. The phone is already plugged into this machine.
  The laptop sends the image. See
  [dev-docs/2026-10-15-cable-not-stick.md](dev-docs/2026-10-15-cable-not-stick.md).

His firmware is `16.0.2.402`, older than this phone's August 2026 SOTA,
so his image is a data point, not a known-good for us.

**LineageOS has official dodge support**, models CPH2649, CPH2653,
CPH2655 and PJZ110, kernel 6.6, maintainers including ItsVixano. Their
flash set is `boot`, `dtbo`, `init_boot`, `vbmeta`, `vendor_boot`, plus
`recovery`. There is no `vendor_kernel_boot`. That list is our later
persistent install set, minus `vbmeta` until we know why theirs must be
flashed. Their kernel tree is the downstream DT reference, next to
OnePlusOSS (`android_kernel_oneplus_sm8750` and the modules/DT repo;
branches through `CPH2653_16.0.9.401` in July 2026).

**Mu-Silicium's dodge port** (`dodgePkg`) is a fallback console, booted
with `fastboot boot` over the cable if our own image hangs before it can
print. The status page marks Linux boot, display, internal storage, side
buttons and USB device mode working, and USB host, GPU and WLAN not. The
project state is inactive. We do not flash it over XBL, and we do not
need its USB-host mode.

**pagani-linux** (OnePlus 13s/13T, same SoC) is the worked example of a
mainline board port: DSC command-mode panel, touch, ath12k on WCN7880.
Different panel (1216x2640). Read it when we write the dodge panel driver.

**postmarketOS's dodge page** reports USB networking, internal storage,
screen, touch and the camera flash working, battery stuck at 0%, and no
device package in the repos. The photo is KDE Plasma on Arch Linux ARM,
which is the userspace family we want. The page disagrees with itself on
whether the port is mainline. Treat the feature list as someone else's
result.

**Not part of the loop:** Android custom kernels (KernelSU, susfs, OPlus
Kernel Lab), dual-boot trees that write `abl` / `tz` / `modem` per slot
(`spiral009/dodge-dualboot` is explicit that an ARB mismatch bricks a
slot), and random EDL "stock ROM" sites. EDL is not our recovery plan.

## 5. The iteration setup

The phone stays on one USB-C cable to this machine. That cable is
fastboot while the bootloader owns the bus, and it is SSH
(`172.16.42.1`) once our kernel brings up the USB gadget. The early
rootfs is a ramdisk inside the image the laptop just sent. Nothing is
copied to a stick, and no hub is required.

The loop has to be minutes. Android's GKI tree is the wrong build: it is
large, it wants a ramdisk full of Android, and a bad flash of it is how
people break `super`.

### 5.1 Laptop

| Piece | Where |
| --- | --- |
| Kernel | `~/android/mainline/wt-dodge`, output `~/android/mainline/out-dodge`. Checked out 2026-10-15 from `sm8750-mainline/linux` branch `v6.16` at `16cf517b2781`, depth 1, local branch `omamobile-dodge`. The dodge DTB builds. A rebase onto current mainline waits: Linux 7.3-rc7 has no dodge board. |
| Config | `kernel/configs/omamobile-dodge.config`, merged by `tools/dodge-try` on 2026-10-15. The Pixel fragment (`ARCH_EXYNOS`, Exynos USB, Exynos UFS, `s3c2410_wdt`) is the wrong fragment. |
| Boot image | One self-contained header v2 image (`Image` + dodge DTB + the initramfs, §5.3). Packed 2026-10-15 at `~/android/mainline/out-dodge/images/boot.img` (45481984 bytes). Not handed to fastboot. Omarchy's full root image comes later, once SSH exists. |
| Loop script | `tools/dodge-try`: `config` and `pack` stay on the laptop; `boot` does `fastboot boot`, waits for SSH, saves kmsg to `logs/`, and appends a row to `logs/dodge-tries.tsv` (§5.5). SSH deadline 120 s. The OxygenOS deadline is 600 s and is not a measured boot time; phase 1 replaces it. Only after both does `boot` call the phone dead. `bin/omamobile`'s `kernel`, `initramfs` and `images` are Pixel-shaped and stay untouched until §5.4. |
| Stock reference | `~/android/reference/dodge-cph2653/`: `getvar`, the OTA's boot images and DTBs (§3.2), notes on what they show. Never committed. |
| Notes | One `dev-docs/` file per session. |

The first config builds in (`=y`) everything the loop needs, so the
initramfs carries no modules: dwc3-qcom (both the `qcom,snps-dwc3` driver
and the legacy `qcom,dwc3` driver), the SM8750 USB PHYs and the eUSB2
repeater, configfs NCM and ACM, simpledrm, pstore/ramoops, `QCOM_WDT`,
panic on soft lockup and hung task. This tree's `FB_SIMPLE` depends on
`!DRM_SIMPLEDRM`, so the simple framebuffer is `DRM_SIMPLEDRM`. The image
command line is `clk_ignore_unused pd_ignore_unused panic=10 console=tty0`.
`console=tty0` is there so a framebuffer ABL left behind can show the
console. Stock's `console=ttynull` and `nosoftlockup` are not copied.

`QCOM_WDT=y` alone resets nothing. It needs a watchdog node in the DTB,
and a hardware watchdog only bites once something has armed it. Phase 0c
found no such node. The mainline dodge DTB has none, and stock's only
watchdog is an empty `/hypervisor/qcom,gh-watchdog` with no `compatible`
and no `reg`. `QCOM_WDT` has nothing to bind, so the watchdog row of
§5.2 does not exist yet. A hang before init runs is covered only by
`panic=10` if it panics, and by a human otherwise. A feeder in the
initramfs stays, and it cannot be the way back until a node Linux can
arm exists.

ramoops needs a region that survives a warm reset and that nothing else
uses: stock's own ramoops / pstore region from the OTA's reserved memory,
or a hole that the OTA's map and the rooted capture's `/proc/iomem`
agree on. Never a guess.

Host setup, done 2026-10-15 before the OTA download:

- `fastboot`, `adb` and `dtc` installed; `mkbootimg` and
  `unpack_bootimg` from a standalone package, not from the LineageOS
  tree `bin/omamobile` assumes (`SRC_DIR`, about 400 GB);
- udev access for OnePlus (`22d9`) and fastboot (`18d1:d00d`), so
  fastboot works without root;
- the user in the `docker` group, or the kernel built with the system
  clang;
- the NetworkManager profile `omamobile-phone` (172.16.42.2/24) that
  `tools/phone-ssh` assumes ([CONTRIBUTING.md](../../CONTRIBUTING.md) §2);
- a payload extractor for the OTA;
- `bc`, which the kernel needs to generate `timeconst.h`. The first
  `tools/dodge-try pack` stopped without it (2026-10-15).

All of these are in place. `adb`, `fastboot`, `mkbootimg`, `unpack_bootimg`
and `mkdtboimg` are Arch `android-tools`; `dtc` is the `dtc` package.
`/etc/udev/rules.d/52-omamobile-oneplus.rules` covers vendor `22d9` at
mode 0660, group `adbusers`. The user is in `docker` and `adbusers`.
`omamobile-phone` is manual `172.16.42.2/24`, never the default route,
IPv6 disabled, matched on `cdc_ncm` and not on an interface name, so an
OxygenOS RNDIS tether stays on its own profile. `payload-dumper-go`
lives in the reference tree.

Downstream DT checkouts (OnePlusOSS, Lineage's 6.6 tree) are read-only
references under `~/android/reference/src/`. They are not the tree we
compile for the phone. A Mu-Silicium checkout is optional, and only for
the fallback in §5.3.

### 5.2 The fast loop (no phone write)

This is the default until a kernel stays up on purpose.

```text
edit DTS or driver
  -> build Image + sm8750-oneplus-dodge.dtb + initramfs   (laptop)
  -> pack boot.img
  -> fastboot boot boot.img          (the cable already plugged in)
  -> panel shows the console; USB gadget comes up as 172.16.42.1
  -> ssh root@172.16.42.1
  -> reboot-to bootloader, or reboot -> OxygenOS -> adb reboot bootloader
```

How a failed try gets back to fastboot depends on where it failed:

| Where it stopped | Way back |
| --- | --- |
| In ABL, before the kernel (fastboot still answers) | `fastboot reboot` from the laptop. This is the hang Abrecht cleared |
| In the kernel, with a watchdog or a panic | Reset after `panic=10` or the watchdog, into OxygenOS, then `adb reboot bootloader` (`bin/omamobile fastboot` does this) |
| In our initramfs, gadget never configured | The init crashes itself after a timeout, as cheetah's does; then as above |
| Hard hang, no watchdog | A human: force restart with the buttons, then the fastboot combo. The case the first two rows exist to avoid |

So a failed kernel costs a reset and an OxygenOS boot, not a hand on the
phone, as long as OxygenOS stays bootable and adb-authorized (§3.2) and
the kernel has its watchdog (§5.1). `172.16.42.1` matches the rest of
this repo, so `tools/phone-ssh` works unchanged.

On the desk: the phone and one USB-C cable. The first session confirms
`fastboot devices`, and that `fastboot boot` of stock's own `boot.img`
boots OxygenOS once and leaves the next cold boot normal.

### 5.3 If our image hangs before it can talk

Two fallbacks, still over the same cable, still with no extra hardware:

1. Fix the boot image, one `fastboot boot` per suspect. [I] for all of
   them: with a header v4 image, Qualcomm ABL combines the uploaded
   `boot.img` with the *flashed* `init_boot` and `vendor_boot`: their
   ramdisks, and the DTB from `vendor_boot`, with `dtbo` on top. That mix
   is not a test of our kernel. Before Magisk it is stock Android's
   first-stage ramdisk and stock's DTB; after Magisk it is Magisk's
   ramdisk and stock's DTB. So the loop image is always self-contained.

   The first image copies stock's geometry: base, kernel, ramdisk, tags
   and DTB offsets and page size, from `unpack_bootimg` of the OTA's
   `vendor_boot` (a v4 `boot.img` carries no addresses). Those addresses
   are recorded in §6. With `--base 0` each offset equals the address.
   ABL may ignore them on arm64 [I], but a wrong offset hangs the same
   way a wrong DTB does, so stock's values remove that variable. Then one
   change per try:
   1. a header v2 image with `--dtb` carrying the mainline dodge DTB, in
      stock's geometry;
   2. `qcom,msm-id` and `qcom,board-id` in our DTB set to stock's values
      (from the OTA's DTB, §6). ABL selects the DTB by them, as gs201's
      ABL does by `soc_id`. Stock's dodge overlay carries eight sun and
      sunp pairs and `qcom,board-id = <0x40008 0x00>`. Which pair this
      unit is stays [I] until the live FDT;
   3. what ABL does when stock's `dtbo` does not apply to our DTB;
   4. the command line ABL appends.

   If ABL refuses a v2 image under `fastboot boot`, the next step is
   flashing `vendor_boot` with our DTB (on the active slot, with the
   OTA's stock copy to restore). That is a flash, and a decision with
   its own dev-docs entry, not the next item on this list.

   The postmarketOS dodge page already reports USB networking working,
   so the cable path is not theoretical.
2. `fastboot boot Mu-dodge.img` for a known console on the panel, to see
   how far UEFI gets. That image is not how we load our kernel. Mu's
   USB-host mode and the stick it boots from stay unused.

We add a hub and a stick only if both of those fail and a written note
says why the cable cannot carry the next try. That is a decision, not
the setup.

### 5.4 A flash, once the cable loop has worked

Only after the same kernel has booted temporarily and come back to
fastboot. Then, with a go-ahead:

- Flash only `boot`, `init_boot`, `vendor_boot`, `dtbo` (Lineage's set,
  without `vbmeta`).
- Put the rootfs on `userdata`. Unlock already erased it.
- Flash the active slot only (§3.3). Keep the OTA's stock boot images
  (§3.2) beside ours, so a bad persistent kernel is one fastboot flash
  from OxygenOS again.

`bin/omamobile images` and `device.conf` show up at this step, filled from
the capture. Extending the descriptor past Pixel `SOC_IDS` /
`vendor_kernel_boot` is a tool change, and cheetah's images stay
byte-identical. Do not invent a descriptor to make the tools run sooner.

### 5.5 What we log every try

Last kernel commit, the image's header version and DTB, whether it was
`fastboot boot` or a flash, the last line on the panel or over SSH,
whether pstore held anything after the reset, and which row of §5.2 got
the cable back to fastboot. `tools/dodge-try` appends this as one row to
`logs/dodge-tries.tsv`; a dev-docs entry quotes the rows that matter. A
try that hangs with no log teaches nothing, so the initramfs prints
early, ramoops is in the DT from the first try, and `panic=10` is set
before we care about a pretty boot.

## 6. Phases

### Phase 0 — Desk

This document, the OSS survey, the device identity. Still offline, no
phone:

- **0a. Host.** Done 2026-10-15. The setup list in §5.1.
- **0b. The stock images.** Done 2026-10-15. The build id is §2. The
  EU full OTA is extracted under
  `~/android/reference/dodge-cph2653/ota/`. The write-up is
  [dev-docs/2026-10-15-ota-boot-images.md](dev-docs/2026-10-15-ota-boot-images.md).
  Header versions, geometry, cmdline, msm-id / board-id, dtbo entries,
  the panel list, the Wi-Fi node and reserved memory are in the
  subsection below.
- **0c. The kernel.** Done 2026-10-15.
  `qcom/sm8750-oneplus-dodge.dtb` builds from `sm8750-mainline` `v6.16`
  at `16cf517b2781`. The built DTB has no `qcom,msm-id` and no
  `qcom,board-id`. Its compatible is `OnePlus,13`, `qcom,sm8750`. That
  is not the stock overlay's `qcom,board-id = <0x40008 0x00>`, and the
  eight sun/sunp pairs stay uncollapsed until the live FDT. There is no
  watchdog node (§5.1). USB `usb@a600000` (`snps,dwc3`), the wrapper
  `qcom,sm8750-dwc3` / `qcom,dwc3`, and both PHYs are enabled. Write-up:
  [dev-docs/2026-10-15-mainline-dtb.md](dev-docs/2026-10-15-mainline-dtb.md).
- **0d. The loop.** Done on the laptop 2026-10-15. Not booted.
  `tools/dodge-try pack` built Image `6.16.0-g16cf517b2781`, the dodge
  DTB from 0c (87477 bytes, still no msm-id or board-id), and
  [`initramfs/init`](initramfs/init). The header v2 image is
  `~/android/mainline/out-dodge/images/boot.img`. The init is cheetah's
  first-light init with the `devmem` and DECON lines removed. Every disk
  is read-only, there is no allowlist, and it does not mount UFS. The
  gadget still panics if the host never configures it. The watchdog
  feeder logs and continues when `/dev/watchdog` is absent, which it is
  on this DTB (§5.1). Write-up:
  [dev-docs/2026-10-15-dodge-try.md](dev-docs/2026-10-15-dodge-try.md).
- **0e. The rooted capture.** Done on the laptop 2026-10-15. Not
  installed. Magisk 30.7 (`Magisk-v30.7.apk`, from the `topjohnwu/Magisk`
  GitHub release, not the `app-debug.apk` asset) is at
  `~/android/reference/dodge-cph2653/root/`. `bin/omamobile capture`
  still uses `adb shell` when the adb uid is 0, so a cheetah capture's
  root commands are unchanged. When that uid is not 0 it tries Magisk
  `su -c`, with a 10 s bound so an ungranted prompt cannot hang it.
  `DEVICE=dodge` also saves the phase 1 regulator, clock, pin, bus,
  firmware and partition-size listings. The tool does not change the
  panel and does not install the APK. Write-up:
  [dev-docs/2026-10-15-magisk-capture.md](dev-docs/2026-10-15-magisk-capture.md).

#### Stock boot images

[V] from the OTA named in §2, unpacked 2026-10-15. Images stay out of
git. The attempt log has the commands and the header dumps.

`boot`, `init_boot`, `vendor_boot` and `recovery` are header version 4.
`boot.img` carries the kernel only
(36731392 bytes, an ARM64 `Image`, little-endian, 4 KiB pages, no
ramdisk, no cmdline). `init_boot` and `recovery` are ramdisks, LZ4
legacy, and their headers say os version 15.0.0, patch 2026-08, while
the package is Android 16. `vbmeta.img` is 12 KiB and has not been
decoded. `recovery.img` is in the payload; whether the GPT has a
`recovery` partition is still [I] until phase 1.

`vendor_boot` page size `0x1000`. Load addresses, used as the v2 offsets
with `--base 0` (§5.3):

| | |
| --- | --- |
| Kernel | `0x8000` |
| Ramdisk | `0x01000000` |
| Tags | `0x100` |
| DTB | `0x01f00000` (6821771 bytes) |

Vendor cmdline is `console=ttynull`, `qcom_geni_serial.con_enabled=0`,
`nosoftlockup`, a 640×400 virtual framebuffer, `bootconfig` and
`buildvariant=user`. Bootconfig names the USB controller
`a600000.dwc3` and sets `androidboot.serialconsole=0` and
`androidboot.hypervisor.protected_vm.supported=true`. The full lines are
in the dev-doc.

The vendor DTB is 13 FDTs. The sun family, all
`qcom,board-id = <0x00 0x00>`:

| msm-id | What the model string says |
| --- | --- |
| `<0x26a 0x10000>` | Sun SoC (`qcom,sun`) |
| `<0x26a 0x20000>` | Sun v2 |
| `<0x100026a 0x10000>` | Sun, alternate thermal |
| `<0x100026a 0x20000>` | Sun v2, alternate thermal |
| `<0x27f 0x10000>` | SunP (`qcom,sunp`) |
| `<0x27f 0x20000>` | SunP v2 |
| `<0x100027f 0x10000>` | SunP, alternate thermal |
| `<0x100027f 0x20000>` | SunP v2, alternate thermal |

The same blob also has kera, kerap, tuna, tuna 7 and tunap. Those are
other SoCs.

`dtbo.img` has 6 entries. The table's id fields are zero; each FDT
carries the match. All six use `qcom,board-id = <0x40008 0x00>` and the
eight msm-id pairs above. Entries 0, 1, 2 and 4 are model
"Sun MTP,dodge T0". Entries 3 and 5 are model "Sun MTP,dodge". Which
entry this unit is is [I] until the live FDT.

`qcom,dsi-default-panel` on those overlays is
`dsi_vtdr6130_amoled_video`, a Visionox video-mode DSC panel. Its first
timing is 1080×2400 at 144 Hz. `oplus,dsi-panel-primary` lists that node
plus five command-mode panels: AA545 P 3 A0005, BF262 P 3 A0021, and
three AA569 P 3 A0019 nodes (evb, evt, and plain). Two DSI controllers
(`qcom,dsi-ctrl-hw-v2.9`) and two PHYs (`qcom,dsi-phy-v7.2`). Which
panel this unit is is [I]. Phase 5's "120 Hz" waits on that answer.

Wi-Fi is the node `qcom,cnss-peach`, `supported-ids = <0x110e>`, at
`0xb0000000`. Bluetooth on the same overlay is `qcom,peach-bt`. Peach is
the DT name.

`cont_splash_region` is `reg = <0x00 0xfc800000 0x00 0x2b00000>` (43 MiB
at `0xfc800000`). `ramoops-region` in the sun base is 2.25 MiB
(`0x240000`), `no-map`, with `alloc-ranges` and no fixed base.
`qcom,ramoops` sets `pmsg-size` to 2 MiB and `console-size` to 256 KiB.
A rooted `/proc/iomem` confirms the live addresses before either region
is copied into our DTB (§5.1).

### Phase 1 — Read the boot chain, unlock, root, capture

Pass: `~/android/reference/dodge-cph2653/` holds `getvar` and the
partition map. Met for the read on 2026-10-15
([dev-docs/2026-10-15-getvar.md](dev-docs/2026-10-15-getvar.md)). The
phone was left locked, on the bootloader menu. adb's product was
`CPH2653EEA`, model `CPH2653`, device `OP5D55L1`, matching the OTA.
Fastboot `product` is `sun`. `current-slot` is `a`. Slot B is
unbootable (§3.3). `version-bootloader` and `version-baseband` are
empty, and the OTA metadata has no bootloader version, so that
comparison is still open. `recovery_a` and `recovery_b` exist, 100 MiB
each. There is no `vendor_kernel_boot`. No partition is named
`modemst1`, `modemst2`, `fsg`, `fsc` or `efs`. `persist` is present and
was not read. The live FDT needs root, which stock does not have until
the rooted capture below.

Then, on a go-ahead: `fastboot flashing unlock`. Data is gone after that.
Tried twice on 2026-10-15. The first answer was `Flashing Unlock is not
allowed` and `unlocked` stayed `no`
([dev-docs/2026-10-15-unlock-refused.md](dev-docs/2026-10-15-unlock-refused.md)).
After the OEM unlocking switch was turned on, the same command returned
`OKAY` and the phone rebooted to the OxygenOS welcome slide
([dev-docs/2026-10-15-unlock.md](dev-docs/2026-10-15-unlock.md)).
After setup, `ro.boot.flash.locked=0`, verified boot is `orange`, and
the slot is still `_a`. The build id is unchanged. Do not substitute
`fastboot oem unlock`.
Fastboot must still answer, and Volume Up + Volume Down + Power must still
reach it.

After unlock, set OxygenOS up once. The welcome flow requires a Wi-Fi
connection and does not offer a skip (2026-10-15). Join a network, then
skip accounts and any copy-from-old-device step. If a system update is
offered, do not install it: the phone stays on
`CPH2653_16.0.10.501(EX01)`. If the wizard instead demands the Google
account that was on the phone before the wipe, that is factory-reset
protection: sign in with that account, then remove it from the phone
once setup is done. Switch off automatic system updates (§3.3), turn on
USB debugging and authorize this laptop.
Pass: `adb reboot bootloader` reaches fastboot. That is the loop's way
back (§5.2).

Stop: `getvar product` is not `sun`, or adb's product is not
`CPH2653EEA`. Both matched on 2026-10-15. A bootloader version that
`getvar` actually returns and that differs from the OTA also stops us.
The variable was empty, so it did not. We do not flash a bootloader to
make anything match.

#### The rooted capture

Why: a working system's live state is what every mainline driver is
debugged against. Cheetah's ports leaned on exactly this
(`~/android/reference/cheetah-stock-*`). Stock OxygenOS gives no root, and
a downstream kernel booted only for its captures would be a second kernel
to maintain. Reasoning and the LineageOS alternative:
[dev-docs/2026-10-15-rooted-capture.md](dev-docs/2026-10-15-rooted-capture.md).

Risk: low. One flash of `init_boot` on the active slot, the partition the
OTA gives us a stock copy of (§3.2). Nothing below `boot` is touched, and
`vbmeta` is not flashed. Each step on a go-ahead.

1. Install `~/android/reference/dodge-cph2653/root/Magisk-v30.7.apk`
   (Magisk 30.7, from 0e) with `adb install`. Push the OTA's stock
   `init_boot.img` for *this* build to the phone and patch it in the
   Magisk app. Pull `magisk_patched-*.img` back into
   `~/android/reference/dodge-cph2653/root/`.
   Expect: the patched image is a few MiB larger than stock, and
   `unpack_bootimg` reads it. Stop: Magisk reports a different image
   format from 0b's, or the build ids do not match.
2. `adb reboot bootloader`. Read the active slot (`getvar current-slot`),
   then `fastboot flash init_boot_<slot> magisk_patched-*.img`, with the
   slot named, never the bare partition. `fastboot reboot`.
   Expect: the orange-state warning, then OxygenOS, and the Magisk app
   shows Magisk installed. Stop: a bootloop. Rollback: Volume Up +
   Volume Down + Power to fastboot, `fastboot flash init_boot_<slot>` with
   the OTA's stock `init_boot.img`. Never `--slot=all`, never the other
   slot (§3.3).
   Done 2026-10-15: `init_boot_a` only, then OxygenOS on slot A with
   `magiskd` running
   ([dev-docs/2026-10-15-magisk-install.md](dev-docs/2026-10-15-magisk-install.md)).
   The boot menu did not enumerate until the cable was reseated. `su` is
   not granted yet.

   If the patched image loops and stock boots again, phase 2 starts
   without the live capture; the OTA's DTBs stand in. Disabling
   verification in `vbmeta` is not the recovery step and not a second
   attempt: that is a separate decision with its own entry.
3. Grant `su` to the shell once on the phone's screen (the human taps
   it). Then the capture, read-only, twice. The tool does not change
   the panel. With the screen on:
   `DEVICE=dodge bin/omamobile capture dodge-cph2653/rooted-<date>-on`
   and with the screen off, the same command with `-off`. Root commands
   go through `su -c` (0e). Each directory gets:
   - `/sys/firmware/fdt`, `dmesg`, `/proc/iomem`, `/proc/interrupts`,
     `/proc/modules`, `/proc/cmdline`;
   - the kernel's own views: `regulator/regulator_summary`,
     `clk/clk_summary`, `pinctrl/*/pinmux-pins`, `gpio` under debugfs,
     and `/sys/bus/i2c/devices`, `/sys/bus/platform/devices`;
   - the firmware inventory: listings of `/vendor/firmware`,
     `/vendor/firmware_mnt` and `/vendor/lib/modules`, and the partition
     map with sizes;
   - one capture with the screen on and one with it off, for the panel's
     rails.

   Not in it: no `regmap/*/registers` files, no `devmem`, no PMIC or PMU
   register reads (§3.5), no writes. Nothing from `persist`, `modemst*`
   or `fsg`. The capture holds identifiers (serial, MACs in `dmesg`, the
   IMEI in properties): it never leaves `~/android/reference/`.
   Pass: the live DTB decompiles, and its `qcom,msm-id` / `qcom,board-id`
   match the OTA's DTB that ABL picked. The screen-on half is in
   ([dev-docs/2026-10-15-rooted-on.md](dev-docs/2026-10-15-rooted-on.md)):
   model "Sun MTP,dodge", `qcom,board-id` `<0x40008 0x00>`, and all eight
   sun/sunp msm-id pairs. The screen-off half is
   [dev-docs/2026-10-15-rooted-off.md](dev-docs/2026-10-15-rooted-off.md).
   Debugfs was not mounted during those two captures. It was mounted
   afterwards with the screen awake, the four files were saved, and it
   was unmounted
   ([dev-docs/2026-10-15-debugfs.md](dev-docs/2026-10-15-debugfs.md)).
   A screen-off copy of the regulator summary is still open.

Also time one cold boot to the OxygenOS home screen, cable plugged in:
that is `tools/dodge-try`'s long deadline (§5.1).

Magisk stays installed afterwards. A rooted OxygenOS is still the loop's
way back (§5.2), and root lets us repeat the capture when a mainline
driver needs a fresh comparison.

### Phase 2 — `fastboot boot` over the cable

First try: stock's own `boot.img` from the OTA. Pass: OxygenOS boots, and
the next cold boot is normal. That proves `fastboot boot` is still
temporary on this firmware, at no risk.

Then: an image we packed (the unchanged `sm8750-mainline` dodge build is
enough) comes up on the panel or on the USB serial gadget, and §5.2's way
back returns the cable to fastboot. If it hangs, work down §5.3.

Stop: the only way forward is flashing XBL, ABL or vbmeta. Stop if
`fastboot boot` is still the active boot after a cold boot (it must not
be). Mu-Silicium is a console to try if our image hangs, not a second
boot path we maintain.

### Phase 3 — Our kernel, SSH, no flash

Pass: `ssh root@172.16.42.1` from a kernel we built, booted with
`fastboot boot`, storage still read-only. Console on the framebuffer.
`panic=10`.

The first initramfs already marks every disk read-only, with an empty
allowlist. Cheetah's allowlist (the slot images and `userdata`) is copied
across, still without the `devmem` and DECON writes, only once we are
about to mount UFS.

### Phase 4 — Persistent Arch

Pass: one flash of the boot images, Arch (then Omarchy) on `userdata`,
Hyprland up. Software rendering is enough. The device package
`omamobile-device-dodge` starts here with nothing enabled that can hang
a boot.

### Phase 5 — Subsystems, one at a time

Each gets `device/dodge/<NAME>-PLAN.md` before code. Order, because each
one shortens the next debug:

| # | Stage | Done when |
| --- | --- | --- |
| 1 | Display | The panel's own mode, brightness, 120 Hz, DPMS. Pagani's DSC driver is the shape, not the timings. |
| 2 | Touch and buttons | `evtest` sees them |
| 3 | Battery and charging | Percent and temperature move. The public report says the gauge sticks at 0%. |
| 4 | USB-C | A replug comes back |
| 5 | GPU | Hyprland on Adreno 830. Software rendering stays the fallback. |
| 6 | Wi-Fi and Bluetooth | The chip the DT names. ath12k is the likely driver. Firmware from the owner's image, never committed. |
| 7 | Haptics, torch | A buzz, a light |
| 8 | Audio | Speakers under a volume ceiling |
| 9 | Sensors | Accelerometer, so rotation works |
| 10 | Suspend | s2idle, log streamed, Wi-Fi unloaded until its sleep path is known |
| 11 | Modem | Its own plan. Backups of the NV partitions first. Not the Pixel SIT client. |
| 12 | NFC, cameras, fingerprint | Last. A secure-storage write waits for an explicit yes. |

## 7. Gates

| After | Continue | Stop |
| --- | --- | --- |
| Phase 0 | The OTA matches the build id, and the dodge DTB builds. Both met 2026-10-15. 0d packed a header v2 image and 0e downloaded Magisk 30.7 and taught capture `su -c`, both on the laptop, neither run on the phone. Phase 1 still waits for a go | No OTA for this build can be found |
| Phase 1 | Fastboot answers before and after unlock; `adb reboot bootloader` works from OxygenOS; the rooted capture exists | Product id is unexpected, the bootloader does not match the OTA, or patched `init_boot` loops and the stock one does not restore it |
| Phase 2 | `fastboot boot` over the cable was temporary, and the kernel printed a banner | The next step wants an XBL or ABL write |
| Phase 3 | SSH from `fastboot boot`, and a reboot returns to fastboot | The boot image has to be flashed to learn anything |
| Phase 4 | A bad flash is one fastboot write from a prompt | Fastboot stops answering |

GPU, Wi-Fi and the modem failing leave those rows open. They do not end
the port. Losing fastboot does.

## 8. Notes

Keep a log. Every step on the phone, and every laptop step that changes
what the next boot will do, is written up before the session moves on.
That includes refusals, surprises and dead ends, not only the steps that
worked. The entry says what we did, what the phone did, and what the
next attempt will do differently. It lands in the same change as the
plan update it causes. Captures and identifiers stay in
`~/android/reference/dodge-cph2653/` and out of git. The format is
[dev-docs/README.md](dev-docs/README.md).

| Kind | Where |
| --- | --- |
| This plan | `device/dodge/PLAN.md` |
| One attempt | `device/dodge/dev-docs/YYYY-MM-DD-slug.md` |
| A fact later boots will trip over | `device/dodge/NOTES.md`, once we have one |
| A subsystem | `device/dodge/<SUBSYSTEM>-PLAN.md` |
| The device matrix | `docs/DEVICES.md`, only with a note that shows what this phone did |

No serials, IMEIs or MACs in any of these. The model, hardware version,
baseband and SOTA string are properties of the CPH2653 EU build, and they
belong in the plan.

## 9. Open on this phone

- The bootloader version of each slot (§3.3). `getvar version-bootloader`
  was empty on 2026-10-15, on slot A. The OxygenOS build id is §2.
- Whether `fastboot boot` is still temporary on this August 2026 firmware.
  Abrecht proved it on `16.0.2.402`. Phase 2's stock `boot.img` try
  answers it.
- Whether the two slots' boot images are the same build. The names are
  known (2026-10-15): `recovery_a` and `recovery_b` are real, 100 MiB,
  and there is no `vendor_kernel_boot`. Slot B is unbootable.
- Why a packed mainline `boot.img` hung for Abrecht: §5.3's list, one
  try per suspect. The cable is the path either way.
- Whether ABL takes the DTB from a header v2 image under `fastboot boot`,
  or always from the flashed `vendor_boot`.
- Whether our kernel's `reboot-to bootloader` reaches fastboot on this
  ABL (`qcom-pon` reboot mode), which would retire OxygenOS as the way
  back.
- Which vendor FDT and which dtbo entry (T0 or later) ABL picks, and
  which panel on the primary list this unit is (§6).
- The ramoops physical address. The OTA gives the size and a dynamic
  range (§6). The mainline dodge DTB has no ramoops node. A rooted
  `/proc/iomem` is the check.
- A watchdog node Linux can arm. Stock has an empty Gunyah watchdog,
  and the mainline DTB has none (§5.1), so a hang that does not panic
  waits for a human.

Answered from the OTA on 2026-10-15 (phase 0b): header versions, page
size, `vendor_boot` geometry, vendor cmdline, msm-id / board-id, the
dtbo entries, the panel list, the Wi-Fi node's compatible and id, the
splash region and the ramoops size. The rooted capture (phase 1) is what
says which of those the running system uses, plus the rails and clocks
the panel, touch and USB need, and which firmware files were loaded.

## 10. Sources

Re-check before building. Community trees move. The survey write-up has
the same list with the role each one plays.

- This repo: CONTRIBUTING §3, `docs/DEVICES.md`, `docs/RELEASES.md` §3,
  `device/cheetah/device.conf`, `kernel/configs/omamobile.config`.
- LineageOS wiki: `devices/dodge` and `devices/dodge/install`.
- Magisk documentation (`topjohnwu.github.io/Magisk/install.html`): patching
  `init_boot` on devices that launched with Android 13 or later.
- Daniel Abrecht, XDA thread "My attempts to boot linux" (November 2025),
  and `Daniel-Abrecht/Mu-Silicium` branch `dodge-host-mode`.
- Project-Silicium `Mu-Silicium` `Platforms/OnePlus/dodgePkg` and
  `Status.md`.
- `sm8750-mainline/linux` branch `v6.16` (`sm8750-oneplus-dodge.dtb`, as
  packed in Abrecht's `fastboot boot` command).
- OnePlusOSS `android_kernel_oneplus_sm8750`,
  `android_kernel_common_oneplus_sm8750`,
  `android_kernel_modules_and_devicetree_oneplus_sm8750`.
- `renhiyama/pagani-linux` commit `c49d202`.
- postmarketOS / Nura wiki, OnePlus 13 (`oneplus-dodge`) and the SM8750
  SoC page.
- XDA anti-rollback thread, January 2026. OnePlus's August 2026 SOTA
  announcement for `B100P01` (the GDPR variant is the EU track of that
  update).
- EU OTA catalog for model CPH2653 (roms.danielspringer.at), read
  2026-10-15. The zip's own metadata is the check; the catalog is how
  the row was chosen. Signed download URLs are not recorded.
- Mainline `arch/arm64/boot/dts/qcom/sm8750.dtsi` (SoC, not the phone).
  Adreno 830 DRM series on the list, August 2026.
