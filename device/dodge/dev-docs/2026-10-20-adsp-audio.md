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

## The DT card

One change for this boot: the DTB gained `/sound` (`qcom,sm8750-sndcard`,
model `OnePlus-dodge`). It has a `speaker-dai-link` from
`<&q6apmbedai SECONDARY_MI2S_RX>` to `<&speaker_left>, <&speaker_right>`
on `<&q6apm>`, and the pinctrl state for i2s1 (drive 4 mA, no bias, as on
stock).

The generic qcom machine driver doesn't parse a DAI format, so MI2S
links would leave the DSP's word select external. The patch in
`sound/soc/qcom/sc8280xp.c` sets I2S with the codec as consumer on
PRIMARY to QUATERNARY and QUINARY MI2S. It is built out of tree into
`/root/audio/snd-soc-sc8280xp.ko` (copy `sc8280xp.c`, `common.h`, `sdw.h`
and `qdsp6/q6afe.h`, then build with `KBUILD_MODPOST_WARN=1`). The script
loads `soundwire-bus`, `snd-soc-qcom-common` and `snd-soc-qcom-sdw` from
the held tree first.

The image was flashed at 11:53 CEST, and the try count was restored to 7
with `set_active a`. After boot the unit was active, card 0 was there
with the same controls, and `aplay` played the tone with both amplifiers
switching. The card name and the topology path did not change.

## Into the module tree

These are all modules, so this was not a DTB or Image change.

**Kernel**
- Added `sound/soc/codecs/aw882308.c` to `wt-dodge`, with `SND_SOC_AW882308` in Kconfig and the Makefile.
  - It is the repo driver without the gpiod lookup tables or the `lookup` parameter. Resets come from DT only.
- In `sc8280xp.c`, the MI2S case now returns before `qcom_snd_wcd_jack_setup()`.
- Committed as `bb98edce9` and `75068ed74`.
- Added `CONFIG_SND_SOC_AW882308=m` to `out-dodge/.config` (olddefconfig changed nothing else) and to `kernel/configs/omamobile-dodge.config`.
- Built the modules with `make O=out-dodge ARCH=arm64 LLVM=1 KERNELRELEASE=6.16.0-gb3ee311dab85 KBUILD_MODPOST_WARN=1 drivers/misc/fastrpc.ko sound/soc/qcom/qdsp6/q6apm-lpass-dais.ko sound/soc/qcom/snd-soc-sc8280xp.ko sound/soc/codecs/snd-soc-aw882308.ko`.
- Checked the result: the vermagic matches, `q6i2s_set_fmt` is present, the `audio_heap_vmids` parameter is present, and the amplifier driver has the OF alias `awinic,aw882308`.

**Phone**
- Copied the three original modules to `/root/held-orig` and installed the new ones into `/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel`. The checksums match the build.
- Moved `adsprpcd` and its libraries to `/usr/local/lib/omamobile/fastrpc`, and the script to `/usr/local/lib/omamobile`.
- Renamed `/root/audio` to `/root/audio.old`.

**Plain reboot at 12:00 CEST**
- The unit was active and card 0 was there.
- `fastrpc`, `q6apm_lpass_dais`, `snd_soc_sc8280xp` and `snd_soc_aw882308` were loaded from the tree.
- No jack controls.
- `aplay -D hw:0,0` played the tone, with SYSST 0x0315 on both amplifiers.

## UCM and PipeWire

The profile is `device/dodge/audio/ucm2/OnePlus/dodge/{OnePlus-dodge,HiFi}.conf`. On the phone it is in `/usr/share/alsa/ucm2/OnePlus/dodge/`, linked from `/usr/share/alsa/ucm2/conf.d/sm8750/OnePlus-dodge.conf`.

