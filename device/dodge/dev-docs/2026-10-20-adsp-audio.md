<!-- SPDX-License-Identifier: MIT -->
# 2026-10-20 — ADSP audio

**Goal.** Get the audio framework inside the ADSP to answer.
**Phone.** OnePlus 13 CPH2653. No restart. The desktop stayed up.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** `APM_CMD_GET_SPF_STATE` returns after the audio
heap is assigned to the LPASS and ADSP-heap VMIDs. The open
`adsprpcd` stays up. Later the same day a bring-up card module
and our own topology gave card 0, `OnePlus-dodge`, with one
playback PCM. A new DTB enabled the amplifiers' I2C bus, and both
speaker amplifiers now run during playback from the SoC's I2S clocks
(see "The amplifiers"). With the topology on SD1, Martin heard a test
tone from the speakers at 11:39 CEST.

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

## The heap

The open `adsprpcd audiopd adsp` reaches its poll loop on
this kernel. The phone did not reset. `GET_SPF_STATE` still
timed out, and it timed out the same way with the daemon not
running: the audio domain is already marked up.

Stock's node sets `qcom,vmids` to `0x16 0x25`. This driver
allocated the 3 MiB heap and then sent `pageslen` 0, so the
DSP was told the heap was empty. With those VMIDs and
`pageslen` 1, the assign logged
`phys 0xf1e00000 size 0x300000`. The same get-state command
then returned, and `q6prm` probed without a timeout.

The VMIDs are not in the DTB the phone is running. The
module parameter `audio_heap_vmids=1` supplies them. The
daemon and that module are not on the boot path. There is
still no ALSA card, and the soundwire controllers stay
disabled. Do not play audio until a card exists and a
volume ceiling is set. Stock's 12 MiB remote-heap region
is not in this DTB.

## The card

**Speakers on stock.** The live DT names two `awinic,aw882xx_smartpa`
amplifiers on the hub I2C at `0x990000` (`i2c_hub_4`), addresses
`0x34` and `0x35`, reset on TLMM 2 and 164. They take Secondary MI2S
on TLMM `i2s1`: gpio121 `sck`, gpio122 `data0`, gpio123 `ws`,
gpio124 `data1`. The stock card says `qcom,msm-mi2s-master` (the
SoC drives the clocks), `qcom,wsa-max-devs = 0`, and WSA2 carries
the haptics. The headset codec is a WCD939x on the RX/TX
soundwire. None of the amplifiers' bus is enabled in our DTB.

**No DT change.** The running kernel has no `OF_OVERLAY`, so the
card is built in a module instead of a `qcom,sm8750-sndcard` node:
[`audio/dodge-snd/dodge-snd.c`](../audio/dodge-snd/dodge-snd.c).
One DPCM back end, `SEC_MI2S_RX`, the ASoC dummy codec, and the
q6apm component (`gprsvc:service:2:1`) as platform. The
q6apm `dais` and `bedais` nodes were already in the DTB;
`q6apm-dai`, `q6apm-lpass-dais` and `q6prm-clocks` bound when
loaded from the held tree.

**Topology.** [`audio/OnePlus-dodge.m4`](../audio/OnePlus-dodge.m4)
is MultiMedia1 playback into a Secondary MI2S device graph, SD0,
LPASS 11.0 containers, from linux-msm/audioreach-topology. The
kernel asks for `qcom/<driver_name>/<card name>-tplg.bin`, so the
file is `/lib/firmware/qcom/sm8750/OnePlus-dodge-tplg.bin`. A DT card
with `model = "OnePlus-dodge"` will load the same file. `alsatplg`
warns that `Secondary MI2S Playback` is undefined; the stream
widget comes from the back-end DAI at run time.

**First load.** Card 0 `sm8750 - OnePlus-dodge`, `pcmC0D0p`, the
controls `SECONDARY_MI2S_RX Audio Mixer MultiMedia1` and the
MultiMedia1 volume. No playback.

**The I2S clocks.** In this tree `q6i2s_ops` has no `.set_fmt`, so
the I2S module's `ws_src` stays external (0) and nothing drives
BCLK or WS. Upstream fixed the same symptom for Senary MI2S on the
Fairphone (Gen. 6) with `snd_soc_dai_set_fmt(cpu, BP_FP)` in the
sc8280xp machine driver, which needs `.set_fmt` on the I2S ops. The
patched `q6apm-lpass-dais.ko` adds it, and the card's link format
is `I2S | NB_NF | BC_FC` (codec consumer), so the CPU side gets
`BP_FP`.

**The oops.** Swapping modules meant `rmmod dodge_snd`. That left
`q6apm_dai` with a reference and its component still bound to a
`(null)` card, so the new card failed with `-19`. Unbinding
`q6apm-dai` through sysfs then oopsed in
`snd_soc_unregister_component_by_driver` (the topology's front-end
DAIs). The phone stayed up and SSH worked. Never unload the card
or unbind q6apm-dai after the topology has loaded; reboot instead.

**Before the reboot.** `/tmp` on the phone is tmpfs. The open
FastRPC build and `fastrpc-audio.ko` lived there, so they were
copied to `/root/audio/`.
[`audio/audio-bringup.sh`](../audio/audio-bringup.sh) is the
whole order: ADSP running, `fastrpc-audio.ko audio_heap_vmids=1`,
`adsprpcd`, wait for the heap assign, `apr`, q6dsp common, q6apm,
q6prm and its clocks, `q6apm-dai`, the patched
`q6apm-lpass-dais`, then the card.

## The amplifiers

