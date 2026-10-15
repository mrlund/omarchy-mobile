<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — kexec from one fastboot boot into our kernel and DTB

**Goal.** Start our kernel on our DTB and our initramfs from one
`fastboot boot`, with no flash. ABL starts header v4 images and hands
them stock's DTB; our kernel with a built-in init already runs on that
([2026-10-15-fastboot-boot-rdinit.md](2026-10-15-fastboot-boot-rdinit.md)).
Have that init `kexec` a second kernel with our DTB.
**Phone.** CPH2653, build `CPH2653_16.0.10.501(EX01)`, slot `_a`,
unlocked. Magisk 30.7 is in `init_boot_a`.
**Kernel.** Stage 1: `6.16.0-gf71c365a86e2`, `out-dodge-rdinit`.
Stage 2: the `out-dodge` `Image` (`6.16.0-g16cf517b2781`; the
`f71c365a8` commit only touched the DTS) with the `boot-ids` DTB.
**Result.** Pass, from timing. OxygenOS was back 82 s after `Booting
OKAY`, the band for stage 2's 60 s hold. Every failure band was at
least 40 s away.

## What we did

Stage 1 is the rdinit kernel (`CONFIG_CMDLINE_FORCE`,
`rdinit=/omamobile/init panic=10`) with this built-in initramfs,
compressed with zstd (`CONFIG_INITRAMFS_COMPRESSION_ZSTD`), everything
under `/omamobile/` so ABL's ramdisks cannot replace it:

| Path | What |
| --- | --- |
| `busybox` | Alpine 3.24 `busybox-static-1.37.0-r31` |
| `init` | the stage-1 script below |
| `kexec` | Alpine 3.24 `kexec-tools-2.0.32-r2`, dynamic musl |
| `lib/` | `ld-musl-aarch64.so.1` (and as `libc.musl-aarch64.so.1`), `libz.so.1`, `liblzma.so.5` (`xz-libs-5.8.4-r0`), `libzstd.so.1` (`zstd-libs-1.5.7-r2`) |
| `Image` | stage 2 kernel, 40376832 bytes |
| `dodge.dtb` | stage 2 DTB |
| `initrd2.cpio` | stage 2 initramfs: `/init` and static busybox |

`kexec` runs through the loader, `ld-musl-aarch64.so.1 --library-path
/omamobile/lib /omamobile/kexec`, so nothing lands in `/lib`. It was
checked under `qemu-aarch64-static` (`--version`, option parsing).
`kexec_file_load` cannot take a new DTB on arm64; kexec-tools' `-l
--dtb` uses `kexec_load`, which can.

Stage 1 `/omamobile/init`:

```sh
#!/omamobile/busybox sh
B=/omamobile/busybox
$B mount -t proc proc /proc
KEXEC="/omamobile/lib/ld-musl-aarch64.so.1 --library-path /omamobile/lib /omamobile/kexec"
if $KEXEC -l /omamobile/Image --dtb=/omamobile/dodge.dtb \
    --initrd=/omamobile/initrd2.cpio \
    --command-line="rdinit=/init clk_ignore_unused pd_ignore_unused panic=10 console=tty0"; then
  $KEXEC -e
  $B sleep 120
else
  $B sleep 150
fi
echo b > /proc/sysrq-trigger
while :; do $B sleep 60; done
```

Stage 2 `/init`: mount `/proc`, `sleep 60`, `echo b >
/proc/sysrq-trigger`, loop. The command line is `tools/dodge-try`'s
plus `rdinit=/init`.

Stage 2 DTB: the `boot-ids` DTB with one change. ABL fills the
`memory` node at boot and kexec does not, so its `reg` was set to the
live FDT's `/memory` `reg` (16 ranges, 15.13 GiB). The upstream DTS's
map is another phone's: the live map has a hole at
`0xbd930000`-`0xbe360000` that the upstream one covers, and other
ranges differ. `memory@a0000000` keeps size 0. `dtc -s` of the two
DTBs differs only in that `reg` line. A first try with `fdtput
/memory` wrote `memory@a0000000` instead (libfdt matches the name
without the unit address); that copy was thrown away.

Stage 1 `Image` is 54729216 bytes. `mkbootimg --header_version 4
--kernel Image`: `~/android/mainline/out-dodge-rdinit/images/boot-v4-kexec.img`,
54734848 bytes, sha256
`d94ce3c0ad15c2525de0e06e2f75ab7ae634b57481547e5d8652cc9a86536430`,
ramdisk 0, cmdline empty. `max-download-size` is 805306368.

Expected bands, from `Booting OKAY` to adb, with OxygenOS about 13 s
after a reset:

| Back at | Meaning |
| --- | --- |
| about 80 s | stage 2 ran its init on our DTB |
| about 25-40 s | stage 2 started and panicked |
| about 140 s | `kexec -e` returned |
| about 165 s | `kexec -l` failed |
| stays in fastboot | ABL refused the image |
| never | stage 2 hung without a panic |

`adb reboot bootloader`, fastboot in 12 s, slot `a`, product `sun`,
`fastboot boot`.

## What happened

```text
Sending 'boot.img' (53452 KB)                      OKAY [  1.216s]
Booting                                            OKAY [  0.378s]
```

| t after `Booting OKAY` | USB |
| --- | --- |
| 0 s | `18d1:d00d` (fastboot) |
| 1 s | nothing |
| 82 s | `22d9:2769`, adb |

OxygenOS: slot `_a`, same build, `ro.boot.flash.locked=0`, `magiskd`,
uptime 13 s, pstore empty, `ro.boot.bootreason` `bootloader`. The reset
came about 69 s after `Booting OKAY`: a few seconds of stage 1, the
kexec, stage 2's boot and its 60 s hold.

## Learning

From timing: one `fastboot boot` now starts our kernel on our DTB with
our initramfs. ABL's DTB and ramdisks only carry stage 1, and nothing
was flashed. This is the self-contained image §5.3 was after.

Still unproven: what stage 2 brings up. Its only sign of life is the
reset. The next stage 2 initramfs is `tools/dodge-try`'s (USB gadget,
SSH), with the timed reset kept as the fallback so a dead cable still
comes back to OxygenOS on its own. USB did not return after kexec on
cheetah; here stage 1 never touched USB, but ABL left the controller
in fastboot's state.