- `alsaucm -c hw:0` lists the verb HiFi and the device Speaker, with `PlaybackPCM` `hw:OnePlusdodge,0`.
- Before the profile, PipeWire showed the ACP fallback sink "Built-in Audio Stereo".
- After `systemctl --user restart wireplumber pipewire pipewire-pulse` (user ml), the sink is `alsa_output.platform-sound.HiFi__Speaker__sink` ("Built-in Audio Speaker playback"), the default, at volume 0.40.
- `pw-play -a --target <sink> --format s16 --rate 48000 --channels 2 /tmp/tone.raw` gave PCM RUNNING (S16_LE, 48 kHz, period 480) and both amplifiers at 0x0315.
- Without `-a`, `pw-play` rejects a raw file. It also cannot read from /root, because it runs as ml.

**Second boot, 12:10 CEST, by way of fastboot**
- The retry count read 5; `set_active a` set it back to 7.
- After boot the unit was active and there were no jack controls.
- The default sink was "Built-in Audio Speaker playback" with no PipeWire restart.
- `pw-play -a` of the tone left both amplifiers at 0x0315.

## Where the kernel commits live

Per AGENTS.md, kernel work stays on `omamobile-<subsystem>` branches in the kernel tree. Curated, upstream-ready commits go to `omamobile`, and the maintainer publishes that to derekross/linux-omarchy-mobile with `tools/publish-kernel`. The repo's `*.patch` series are for userspace packages.

`wt-dodge` is based on sm8750-mainline (16cf517b2781), not on `omamobile`, and its origin is not ours. So neither a push nor patches in the repo is clear-cut, and I left both to the human.

The local `format-patch` copy is in `~/android/mainline/patches-dodge`.

## Microphones (12:10 to 12:30 CEST)

The stock `mixer_paths.xml` (read from the OTA odm image into the captures directory, not committed) shows the built-in mics:
- `handset-mic` and `speaker-mic` use AMIC1 (ADC1) and AMIC5 (ADC4).
- The headset mic is AMIC2.
- There are no DMICs in use.
- `handset` is the left amplifier in its Receiver profile. That is the earpiece.

The stock DT (`live.dtb`) gives:
- WCD939x reset on GPIO 101.
- Supplies: L15B for buck, rx and tx; L2I for px; BOB1 for mic bias.
- Mic biases at 2700 mV.
- The SoundWire slaves are 0217:010e at device numbers 4 (RX) and 3 (TX).

**Runtime check first.** I loaded the LPI pinctrl and the VA, TX and RX macros by hand on the old DTB. All three macros and the LPI pinctrl probed (`7760000.pinctrl` bound to `qcom-sm8650-lpass-lpi-pinctrl`).

**One boot (12:18 CEST), DTB plus topology:**
- The codec node, the swr1/swr2 slaves, the routing and the capture link.
- The topology gained MultiMedia3 from TX_CODEC_DMA_TX_3 (IIDs 0x4003/0x6020 and 0x4009/0x6090, as in SM8550-HDK).
- Result: `wcd939x_codec audio-codec: bound sdw:2:0:0217:010e:00:4` and `sdw:3:...:3`. PCM `00-02: MultiMedia3 Capture`.

**Finding the channels:**
- With `TX SMIC MUX0` set to SWR_MIC1..3, `arecord` failed with EIO.
- SWR_MIC4..11 gave identical files: zeros, then a 480-frame period repeating. That is a stale buffer, not audio.
- SWR_MIC0 is live for ADC1. With ADC4 enabled, SWR_MIC3 is live for it.

**Evidence that it is sound:**
- The two mics correlate at 0.53, with a lag of 6 samples (about 4 cm).
- Their envelopes track each other: 84/171/142/51 against 132/286/229/94.
- With the ADC muted, the capture fails rather than reading zeros. So the data comes from the ADC.

**UCM:** the `Mic` device has the full enable and disable sequences. After a PipeWire restart there is a default source "Built-in Audio Internal microphones". `pw-record -a` gave -56.4 and -52.4 dBFS.

