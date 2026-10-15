<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — stock boot images from the EU OTA

**Goal.** Fetch the full OxygenOS package for the build in Settings and
record the boot-image facts phase 0c and the first `fastboot boot` image
need.
**Phone.** OnePlus 13, CPH2653. Settings, About:
`CPH2653_16.0.10.501(EX01B100P01)`, baseband `Q_V1_P14,Q_V1_P14`, kernel
`6.6.118-android15-8-g2e6b9c3812c5-ab1511`. No serial, IMEI or MAC here.
**Kernel.** No kernel of ours. The phone was not unlocked, rooted,
rebooted or flashed.
**Result.** Pass. The EU full package matches that build, and the boot
images are unpacked under `~/android/reference/dodge-cph2653/ota/`.

## What we did

Phase 0a was already in place on this laptop: `android-tools` and `dtc`,
the user in `adbusers` and `docker`, a mode-0660 udev rule for vendor
`22d9`, and NetworkManager profile `omamobile-phone` (manual
`172.16.42.2/24`, `ipv4.never-default` yes, IPv6 disabled, matched on
`cdc_ncm` only). No command went to the phone.

The public EU catalog for model CPH2653 (roms.danielspringer.at, read
2026-10-15) has a row `CPH2653_16.0.10.501(EX01)`, ota version
`CPH2653_11.F.93_2930_202608071055`, security patch 2026-08-01, size
8326711343, md5 `430b63773eaeab3f03df9aeafcf72873`. A later row,
`CPH2653_16.0.10.600(EX01)` (`F.94`, September 2026 patch), was the
catalog's latest and was left unused.

The download host refuses a bare GET. The client headers an OPlus OTA
download uses (`userId: oplus-ota|00000001`, a `Range` header, a Dalvik
user agent) get a short-lived redirect. The signed CDN URL was not
written down. The zip landed at
`~/android/reference/dodge-cph2653/ota/CPH2653_16.0.10.501_EX01_EU.zip`,
8326711343 bytes, md5 as above.

`payload-dumper-go` (ssut, kept in the reference tree) extracted `boot`,
`init_boot`, `vendor_boot`, `dtbo`, `vbmeta` and `recovery` into
`ota/images/`. Firmware partitions (`xbl`, `abl`, `modem` and the rest)
were not extracted. `payload.bin` was removed after the dump; the zip is
the copy to keep. `unpack_bootimg`, `mkdtboimg dump` and `dtc` 1.8.1 did
the unpack. The vendor DTB is 13 FDTs concatenated on magic `d00dfeed`.

## What happened

The zip's `META-INF/com/android/metadata` says `product_name=CPH2653EEA`,
`pre-device=OP5D55L1`, `version_name=CPH2653_16.0.10.501(EX01)`,
`ota_version=CPH2653_11.F.93_2930_202608071055`, Android 16, SDK 36,
security patch and vendor patch 2026-08-01, `ota-type=AB`, `wipe=0`,
`os_version=V16.1.0`, `oplus_project_numbers=23893`. `post-build` is
`OnePlus/CPH2653EEA/OP5D55L1:16/BP2A.250605.015/V.R4T3.26d97ac-1c1394-1d9854:user/release-keys`.
`post-timestamp` is 1786066801 (2026-08-07 01:40:01 UTC). The catalog's
build timestamp for the same row is 2026-08-07 10:55:00, which is the
stamp inside the ota version. Settings appends the SOTA suffix
`B100P01` onto `version_name`; the package itself does not.

`boot.img`'s kernel is an ARM64 `Image`, little-endian, 4 KiB pages,
`text_offset` 0. Its version string is
`6.6.118-android15-8-g2e6b9c3812c5-ab15114928-4k`, built Mon Mar 30
10:41:25 UTC 2026. That is the string Settings showed, plus the `-4928-4k`
tail Settings cut off.

Headers, from `unpack_bootimg`. Every image is header version 4. `boot`
has no ramdisk, no cmdline and no signature. `init_boot`, `recovery` and
the vendor ramdisk are LZ4 legacy (`02 21 4c 18`). The `init_boot` and
`recovery` headers say os version 15.0.0, patch 2026-08, while the
package is Android 16.

| Image | File size | Payload |
| --- | --- | --- |
| `boot.img` | 96 MiB | kernel 36731392 bytes, ramdisk 0 |
| `init_boot.img` | 8 MiB | ramdisk 2720723 bytes |
| `vendor_boot.img` | 96 MiB | see geometry below |
| `dtbo.img` | 24 MiB | table total 7748005, 6 entries |
| `vbmeta.img` | 12 KiB | not decoded |
| `recovery.img` | 100 MiB | ramdisk 47264276 bytes, kernel 0 |

`vendor_boot` header v4, page size `0x1000`, header size 2128. Load
addresses, which a v2 pack passes as the offsets when `--base` is 0:

| Field | Address |
| --- | --- |
| Kernel | `0x8000` |
| Ramdisk | `0x01000000` |
| Tags | `0x100` |
| DTB | `0x01f00000` (size 6821771) |

One vendor-ramdisk table entry: type `0x1` (platform), offset 0, size
18480690, empty name, `board_id` all zeros. Vendor cmdline:

```text
video=vfb:640x400,bpp=32,memsize=3072000 log_buf_len=2M nosoftlockup console=ttynull qcom_geni_serial.con_enabled=0 nohugevmalloc bootconfig buildvariant=user
```

