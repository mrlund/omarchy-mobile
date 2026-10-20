<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20 — ADSP audio

**Goal.** Get the audio framework inside the ADSP to answer.
**Phone.** OnePlus 13 CPH2653. No restart. The desktop stayed up.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** The ADSP FastRPC device is up. `audio_pd` still
does not answer. The open daemon that stock uses to start it
resets an SM8750 on this kernel.

## What we did

`apr` bound `adsp_apps` and added q6apm (`gprsvc:service:2:1`)
and q6prm (`gprsvc:service:2:2`). Stock `adspua.jsn` names
`msm/adsp/audio_pd`, service `avs/audio`, instance 74, which is
what the DT and `pd_mapper` already say. The get-state command
`0x01001021` timed out, including after a reload. There is no
ALSA card. The lpass macros are in the DTB. The soundwire
controllers are disabled, and there is no `sndcard` node.

Stock's `vendor.qti.audio-adsprpc-service.rc` starts
`/vendor/bin/audioadsprpcd audiopd adsp` at early-init. The
ADSP is advertising `fastrpcglink-apps-dsp` and nothing binds
it. The only FastRPC node in our tree was on the CDSP, which
this boot does not start.

The dodge ADSP node uses compute banks 3 to 8, SIDs `0x1003`
to `0x1008` with the `0x104x` pair, not the SM8550 `0x106x`
pair. That node is now in `sm8750.dtsi`. The dodge DTB builds.
It is not in the image the phone is running.

## What the new boot did

The first image omitted `DTB_OPTS='splash fb'`, so
`simpledrm` never bound and Hyprland exited with
`CBackend::create() failed`. The second image has `splash fb`
and the FastRPC node. The desktop is back. `fastrpc.ko` binds
the ADSP channel and creates `/dev/fastrpc-adsp-secure`. The
six compute banks join IOMMU groups. The driver logs
`no reserved DMA memory for FASTRPC`. Stock's node has a
`memory-region` we did not copy. The modem and the CDSP stayed
down.

## Next

Stock starts the domain with `audioadsprpcd audiopd adsp`.
Upstream reports that this daemon resets an SM8750 on kernels
before the 2026 FastRPC audio fixes, which are not in 6.16.
Do not run it here. The get-state timeout stands until that
daemon, or the kernel fix, is in place. Do not play audio
until a card exists and a volume ceiling is set.
