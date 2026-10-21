<!-- SPDX-License-Identifier: MIT -->
# dodge sensors (ADSP SSC via libssc)

The sensors sit behind the ADSP's Snapdragon Sensor Core (QMI service 400 on
QRTR node 5). They work once `hexagonrpcd -s` attaches to the sensors PD and
serves the phone's own registry, JSON config and DSP libs.

| Sensor | Status (2026-10-21) |
|---|---|
| accelerometer (bmi26x) | works: `ssccli`, iio-sensor-proxy |
| proximity (tcs3720) | works: NEAR/FAR |
| compass | works through iio-sensor-proxy |
| ambient light | not found (`ambient_light` discovery fails; OPlus ALS) |

Pieces:

- `prepare-root`: builds `/var/lib/omamobile/sensors/root` read-only from
  `persist` (registry, mounted `ro,noload`), `dsp_a` (ADSP libs) and the
  vendor/odm erofs in `super` (copied with dd, extracted with `fsck.erofs`). Also
  writes stub socinfo (no qcom-socinfo in this kernel). Phone-only data: never
  commit it.
- `hexagonrpc-da7a374-omamobile.patch`, against
  github.com/linux-msm/hexagonrpc:
  - maps `/odm/etc/sensor/config`;
  - keeps the listener running after an unsupported method. Without this,
    hexagonrpcd quit 257 ms in, on apps_std method 36.
- `libssc-4e4c6c8-no-gir.patch`: skips GObject introspection (no g-ir-scanner).
- `omamobile-sensors.service`: hexagonrpcd on `/dev/fastrpc-adsp-secure`, gated
  on `/etc/omamobile/sensors.enable`. The sensors PD attaches only once per ADSP
  boot, so the service has to be up at boot.
- `81-omamobile-ssc.rules` + `iio-sensor-proxy-omamobile.conf`: tag the fastrpc
  node `ssc-accel ssc-proximity` and order iio-sensor-proxy after hexagonrpcd.
  iio-sensor-proxy is built from git with `-Dssc-support=enabled`.
- `omamobile-autorotate`: monitor-sensor → `hyprctl eval` monitor and
  touch transform. Opt-in, from autostart.lua. The rotation mapping is
  not verified on the device yet.

Persist is never written. hexagonfs opens everything `O_RDONLY` and
refuses writes ("Tried to open … for writing"), and it serves a copy anyway.