## Kernel fork and rebase (12:22 to 12:35 CEST)

**Audit:** the 31 commits on `omamobile-dodge` before the mic commit had no MACs, serials, IMEI, keys, home paths, binaries or hex tables. The amplifier driver loads its tables from firmware. `qcom,msm-id` and `qcom,board-id` are per-model, not per-unit. The authors are Martin, plus one upstream patch by Maulik Shah.

**Fork:** `gh auth status` says no host is logged in, so I created no fork and pushed nothing. Running `gh` made mise install `gh` 2.102.0.

**Rebase:** `maint/omamobile` (bb0877536c7a, v7.3-rc6, 146 commits on one squashed base commit) shares no history with `wt-dodge`, which sits on a single shallow sm8750-mainline commit (16cf517b2781, 6.16). A trial `cherry-pick` of each commit onto `maint/omamobile` in a throwaway worktree gave 4 clean picks and 28 failures:
- `sm8750-oneplus-dodge.dts` does not exist in omamobile. It is 1478 lines from sm8750-mainline.
- The ath12k peach series, MHI, fastrpc, q6apm-lpass-dais and q6v5_pas conflict.
- The rpmh-rsc v4 and pd-mapper changes are already in.

That makes it a port to a new kernel, followed by a fresh bring-up of dodge on 7.3. It is not a tidy rebase, so I stopped. The old branch is kept as `backup/omamobile-dodge-6.16`.

## USB-C headset (12:30 to 12:45 CEST)

The stock DT has `wcd939x_i2c@e` on `i2c@a8c000` (QUP I2C3), with a `vdd-usb-cp` supply on L15B and no reset GPIO. The DT follows sm8650-qrd: a USBSS node with `mode-switch`, `orientation-switch` and ports, connector `port@2` (SBU), the codec `port`, and the RX playback link. The topology adds RX_CODEC_DMA_RX_0 (IIDs 0x4007/0x6070).

**First boot (flash at 12:32 CEST):** the service failed with no card, showing `wcd939x-usbss: failed to acquire codec mode-switch` and `wcd939x_codec: failed to acquire orientation-switch`. The SoundWire slaves were already present, so `component_master_add_with_match()` bound inside `wcd939x_probe()`. The bind failed to get the USBSS switch, so probe returned -EPROBE_DEFER and devres unregistered the codec's typec mux. That left the USBSS waiting for a mux that never stays registered.

**Fix:** load `snd-soc-wcd939x-sdw`, `snd-soc-wcd939x`, `wcd939x-usbss`, then `slimbus` and `soundwire-qcom`. After a plain reboot (12:35 CEST) both drivers bound and the card has the jack controls.

**HPH check:**
- Both MultiMedia1 mixers on: `aplay` gets "Unable to install hw params".
- Only RX on: RUNNING, DAPM HPHL/HPHR PGA, HPHL and RX AIF1 PB on, and WCD 0x3009 = 0xf0 while playing (0x00 idle and after).
- Neither on: ACP fails to open `hw:0,0` with EINVAL. So the verb enables the speaker route and the MultiMedia3 route, and Headphones swaps MI2S for RX.
- With the profile forced to `HiFi (Headphones, Mic)` and no jack, PipeWire did not apply the device sequence and the audio went to the speaker. That is expected with the port unavailable.

**Altmode:** I armed `systemd-run --on-active=150 systemctl reboot`, then insmodded `aux-hpd-bridge` and `pmic_glink_altmode`. It bound to `pmic_glink.altmode.0`, SSH stayed up, the UDC stayed `configured`, and I stopped the timer.

**`jack-watch.sh`:** smoke-tested; it logs `hp=off mic=off udc=configured`.

## Earpiece

The earpiece uses the left AW882308 (0x34) in the stock Receiver profile, with the right amplifier muted through `Right Amp Volume` 0. Kernel commit `2e2290387` (local) adds an `Amp Profile` enum per amplifier. put/get only set and read the wanted profile. `aw882308_hw_params` applies the pending table (`aw882308-%02x-receiver.bin` for Receiver) and then stops the amplifier, before the I2S setup, whenever it is not running.

