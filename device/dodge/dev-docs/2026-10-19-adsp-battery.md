<!-- SPDX-License-Identifier: MIT -->
# 2026-10-19 — ADSP battery

**Goal.** Get a battery percent from the ADSP charger domain.
**Phone.** OnePlus 13 CPH2653. No restart of the phone. The
desktop stayed up. The ADSP itself was restarted twice.
**Kernel.** `6.16.0-gb3ee311dab85`, plus `qcom_q6v5_pas.ko` and
`qcom_pd_mapper.ko` built from `omamobile-dodge` `1ad7f044e`.
**Result.** Pass. Capacity 69 before the reboot. After a
cold boot the service is active, the ADSP is running, and the
supply reads 67, Discharging, 4.056 V, 36.6 °C, health Good.

## What we did

`dsp_a` is audio libraries. The split images are on `modem_a`,
a FAT filesystem mounted read-only. `adsp.mdt` and `adsp.b*`
were copied to `/lib/firmware/qcom/sm8750/OnePlus/`, with the
mdt header named `adsp.mbn` so the loader's segment names stay
`adsp.bNN`. The same for `adsp_dtb`. The partitions were
unmounted afterwards. Nothing in those images was committed.

`qcom_q6v5_pas` probes every enabled PAS node. `only_adsp=1`
returns `-ENODEV` for the modem and the CDSP before either is
touched. The first probe failed in `qmi_handle_init` until
`qrtr` was loaded. The ADSP then reached `running`.

`qcom_battmgr` created its supplies and returned `EAGAIN`.
`service_up` stays false until PDR reports
`msm/adsp/charger_pd`. `pd_mapper` had no `qcom,sm8750` match,
so the locator answered nothing. The stock `battmgr.jsn` names
that domain at instance 74, which is the SM8550 list. Adding
the compatible was not enough on its own: PDR talks to the
ADSP over `qrtr-smd`, and that module was not loaded. With
`qrtr-smd` in place, one more ADSP restart logged

```
PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff
```

and the properties started answering. A 90 s dead-man was armed
for that restart and cancelled when SSH stayed up.

The sm8350 notification handler still logs unknown codes
`0x55`, `0x57`, `0x58`, `0x7d` and `0x7f`. They did not block
the percent.

## What is installed

`/usr/local/lib/omamobile/adsp-battery.sh` and
`omamobile-adsp-battery.service` load this stack at boot. A
cold boot on 2026-10-20 started the unit with result success.
The only remoteproc is the ADSP, state running. The modem and
the CDSP stayed down. The desktop was up. The USB supply was
online at 4.93 V with `usb_type` SDP and a 500 mA input limit,
while the battery status stayed Discharging.
