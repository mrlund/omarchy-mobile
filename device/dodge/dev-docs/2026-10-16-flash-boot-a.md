<!-- SPDX-License-Identifier: MIT -->
# 2026-10-16 — flashing boot_a did not boot

**Goal.** Flash the chain image to `boot_a` only, then reboot without
another `fastboot boot`.
**Image.** `out-dodge-chain/images/boot-chain.img`, sha256
`fe1334e569a58a28281325d1658a7ac1185aa92aed870970d844e307a3b57538`,
58535936 bytes, header v4, ramdisk size 0. Stage 1 has a built-in
initramfs and `CONFIG_CMDLINE_FORCE`.
**Rollback.** OTA `boot.img`, sha256
`bbb4980f9efc63371268b8f7fbf78d0516e19c78a2c6a5f254170a409ebea983`,
100663296 bytes.
**Result.** `fastboot flash boot_a` returned OKAY. The reboot came
back to fastboot. Stock `boot_a` was written back. Arch is running
again via `fastboot boot`.

## What we did

From Arch, `reboot-to bootloader`. One fastboot device, slot `a`.
`fastboot flash boot_a` of the chain image, then `fastboot reboot`.
No other partition was written. Slot B was not touched.

## What happened

The write finished at 14:32:51. USB dropped at 14:32:53 and returned
at 14:32:58 as fastboot (`18d1:d00d`). Five seconds is not our
kernel: stage 1's `panic=10` would take longer than that. ABL
accepted the write and did not start the image.

Stock `boot_a` was flashed back at 14:34:40, OKAY. `fastboot boot` of
the chain image then reached Arch Linux ARM on `/dev/sda15`, 452.7 GiB.

## Learning

`fastboot boot` of this kernel-only v4 image is not the same as a
normal boot of that image from `boot_a`. ABL came back to fastboot in
5 s, before the kernel. `vbmeta` chains `boot` to a footer at the end
of the partition. Stock `boot.img` has that footer (metadata at offset
36753408). `boot-chain.img` has none: `avbtool info_image` says it does
not look like a vbmeta image. Invalid metadata is fatal even when the
bootloader is unlocked. `fastboot boot` never reads that footer.

`tools/dodge-chain footer` now writes
`out-dodge-chain/images/boot-chain-avb.img`: the same bytes, then a
SHA256_RSA4096 hash footer, padded to 100663296. Metadata is at offset
58535936. The signing key is outside the repo
(`~/android/reference/dodge-cph2653/avb-boot.pem`) and does not match
the key `vbmeta` chains to. That image has not been flashed.