Two earlier designs failed:
- Returning -EBUSY while running broke the UCM disable sequence.
- A deferred apply at unmute overwrote I2SCTRL1, so the PLL did not lock (SYSST 0x0011, -110).

The receiver tables come from the stock ACF and stay local.

UCM device `Earpiece`: ConflictingDevice Speaker and Headphones; priority 50.

Verification by status register: in Earpiece, left SYSST reads 0x0311 and the right amplifier sits at attenuation 1023. Back on Speaker, both read 0x0315. The speaker attenuation cap of 700 is unchanged. No one has listened yet.

## Headset microphone

AMIC2 → ADC2 → `SWR_MIC1` → DEC0 → MultiMedia3 (hw:0,2), mono. No DTS or topology change was needed: the `AMIC2`←`MIC BIAS2` route and the TX codec DMA capture already exist.

Verified with no plug, using `arecord` with PipeWire stopped:
- The noise floor on DEC0 follows the ADC2 analog gain: -93.4, -82.4 and -67.6 dBFS at Volume 0, 10 and 20.
- With ADC2 off, the capture fails with EIO.

The UCM `Headset` device conflicts with `Mic`. Its Enable sequence writes `ADC2 MUX` twice (disable, then AMIC2), because a single write sometimes left ADC2 silent.

Several fast PipeWire stop/start cycles wedged the ADSP APM (`CMD timeout`, prepare -110). A reboot cleared it.

`jack-watch.sh` now records from the headset mic and plays a quiet tone when `Mic Jack` turns on. The plug test steps are in NOTES.md.

## Earpiece listen test (14:20 CEST)

The first try played on the speaker, about 14:20:30-14:20:50 CEST. The profile name was wrong: use `pactl set-card-profile alsa_card.platform-sound "HiFi (Earpiece, Mic)"`.

The second try played on the earpiece, about 14:21:01-14:21:21 CEST: 440/660 Hz alternating every 0.5 s at -12 dBFS, for 20 s.

While it played:
- The left amplifier loaded `aw882308-34-receiver.bin` (75 registers, chsel 1) and read SYSST 0x0211, SYSCTRL 0x42c0, attenuation 700.
- The right amplifier sat at attenuation 1023, muted.

Back to `HiFi (Mic, Speaker)` at 14:21:31 CEST.

The headset is accepted on the current evidence. The plug test was not run, because no headset was available.

## Silent after 11:39: the amplifier volume

Nothing was heard at 14:20/14:21. At 11:39 the amplifiers ran at attenuation 320 (volume control 703, the cap). After the next boot they came up at the driver default, 700 (about -66 dB), and nothing set them back. SYSST switching was taken as proof of sound; it is not.

Fix: UCM Speaker/Earpiece and the boot service set `Left/Right Amp Volume` 703. Route, tables, I2S format and PLL lock matched the 11:39 state.

Clock: there is no RTC device and no NTP route. The host user timer (`tools/dodge-timesync`, every 30 s) sets the clock, and timesyncd's clock file carries it across boots.

## Human-verified

Martin heard both:
- the speaker, triggered 14:29:21 CEST (both amplifiers at attenuation 320, SYSST 0x0315);
- the earpiece, triggered 14:30:54 CEST (left amplifier Receiver at attenuation 320, SYSST 0x0311; right amplifier muted at 1023).

Both played the 20 s 440/660 Hz -12 dBFS tone with `aplay -D hw:0,0`.

Boot defaults are verified over two reboots with no manual steps:
- the boot service sets both amplifiers to 703;
- WirePlumber's per-card default gives the speaker sink 0.85 (cubic) and the mic 1.0;
- the host timer corrects the clock within a minute of SSH coming up.