**The bus.** One DTB change: `&i2c_hub_4 { status = "okay"; }`. The
chain image was rebuilt with only that DTB changed and flashed to
boot_a at 11:22 CEST. It booted; hub I2C4 enumerated as `i2c-1`.

**The chips.** In reset (TLMM 2 and 164 low) both addresses NACK.
Driving the resets high, the reverse of stock's active-low pulse,
gives chip id `0x2308` at `0x34` (left) and `0x35` (right).

**The driver.** [`audio/aw882308`](../audio/aw882308/aw882308.c) is
ours, written from the register layout in OnePlus's GPL-2.0 aw882xx
sources: `SYSCTRL` power-down, amplifier power-down, hard mute and
the ultrasonic mute, a 10-bit attenuation in `SYSCTRL2`, and the
I2S frame in `I2SCTRL1`. Start order matches the vendor driver:
power up, wait for PLL lock and stable clocks, power the amplifier,
wait for boost done, unmute. The resets come from a gpiod lookup
table because there is no DT node yet. A register table can come
from firmware, `aw882308-<addr>.bin`. Volume is a mixer control that
cannot go below 320 steps of attenuation (about -30 dB).

**The register table.** Stock loads `aw882xx_acf.bin` from odm.
[`audio/tools/aw-acf-regs.py`](../audio/tools/aw-acf-regs.py) lists
its sections and writes one profile per amplifier. This ACF uses
header version 0.0.0.1: four "default device" register sections,
profiles 0 (speaker) and 10 (receiver) for index 0 and 1. The two
speaker tables differ only in channel select and the TX slot
register. The ACF and the tables stay out of git. The driver keeps
power-down and mute set and the I/V feedback off when applying them.

**First sound attempt.** `aplay` of a -12 dBFS 440/660 Hz tone on
`hw:0,0` (S16, 48 kHz, stereo) after
`SECONDARY_MI2S_RX Audio Mixer MultiMedia1` on. Both amplifiers
start: SYSST `0x0215`, SYSINT 0, VBAT 3.9 V, 41 °C. After the
stream SYSCTRL reads `0xd343` again (powered down, muted).

**Frame check.** Rewriting `I2SCTRL1` mid-stream: 16-bit at 32 fs
keeps SYSST at `0x0215`; 64 fs (16, 24 or 32 bit) or 48 fs keep the
PLL locked but clear boost-done. So the DSP sends 32 fs, and the
driver's `hw_params` matches it.

**Is anything audible?** Not known. With the noise gate on (stock
`NGCTRL3` bit 0) the switching bit stays 0 during the tone. With
the gate off it goes to 1. Mono channel select changes nothing. The
current and voltage sense registers read static. That could mean
data0 carries silence. Stock's pins argue data0 is the playback
line: data1's active state is pulled down, like an input for the
amplifiers' feedback.

Claude's advice (consult 2): BROWN_OUTS in SYSST is a status bit,
not a latched fault. Short tests at -30 dB or quieter are milliwatts.
Keep the floor in the driver.

## Sound

**The data line.** One change per boot: the device subgraph's
`SD_LINE_IDX_I2S_SD0` became `SD_LINE_IDX_I2S_SD1`, the topology was
rebuilt and installed, and the phone rebooted. Nothing else changed:
same DTB, modules and register tables. The amplifiers' input is
i2s1 data1 (gpio124). Stock's pull-down on data1's active state was
misleading.

**Proof.** With the noise gate on, silence keeps SYSST at `0x0215`.
A -12 dBFS tone gives `0x0315` (switching), and DACST
(`0x0a1b` → `0x001b`) and VSNDAT move. Martin heard the tone at
11:39 CEST, at the -30 dB floor.

**After the reboot the bring-up script hit two problems.**
- It ran before udev loaded `i2c-qcom-geni`, so the script now
  loads the module and waits for the bus.
- `fastrpc-audio.ko` reported "File exists" because the module was
  already loaded under another name, so `load` now accepts that.

**Not done.**
- Start at boot.
- A `qcom,sm8750-sndcard` DT node with the amplifier nodes (resets,
  `sound-name-prefix`), so the lookup tables and `new_device` go away.
- Speaker protection and calibration, before the volume floor moves.
- Rates other than 48 kHz.
- UCM and PipeWire.
- I/V feedback on data0.
- The headset codec and the microphones.

## At boot

[`audio/omamobile-dodge-audio.service`](../audio/omamobile-dodge-audio.service)
is a oneshot unit that needs `omamobile-adsp-battery.service` and starts
after it. It runs the bring-up with `pins=1 amps=1` and sets the speaker
route. It is installed by hand, like the battery unit.

**The check.**
- Slot state over fastboot at 11:44 CEST: slot a, retry count 5,
  bootable. That needed no change.
- `fastboot reboot`.
- About 90 s after boot: the unit was active, card 0 was present
  with the route on, and `aplay` of the test tone exited 0 with both
  amplifiers switching.
- No manual step was needed.

## Amplifier nodes

One change for this boot: the DTB gained the two amplifier nodes on hub
I2C4. Each node has the provisional compatible `awinic,aw882308`, an
active-low `reset-gpios`, `#sound-dai-cells = <0>` and a
`sound-name-prefix`. The driver gained an OF match table, and its gpiod
lookup tables are now opt-in (`lookup=1`). The chain image was flashed to
boot_a at 11:49 CEST. After boot, `1-0034` and `1-0035` point at their DT
nodes, `lookup` reads `N`, both chips were identified and their tables
applied, and the test tone ran with both amplifiers switching.