Bootconfig (232 bytes): `androidboot.hardware=qcom`,
`androidboot.memcg=1`, `androidboot.usbcontroller=a600000.dwc3`,
`androidboot.load_modules_parallel=true`,
`androidboot.hypervisor.protected_vm.supported=true`,
`androidboot.vendor.qspa=true`, `androidboot.serialconsole=0`.

The vendor DTB holds one FDT per SoC variant. Every one has
`qcom,board-id = <0x00 0x00>`. The sun family is SM8750:

| FDT | Model | compatible | qcom,msm-id |
| --- | --- | --- | --- |
| vendor5 | Sun SoC | `qcom,sun` | `<0x26a 0x10000>` |
| vendor4 | Sun v2 SoC | `qcom,sun` | `<0x26a 0x20000>` |
| vendor3 | Sun alt. thermal | `qcom,sun` | `<0x100026a 0x10000>` |
| vendor2 | Sun alt. thermal v2 | `qcom,sun` | `<0x100026a 0x20000>` |
| vendor9 | SunP SoC | `qcom,sunp` | `<0x27f 0x10000>` |
| vendor8 | SunP v2 SoC | `qcom,sunp` | `<0x27f 0x20000>` |
| vendor7 | SunP alt. thermal | `qcom,sunp` | `<0x100027f 0x10000>` |
| vendor6 | SunP alt. thermal v2 | `qcom,sunp` | `<0x100027f 0x20000>` |

The same blob also carries kera (`0x293`), kerap (`0x2ae`), tuna
(`0x28f`), tuna 7 (`0x2a9`) and tunap (`0x2b6`). Those are other SoCs.

`dtbo.img`: magic `d7b7ab1e`, version 0, page size 4096, 6 entries, and
the table's own id, rev and custom fields are all zero. Selection is the
board id inside each FDT. All six overlays have the same
`qcom,msm-id` (the eight sun and sunp pairs above) and
`qcom,board-id = <0x40008 0x00>`, compatible `qcom,sun-mtp`, `qcom,sun`,
`qcom,sunp-mtp`, `qcom,sunp`, `qcom,mtp`. Entries 0, 1, 2 and 4 are model
"Sun MTP,dodge T0". Entries 3 and 5 are model "Sun MTP,dodge".

On those overlays, `qcom,dsi-default-panel` is
`dsi_vtdr6130_amoled_video`: "vtdr6130 amoled video mode dsi visionox
panel with DSC", type `dsi_video_mode`. Its first timing is 1080×2400
(`0x438`×`0x960`) at 144 Hz. `oplus,dsi-panel-primary` lists that node
and five command-mode panels: AA545 P 3 A0005 ("AA545 P 3 A0005 dsc cmd
mode panel"), BF262 P 3 A0021, and three AA569 P 3 A0019 nodes (evb, evt,
and plain), each "AA569 P 3 A0019 dsc cmd mode panel". Two DSI
controllers, `qcom,dsi-ctrl-hw-v2.9`, and two PHYs, `qcom,dsi-phy-v7.2`.
The overlays also contain Qualcomm reference `nt37801` panel nodes that
are not on the primary list.

Wi-Fi node `qcom,cnss-peach@b0000000`, compatible `qcom,cnss-peach`,
`supported-ids = <0x110e>`, `reg = <0xb0000000 0x10000>`, `wlan-en-gpio`
on tlmm gpio `0x10`. A sibling is `qcom,cnss-direct-link`. Bluetooth is
`qcom,peach-bt`. Peach is the name in the DT.

Reserved memory. In the sun base (vendor5), `ramoops-region` is
`size = <0x00 0x240000>` (2.25 MiB), `no-map`,
`alloc-ranges = <0x01 0x00 0xfffffffe 0xffffffff>`, so no fixed base.
`qcom,ramoops` points at it with `pmsg-size = <0x200000>`,
`console-size = <0x40000>`, `mem-type = <0x02>`. In the dodge overlay,
`cont_splash_region` is
`reg = <0x00 0xfc800000 0x00 0x2b00000>` (43 MiB at `0xfc800000`). A
`disp_rdump_region` in another fragment has `reg = <0xfc800000 0x800000>`
and a unit address (`0xd5500000`) that does not match that `reg`. Demura
regions are `reg` zero.

`vbmeta.img` was extracted and not decoded.

## Learning

The package name to restore from is `CPH2653EEA` /
`CPH2653_11.F.93_2930_202608071055`, not the `CPH2653GDPR_11_…` form the
plan guessed. `EX01` is the tag on the EU catalog's version strings.
Plan §2, §3.2 and §6.

The first self-contained image copies the `vendor_boot` load addresses
above (§5.3). There is no single stock `qcom,msm-id`: the dodge overlay
lists all eight sun and sunp pairs and `qcom,board-id = <0x40008 0x00>`.
Phase 0c compares the mainline dodge DTB with that set and does not
collapse it to one pair. Which vendor FDT and which overlay (T0 or
later) ABL actually picks, and which primary-list panel this unit is,
wait for the rooted live FDT.

ramoops has a size and no address. The splash node has an address.
Neither goes into our DTB until a rooted `/proc/iomem` agrees (§5.1).

The running system is still Android's. `console=ttynull`,
`qcom_geni_serial.con_enabled=0` and `androidboot.serialconsole=0` are
stock's command line. `androidboot.usbcontroller=a600000.dwc3` is the
USB controller name phase 0c looks for. `androidboot.hypervisor.protected_vm.supported=true`
is consistent with Gunyah owning pieces of the boot, which is still an
open question for the watchdog.
