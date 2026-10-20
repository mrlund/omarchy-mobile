<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge) bring-up notes

Findings from this phone, newest first. The plan is [PLAN.md](PLAN.md).
Attempts live in [dev-docs/](dev-docs/).

## 2026-10-20: earpiece listen test (14:20 CEST), headset accepted

- **The first attempt played on the speaker** (about 14:20:30-14:20:50 CEST, the same 20 s tone). `pactl set-card-profile` was given an `output:...+input:...` name and answered "No such entity". On this card the profile name is the UCM string `HiFi (Earpiece, Mic)`. The dmesg lines showed both amplifiers in Speaker mode (SYSST 0x0215, attenuation 700).
- **The second attempt went to the earpiece: about 14:21:01-14:21:21 CEST** (laptop clock; the phone clock is not synced). A 20 s tone alternated 440 and 660 Hz every 0.5 s at -12 dBFS, played with `pw-play` on `alsa_output.platform-sound.HiFi__Earpiece__sink`. PipeWire was not restarted.
- **Register evidence while playing:**
  - Left (0x34): `applied 75 registers from aw882308-34-receiver.bin, SYSCTRL 0xc3c3 chsel 1`, then `running: SYSST 0x0211 SYSCTRL 0x42c0 atten 700`. In Speaker mode it reads SYSCTRL 0x5240.
  - Right (0x35): `SYSST 0x0215 atten 1023`, which is muted.
  - Controls: `Left Amp Profile` = 1 (Receiver), `Right Amp Volume` = 0.
  - The volume cap is unchanged (attenuation 700).
  - The left SYSST read 0x0211 this time, against 0x0311 earlier. Bit 8 differs; its meaning is not known.
- **Switched back** to `HiFi (Mic, Speaker)` at 14:21:31 CEST. The controls read `Left Amp Profile` 0 and `Right Amp Volume` 323. The speaker table is reloaded at the next stream's hw_params.
- **Whether it was audible** at the ear is Martin's report.
- **The headset is accepted on the current evidence** (Martin, 14:20; he has no headset). The playback chain is verified by DAPM and WCD 0x3009. The headset mic path is verified without a plug (gain-tracking noise floor, EIO when ADC2 is off). The UCM devices and the `jack-watch.sh` probe are in place. Real jack-detect events and MBHC have never been seen; the plug test stays available for whenever a headset is at hand.

## 2026-10-20: headset microphone (AMIC2), up to the plug test

- **No DTS or topology change needed.** The DTB already routes `AMIC2` from `MIC BIAS2` (commit `676c0daad`). The headset mic uses the same MultiMedia3 / `TX_CODEC_DMA_TX_3` capture as the built-in mics (hw:0,2).
- **The path:** AMIC2 → `ADC2 MUX` CH2_AMIC2 → ADC2 (`TX1 MODE` ADC_LP) → TX `SWR_MIC1` → `TX SMIC MUX0` → DEC0 → hw:0,2, mono. Stock `mixer_paths.xml` (`headset-mic` = `amic2`, ADC2 volume 10, DEC0 volume 84) agrees once the downstream channel names are mapped: stock ADC1 is `SWR_MIC4` and ADC2 is `SWR_MIC5`; upstream they are `SWR_MIC0` and `SWR_MIC1`.
- **Verified with nothing plugged in**, using raw `arecord` with PipeWire stopped:
  - ADC2 on gives a live noise floor on DEC0. It tracks the analog gain: ADC2 Volume 0 → -93.4 dBFS, 10 → -82.4, 20 → -67.6.
  - With ADC2 and its mixer off, the capture fails with EIO.
  - DAPM shows `MIC BIAS2`, `AMIC2` and `ADC2` On while capturing.
- **UCM `Headset` device** (conflicts with `Mic`; priority 300; `JackControl "Mic Jack"`; `CaptureMixerElem "ADC2"`). Mic → Headset → Mic switching via `alsaucm` passed every time, and the internal mics came back each time at -37.8 / -51 dBFS. PipeWire lists `HiFi (Headphones, Headset)`, `(Headset, Speaker)` and `(Earpiece, Headset)` as unavailable until the jack reports a mic.
- **Quirk:** a single `ADC2 MUX` CH2_AMIC2 write after the Mic device sometimes left ADC2 silent (the -96 dBFS floor, gain had no effect) until the mux moved again. The Enable sequence now writes CH2_AMIC_DISABLE, then CH2_AMIC2. Root cause not found.
- **Do not cycle PipeWire quickly.** Stopping and starting the user PipeWire units several times within a minute, with `alsaucm` and `arecord` in between, wedged the ADSP APM: `CMD timeout` for 0x100100d and then 0x1001006, and every PCM failed to prepare with -110. A reboot cleared it. Stop PipeWire once, test, start it once.
- **`jack-watch.sh` now probes on insertion.** When `Mic Jack` turns on, it logs the PipeWire profile and the default source/sink, records 6 s from the default source and logs the RMS. It then plays a 2 s 1 kHz tone at -36 dBFS and logs the HPH, MIC BIAS2 and ADC2 DAPM state during the tone. Smoke-tested without a jack by running the probe by hand (speaker profile, internal mic, -56.8 dBFS). The log times use the phone clock, which is not synced (it read 2026-09-26).
- **The plug test is still open.** It supersedes the earlier headset hands-on step:
  1. Over SSH: `sudo /usr/local/lib/omamobile/jack-watch.sh 600` (10 min window).
  2. Unplug the USB cable from the phone.
  3. Plug in a USB-C analog headset with a mic, or a passive USB-C to 3.5 mm adapter with a 4-pole (TRRS) headset. Leave it in for about 30 s. Talk or count aloud into the headset mic for the first 10 s. About 10 s after plugging, a short quiet beep should play in the earpieces.
  4. Unplug the headset, reconnect the cable, and send back `/var/log/omamobile/jack.log` (or just say "done" and it gets read over SSH), plus whether the beep was heard and in which ear.

## 2026-10-20: the kernel stays ours (decision 13:18 CEST)

- **Where it lives:** `~/android/mainline/wt-dodge`, branch `omamobile-dodge`, on sm8750-mainline/linux v6.16 `16cf517b2781` (shallow). It has 34 commits, head `2e2290387`, and builds to release `6.16.0-gb3ee311dab85`. Output goes to `~/android/mainline/out-dodge`.
- **No fork, no push.** The kernel commits stay local. The `maint` remote (the maintainer's tree) is for fetching only; its push URL is `DISABLED-no-push-to-maintainer`.
- **Backups:** `~/android/mainline/patches-dodge/` holds a full `git format-patch` of the series, refreshed at 13:19 CEST, with `BASE.txt`. `git am` onto the base reproduces the same tree (17c50d50c36d). The local ref `backup/omamobile-dodge-6.16` is a second backup.
- **Later todo** (PLAN §9): measure the maintainer `omamobile`'s SM8750 support, then port as a clean, PR-ready series to Martin's own fork only. Never push to the maintainer or open a PR there.

## 2026-10-20: earpiece (receiver) via the left amplifier

- **The earpiece is the left AW882308 (0x34) in its stock Receiver profile, with the right amplifier muted.** The stock ACF has a Receiver profile ("10"). Its register tables are extracted locally into `/lib/firmware/aw882308-3{4,5}-receiver.bin` on the phone and under `audio-local/receiver/` in the captures directory. They are not in git.
- **Kernel commit `2e2290387`** (local, `wt-dodge`) adds `Left/Right Amp Profile` (Speaker/Receiver). The control only records the wanted profile. `aw882308_hw_params` applies a pending profile (load table, then stop) before the I2S setup, so it takes effect at the next stream setup. The repo's out-of-tree `aw882308` copy does not have this control.
- **What failed first:** returning EBUSY while running aborted the UCM disable sequence. Applying at unmute clobbered I2SCTRL1, so the PLL never locked (SYSST 0x0011, start -110). Applying only in hw_params works.
- **UCM `Earpiece` device:** conflicts with Speaker and Headphones. Enable sets `Right Amp Volume` 0 (attenuation 1023, muted) and `Left Amp Profile` Receiver. Disable restores `Right Amp Volume` 323 and `Left Amp Profile` Speaker. Priority 50.
- **Verified by switching PipeWire profiles while playing:** Speaker gives both amplifiers SYSST 0x0315. `HiFi (Earpiece, Mic)` gives left 0x0311 with the receiver table and right muted at 1023. Back to Speaker gives both at 0x0315. The speaker attenuation stayed at 700, so the volume cap is unchanged. Speaker protection was not touched. Nobody has listened at the earpiece yet.
- **Boots at about 12:40-12:51 CEST** (module and UCM iterations, one change per boot). After several plain reboots the retry count read 2. `fastboot set_active a` set it back to 7 at 12:51 CEST.
- **After the 12:51 boot:** the service is active, PCMs hw:0,0 and hw:0,2 are present, and the PipeWire speaker sink and mic source are there. The profiles are `(Mic, Speaker)` (active), `(Earpiece, Mic)` and `(Headphones, Mic)` (unavailable without a jack). arecord gives -37.9 and -51.1 dBFS with no 480-frame repeat.

## 2026-10-20: USB-C headset path (needs a plug test)

- **The DTB has the WCD939x USBSS** (`typec-mux@e` on QUP I2C3, L15B, no reset line), linked to the pmic-glink connector's SBU port and to the codec's headset port. The codec has `mode-switch` and `orientation-switch`, and there is a `wcd-playback-dai-link` from RX codec DMA 0. Kernel commit `a28fd268d` in `wt-dodge`.
  - The topology gained RX_CODEC_DMA_RX_0 with a MultiMedia1 mixer.
- **Flashed at 12:32 CEST**; the previous image is `boot-chain-avb.before-headset.img`. The retry count read 6; `set_active a` set it to 7.
  - On that first boot the codec and the USBSS deferred on each other. The codec had bound its SoundWire slaves inside probe and failed to get the USBSS switch, which unregistered its mode switch, so the USBSS never found it.
  - Fix: the script loads `snd-soc-wcd939x` and `wcd939x-usbss` before `soundwire-qcom`. After a plain reboot (12:35 CEST) both bound, the card came up with `Headphone Jack` and `Mic Jack` (both off), and the speaker and mics are unchanged.
- **The HPH chain plays, checked by register.** With only `RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1` on and the upstream headphone sequences, `aplay` ran (PCM RUNNING). HPHL/HPHR PGA were on in DAPM, and WCD register 0x3009 read 0xf0 while playing and 0x00 when idle.
  - **With both the speaker and RX mixers on, `hw_params` fails.** With neither on, the PCM cannot be opened (EINVAL).
  - So UCM keeps the speaker route as the default and the `Headphones` device swaps it out. PipeWire shows the profiles `HiFi (Mic, Speaker)` (active) and `HiFi (Headphones, Mic)`. With the jack unplugged, the Headphones port is unavailable and its sequence is not applied.
- **Jack detection needs `pmic_glink_altmode`.** It is not loaded at boot. I loaded it by hand under a 150 s dead-man reboot timer: it bound and the USB gadget stayed `configured`. `/sys/class/typec` stays empty, because ucsi is not loaded.
- **Hands-on step: a plug test.** The only USB-C port is also the SSH link. Run `/usr/local/lib/omamobile/jack-watch.sh 600`, which loads altmode and logs the jack controls and the codec/typec dmesg lines to `/var/log/omamobile/jack.log`. Then unplug the cable, plug in an analog USB-C headset or a passive USB-C to 3.5 mm adapter for about 20 s, unplug it, reconnect the cable and read the log.

## 2026-10-20: built-in microphones

- **The DTB has the WCD939x** (`qcom,wcd9395-codec`, reset GPIO 101, supplies L15B/BOB1 as on stock, mic biases at 2.7 V). It has an RX slave on swr1 (0,4), a TX slave on swr2 (0,3), and a `wcd-capture-dai-link` from TX codec DMA 3. The routing follows the stock mic biases.
  - Kernel commit `676c0daad` in `wt-dodge`.
  - The topology gained MultiMedia3 capture from TX_CODEC_DMA_TX_3, so the PCM is `hw:0,2`.
  - The script loads the LPASS LPI pinctrl, the VA/TX/RX macros, soundwire-qcom and the WCD939x modules when the DTB has `/audio-codec`.
- **Flashed at 12:18 CEST**; the previous image is `boot-chain-avb.before-wcd.img`. The retry count read 6; `set_active a` set it to 7.
  - Both SoundWire slaves bound and the card came up. The speaker path is unchanged.
- **The mics are AMIC1 and AMIC5** (stock `handset-mic`, both on MIC BIAS1). With the upstream port map, ADC1 arrives on TX `SWR_MIC0` and ADC4 on `SWR_MIC3`.
  - Selecting a channel with no active port gives `arecord` an I/O error, or a stale period that repeats every 480 frames. So check for that before believing an RMS figure.
- **Verified without a human:** a stereo `arecord -D hw:0,2` gave -57.8 and -45.1 dBFS ambient. The two mics correlate at 0.53, 6 samples apart, and their 200 ms envelopes rise and fall together, which means sound, not electrical noise.
  - The capped speaker tone (-12 dBFS, attenuation 700) barely shows at the mic, so that was no use as a loopback test.
- **UCM device `Mic`** on `hw:CARD,2` (2 channels). WirePlumber lists `Built-in Audio Internal microphones` as the default source. `pw-record` gave -56.4 and -52.4 dBFS.
- **Kernel fork: not done.** `gh` on Omarchy is not logged in, so no `mrlund/linux-omarchy-mobile` fork was created and nothing was pushed.
  - A trial cherry-pick of the 32 commits onto the maintainer's `omamobile` (v7.3-rc6) applied only 4. The dodge DTS does not exist there, and the audio, ath12k, MHI and fastrpc code has moved a lot since 6.16. That makes it a port to a new kernel, not a rebase. Details are in the dev-doc.
  - The maintainer's repository is the remote `maint` in `wt-dodge`, with push disabled. The old branch is kept as `backup/omamobile-dodge-6.16`.

## 2026-10-20: audio from the module tree, and a UCM profile

- **Nothing loads from `/root/audio` any more.** The patched `fastrpc`, `q6apm-lpass-dais` and `snd-soc-sc8280xp` modules, and the amplifier driver (now in the kernel as `snd-soc-aw882308`, `CONFIG_SND_SOC_AW882308=m`), were built in `out-dodge` and installed into the held module tree. The originals are kept in `/root/held-orig` on the phone. The Image did not change: all four are modules.
  - `adsprpcd` and its two libraries are now in `/usr/local/lib/omamobile/fastrpc`, and the script is `/usr/local/lib/omamobile/audio-bringup.sh`. The unit runs it with no arguments.
  - The script now requires the DT sound node. The `dodge-snd` and `new_device` fallbacks are gone. `device/dodge/audio/aw882308` and `dodge-snd` stay in the repo, because the kernel commits are not published yet.
  - `/root/audio` was renamed to `/root/audio.old` to prove that nothing uses it.
- **The machine driver no longer adds `Headphone Jack` or `Mic Jack`.** sc8280xp returns before the WCD jack setup on MI2S links.
- **Verified after a plain reboot at 12:00 CEST:** the unit was active and the four modules were loaded from the tree, with `audio_heap_vmids=Y`. The controls are only the two Amp Volumes, the route and the stream volume. `aplay` played the tone with both amplifiers at SYSST 0x0315.
- **UCM: `ucm2/OnePlus/dodge/`**, linked from `conf.d/sm8750/OnePlus-dodge.conf` (card driver `sm8750`, long name `OnePlus-dodge`). It has the HiFi verb and the Speaker device on `hw:CARD,0`, and it turns on the `SECONDARY_MI2S_RX Audio Mixer MultiMedia1` route. The amplifier gain stays at the driver default (attenuation 700).
  - After restarting WirePlumber and PipeWire, `wpctl status` lists the sink `Built-in Audio Speaker playback` (`alsa_output.platform-sound.HiFi__Speaker__sink`), which is the default.
  - `pw-play -a --format s16 --rate 48000 --channels 2` ran a tone through it: PCM RUNNING at S16_LE/48 kHz, and both amplifiers at 0x0315. `pw-play` needs `-a` for raw files.
- **A second boot at 12:10 CEST also came up on its own**, by way of fastboot. The retry count read 5; `set_active a` set it back to 7. On that boot the speaker sink was the default with no PipeWire restart, and `pw-play` reached both amplifiers.
- **Kernel commits:** 31 on `omamobile-dodge` over 16cf517b2781, local only. A `git format-patch` copy is in `~/android/mainline/patches-dodge`, outside the repo.

## 2026-10-20: a DT sound card

- **The DTB has a `sound` node:** `qcom,sm8750-sndcard`, model `OnePlus-dodge`, one link from Secondary MI2S RX to both amplifiers on q6apm, and an `i2s1-active-state` for gpio121-124. The machine driver is `snd-soc-sc8280xp`, patched to call `snd_soc_runtime_set_dai_fmt(I2S | NB_NF | BC_FC)` on MI2S links.
  - The patched module is built out of tree into `/root/audio`, like `q6apm-lpass-dais`.
  - Kernel commits in `wt-dodge`.
- **Flashed to boot_a at 11:53 CEST**; the previous image is `boot-chain-avb.before-sndcard.img`. The retry count read 6, and I restored it with `fastboot set_active a` (now 7).
- **The boot came up with no manual steps.** The audio unit loaded the machine driver instead of `dodge-snd`. Card 0 has the same name and controls, and the DT pinctrl holds the i2s1 pins. `aplay` of the tone exited 0 with both amplifiers switching.
- **`dodge-snd` and the gpiod lookups now only serve DTBs without these nodes.** The bring-up script picks the path from `/proc/device-tree/sound`.
- **The machine driver adds `Headphone Jack` and `Mic Jack` controls** (its WCD jack helper). There is no headset support behind them yet.

## 2026-10-20: the amplifiers come from the DT

- **The DTB now has `audio-codec@34` and `@35` on hub I2C4** (`awinic,aw882308`, a provisional compatible): reset-gpios TLMM 2 and 164 active low, `sound-name-prefix` Left and Right. Kernel commit in `wt-dodge` on `omamobile-dodge`.
- **Flashed to boot_a at 11:49 CEST**; the previous image is `boot-chain-avb.before-amp-nodes.img`. The retry count read 4 before the flash.
- **That boot needed no help.** The clients exist at boot with an `of_node`, the driver got the resets from DT (its `lookup` parameter is now off by default), and the audio unit finished. The tone played with both amplifiers switching.
- **The bring-up script only falls back to `new_device` + `lookup=1` when there are no DT nodes.**

## 2026-10-20: speakers at boot

- **`audio/omamobile-dodge-audio.service` runs `audio-bringup.sh pins=1 amps=1` after the ADSP battery service,** then turns on the MultiMedia1 → speakers route. It is installed by hand in `/etc/systemd/system` and enabled, like the battery unit.
- **It works across a real reboot.** I read the slot state over fastboot at 11:44 CEST: current slot a, retry count 5, not unbootable, so no `set_active` was needed. Then a plain `fastboot reboot`.
- **After that boot:** the unit finished 7 s after starting and card 0 was there with the route on. `aplay -D hw:0,0 -f S16_LE -r 48000 -c 2 -t raw tone.raw` exited 0 with both amplifiers switching (SYSST `0x0315`). The driver's default level is attenuation 700 (about -66 dB); the -30 dB floor is unchanged.
- **The 122 local commits were audited before the push.**
  - No MACs, IMEIs, serials or live device identifiers (checked against the phone's own, which were not printed), no keys or tokens, and no other users' paths.
  - The only binary is the fork's public signing key.
  - No ACF, register tables or firmware are in the commits.
  - The author email is the one Martin already uses publicly on GitHub.
  - `dodge-plan` was pushed to the fork (`origin`) as a branch, as CONTRIBUTING's PR flow has it.

## 2026-10-20: sound from the speakers

- **Martin heard the phone at 11:39 CEST.** That was a -12 dBFS 440/660 Hz tone through both amplifiers at the -30 dB volume floor.
- **What fixed it: the topology's I2S data line, SD0 → SD1.** The amplifiers listen on i2s1 data1 (gpio124). On SD0 they ran but saw silence. The change is one token in `audio/OnePlus-dodge.m4`, then a reboot, because the card can't be unloaded.
- **The amplifiers confirm it:** silence gives SYSST `0x0215` (not switching, noise gate closed). The tone gives `0x0315` (switching), and DACST and the voltage sense change with it.
- **To reproduce after a boot**, install `OnePlus-dodge-tplg.bin` from the m4 at `/lib/firmware/qcom/sm8750/`, put `aw882308-3{4,5}.bin` (from `aw-acf-regs.py`, local only) in `/lib/firmware`, and copy the modules to `/root/audio`. Then run `audio-bringup.sh pins=1 amps=1`, `amixer -c0 cset name="SECONDARY_MI2S_RX Audio Mixer MultiMedia1" 1` and `aplay -D hw:0,0 -f S16_LE -r 48000 -c 2 <file>`. The bring-up script now loads `i2c-qcom-geni` itself and tolerates modules that are already loaded.
- **Still missing:**
  - It doesn't start at boot.
  - There is no DT sound node or amplifier nodes; the bus number and reset lookups are hard-coded.
  - No speaker protection or calibration, so the volume stays capped at -30 dB.
  - Only S16 at 48 kHz.
  - No UCM or PipeWire profile.
  - No I/V feedback, earpiece profile, headset (WCD939x) or microphones.

## 2026-10-20: the speaker amplifiers run, not yet heard

- **A DTB with `i2c_hub_4` enabled booted from boot_a** (chain image flashed 11:22 CEST, previous image kept as `boot-chain-avb.before-audio-i2c.img`). Hub I2C4 is `i2c-1`. SSH, the desktop and the ADSP battery service came back.
- **Both amplifiers answer: chip id `0x2308` at `0x34` and `0x35`** once their active-low resets (TLMM 2, 164) are released. In reset they NACK.
- **`audio/aw882308` is a small bring-up codec driver,** written from the register layout in OnePlus's GPL aw882xx sources. It takes the resets from a gpiod lookup, applies an optional register table from firmware and caps the volume (attenuation floor 320 steps, about -30 dB). There is no speaker protection.
- **`audio/tools/aw-acf-regs.py` turns the phone's own ACF into those tables.** The ACF comes from the OTA's odm image and stays in `~/android/reference`; the tables sit in the phone's `/lib/firmware` only. Profile 0 is the speaker profile, 10 the receiver one; index 0 is the left amplifier, 1 the right.
- **`dodge-snd amps=1 pins=1` makes the two amplifiers the codecs** (prefixes `Left`/`Right`, link format `CBC_CFC`). The first try failed with `-16`: both added `Amp Volume`. Prefixes fixed it; rmmod and insmod of the failed card worked.
- **During a tone both amplifiers run:** SYSST `0x0215` (PLL locked, clocks stable, boost done), no interrupts, VBAT 3.9 V, 41 °C. After the stream they are powered down and muted again.
- **Their frame must be 32 fs for S16.** Writing 64 fs or other widths mid-stream keeps the PLL but drops the boost-done bit.
- **Not proven audible.** With the stock noise gate on, the switching bit stays 0 during a -12 dBFS tone, which may mean the amplifiers see silence on data0. With the gate off they switch. The current and voltage sense registers stay static. Stock's pin config suggests data0 is playback and data1 the feedback input.

## 2026-10-20: an ALSA card, no sound yet

- **Card 0 is `OnePlus-dodge`, made by a module, not the DTB.** `dodge-snd.ko` registers Secondary MI2S RX on q6apm with the dummy codec; `/lib/firmware/qcom/sm8750/OnePlus-dodge-tplg.bin` (our topology) supplies MultiMedia1. `pcmC0D0p` exists. Nothing was played.
- **The speakers are two aw882xx amplifiers on Secondary MI2S** (TLMM i2s1, gpio121-124), controlled on `i2c_hub_4` at `0x34`/`0x35`, resets on TLMM 2 and 164. The SoC is the I2S clock provider on stock.
- **This tree's `q6i2s_ops` lacks `.set_fmt`,** so the DSP never drives BCLK/WS. The patched `q6apm-lpass-dais.ko` in `/root/audio` adds it.
- **Never `rmmod` the card or unbind `q6apm-dai` after the topology loaded.** It leaked a reference, then the unbind oopsed in `snd_soc_unregister_component_by_driver`. Reboot instead.
- **Phone `/tmp` is tmpfs.** The audio FastRPC module and the open `adsprpcd` build now live in `/root/audio`. `device/dodge/audio/audio-bringup.sh` loads everything in order.
- **Out-of-tree module builds against `out-dodge` must keep `kernel.release` at the running `6.16.0-gb3ee311dab85`.** A `make` in the worktree regenerated it as `-g932f80d728bd-dirty`; `make KERNELRELEASE=6.16.0-gb3ee311dab85 prepare` put it back. Build in-tree modules out of tree with `KBUILD_MODPOST_WARN=1`: this `Module.symvers` lacks module exports.

## 2026-10-20: the audio framework answers

- **`APM_CMD_GET_SPF_STATE` returns once the audio heap is assigned.** It times out with or without `adsprpcd` until then. Stock's ADSP FastRPC node sets `qcom,vmids` to `0x16 0x25` (LPASS and the ADSP heap). This 6.16 driver sent `pageslen` 0, so the DSP was told the heap was empty.
- **The open daemon stays in its poll loop.** The assign was `phys 0xf1e00000`, `size 0x300000`, two VMIDs. The phone did not reset. `q6prm` probed afterwards and did not time out. There is still no ALSA card, and soundwire stays disabled. Do not play audio.
- **The running DTB has the FastRPC node and `splash fb`.** `/dev/fastrpc-adsp-secure` exists. The VMIDs are not in that DTB yet; the loaded module supplies them with `audio_heap_vmids=1`. The first image of this series omitted the splash framebuffer and Hyprland had no DRM device.
- **A dead-man reboot fired while that timer was still armed.** The desktop came back. Slot A's try count was not read afterwards.

## 2026-10-19: the ADSP reports a battery percent

- **Capacity reads 69, status Discharging, 4.059 V, 34.1 °C.** The supplies are `qcom-battmgr-bat`. The ADSP is `running`. The modem and the CDSP were not started.
- **`qrtr-smd` has to be loaded before PDR looks up `msm/adsp/charger_pd`.** `pd_mapper` also needs a `qcom,sm8750` domain list, the same one as SM8550. Without either, every property returns `EAGAIN`.
- **Load the PAS driver with `only_adsp=1`.** The board enables the modem and CDSP nodes, and probing the modem assigns its RAM to the modem VM.
- **A cold boot brings the percent back.** `omamobile-adsp-battery.service` finished successfully, the ADSP was running, and capacity was 67. The USB supply was an SDP at 500 mA. The battery status stayed Discharging.
- **These figures are suspect.** The pack should have been charging from USB and the percent should have been nearer 85. `voltage_max` read 8.9 V, `charge_full` failed, and `power_now` did not match the current. Review the battmgr property scaling and the unknown notifications before trusting the gauge. Left as-is on 2026-10-20.

## 2026-10-19: the DT fuel gauge does not answer

- **`ti,bq27541` at I2C `0x55` NACKs.** The bus at `98c000` comes up. Address `0x36` ACKs and returns `0xffff`. Stock's percent path is `oplus_adsp_gauge` behind `oplus,virtual_gauge`, not this node.
- **The PMIC temperature alarms probe.** All nine sit in stage 0, which this driver reports as 37.0 °C. They are not loaded at boot.

## 2026-10-19: IO LDO high-power mode does not clear the aux assert

- **L2F and L3F at stock's 30 mA sit in high-power mode.** `fw_caps` stays `0xf`. Aux is still QMI error 90, and the dump asserts in the same aux-MAC wakeup (`line#192`). Mode 0 times out. No `wlan`. ath12k stays bound.
- **The restart before that probe found slot A out of tries.** `fastboot set_active a` (already current) restored seven. Slot B stayed unbootable. The success bit is still clear.

## 2026-10-19: mission mode crashes the same way

- **Mode 0, with ini and config, still times out.** The firmware enters RDDM about 160 ms after the rejected aux download. Host feature `0x58` does not change `fw_caps` (`0xf`). HW_XPA in the board response is 1, matching stock. ath12k stays bound.

## 2026-10-19: the firmware asserts in the aux MAC wakeup

- **The BDF response says `host bdf data 0x1`, HW_XPA set.** That matches stock's `HW_XPA: 1`.
- **The reset is RDDM.** The crash dump asserts in `cmnos_assert_patched.c:604`, recorded as `Asserted in:0x1a9046c:0x1a90c80, line#192`. The strings beside it are `whal_aux_mac_trigger_wakeup` and the aux PLL ready bits.
- **Host feature bit 6 does not change `fw_caps`.** It stays `0xf`. Sending `aux_ucode20.elf` anyway is still QMI error 90. The QDSS config is error 90 too. ath12k stays bound. The dump is in `~/android/reference/dodge-cph2653/stock-session-2026-10-19/devcd1.bin`.

## 2026-10-19: the QDSS config is rejected too

- **`qdss_trace_config_v2.cfg` (6241 bytes) is answered with QMI error 90.** Regdb, `bdwlan.b0e`, and `phy_ucode20.elf` were sent first. The firmware still resets about 195 ms after the board file, the same interval as the probe that did not send this file. Mode 7 times out. ath12k stays bound.

## 2026-10-19: aux is not advertised, and the reset remains

- **Target cap `fw_caps` is `0xf`.** Bit 6, the aux feature, is clear, so aux was not sent. Regdb (24278 bytes), `bdwlan.b0e`, and `phy_ucode20.elf` were sent. The firmware still resets about 160 ms later and mode 7 times out. ath12k stays bound.

## 2026-10-19: peach PHY ucode is accepted, aux is not

- **`phy_ucode20.elf` downloads with no M3 error.** `aux_ucode20.elf` is rejected with QMI error 90, incompatible state. The firmware still resets and mode 7 times out. The board file in that probe was stock `bdwlan.b0e`. ath12k stays bound. The phone clock was set to 2026-10-19 16:54 CEST; NTP is off.

## 2026-10-17: skipping TME-Lite does not stop the reset

- **With `skip_tme=1`, ini and config are accepted and the firmware still resets** about 190 ms after the board file. Mode 0 then times out. The same reset happens when TME-Lite is sent and rejected. ath12k stays bound.
- **The boot try count hit zero** during these restarts. `fastboot set_active a` put seven tries back. Slot B was left unbootable. The success bit is still clear.

## 2026-10-17: stock's DMA window also resets peach early

- **Host cap `ddr_range` start 0 size `0x68000000`, with the segments inside it, resets the firmware** before the memory acknowledgement. Same shape as the 36-bit aperture. The module on disk does not send the field. ath12k stays bound.

## 2026-10-17: stock PDC messages still get TME error 83

- **The AOSS accepted stock's four `wlan_pdc` strings for S5F** (mode, voltage enable, 876 mV up and down) before WLAN enable. There is no `qcom,vreg_ol_cpr` in the stock node. TME-Lite is still `err 83`. No `wlan`. ath12k stays bound.

## 2026-10-17: low DMA addresses still get TME error 83

- **A 28-bit DMA mask put the three firmware segments at `0x0e800000`, `0x0e400000`, and `0x0e3ff000`.** That is inside stock's low window. The firmware reached TME-Lite and answered `err 83` again, then reset. No `wlan`. ath12k stays bound.

## 2026-10-17: a 36-bit DMA window resets peach before TME

- **The firmware asks for three memory segments:** type 1 (7.4 MB), type 4 (4.1 MB), and type 11 (4 KB). Each received a DMA address. Type 11 was already allocated by the driver.
- **Advertising the stage-1 aperture (`0` size `0x1000000000`) makes the firmware reset** before it acknowledges that memory. No TME request on that boot. The module that does not send the window is on disk and is not loaded. ath12k stays bound.

## 2026-10-17: stock rails do not clear TME error 83

- **S5F and S4D at 876 mV, S7I at 1312 mV, and `wcn_sw` / `wcn_sw_ctrl` still get TME-Lite `err 83`.** The firmware resets and mode 7 times out. No `wlan`. ath12k stays bound.
- **Slot A has a seven-boot budget.** Linux never sets `boot_a`'s success bit, so a later restart drops into fastboot with the slot unbootable. `fastboot set_active a` restores the tries without touching slot B. The storage guard refuses the GPT write that would mark the boot successful. Do not restart until that bit is set.
- **Do not `insmod` ath12k twice on one boot.**

## 2026-10-17: the mode timeout is after a rejected TME-Lite download

- **The same PCI id is ported on the OnePlus 13s.**
  `renhiyama/pagani-linux` commit `c49d202` sends
  `tmel_peach_20.elf` over QMI before board data, skips a
  separate M3, and runs cold-boot calibration (WLAN mode 7)
  before mission mode. It names that as the fix for set-mode
  `-110`.
- **This phone's firmware rejects the TME-Lite request**
  (`result 1, err 83`) and then resets (`ignore reset dev
  flags`). Mode 0 and mode 7 both time out. The stock board ELF
  (`board.bin`, 125420 bytes) was sent and the reset still
  happened. No `wlan`.
- **Do not `insmod` ath12k twice on one boot.** The second load
  oopses in `mhi_queue_skb`. The module is bound. The desktop
  is up.

## 2026-10-17: peach Wi-Fi firmware reaches AMSS

- **`amss20.bin` is two ELF files.** The first 512 KiB is an ARM
  SBL. The WLAN firmware ELF starts at offset 512 KiB. BHIe has to
  send that second file on its own.
- **`BHI_EXECENV` is already SBL when MHI prints the wait.** The
  event-ring packet does not arrive. Reading the register and
  continuing is what gets the chip to AMSS. QMI then reports
  `WLAN.GNG.1.0-03342`. No `wlan` interface yet. The mode request
  timed out after a warning for memory type 11.
- **Do not reload ath12k on this boot.** A second `insmod` oopsed
  in `mhi_queue_skb` and the SMMU faulted (SID `0x1401`). The
  module is bound and the desktop is up. Leave it. If the session
  dies, `sync` then `echo b > /proc/sysrq-trigger`.

## 2026-10-17: the Omarchy root fills userdata

- **`resize2fs` online took `/dev/sda15` from 10.5 GiB to 453 GiB**
  (120554767 blocks of 4 KiB, the whole partition). The image had
  `resize_inode` and 1024 reserved GDT blocks. No `ufshcd` error.
  The 2026-10-16 grow was the Arch root this image replaced.

## 2026-10-16: SSH, and the timezone screen

- **The timezone screen is `systemd-firstboot`.** Its description is
  `Initial Setup`. `ConditionFirstBoot=yes` while `/etc/machine-id` is
  the word `uninitialized`, and the unit is `Before=sysinit`, so it
  holds the boot on the console (locale, keymap, timezone, root
  password) and `sshd` never starts. This phone has no keyboard and
  the touchscreen driver is not loaded. Seed machine-id, or mask the
  unit. Do not wait for someone to tap it.
- **OpenSSH 10.6 refuses a locked root when `UsePAM` is off.** The
  packaged config has `UsePAM yes` and `PermitRootLogin
  prohibit-password`. An early config with `UsePAM no` logged
  `User root not allowed because account is locked` and never tried
  `authorized_keys`. Leave the root password locked.
- **`openssh` 10.6p1-2 does not create the `sshd` user.** Without it,
  `sshd-session` exits (`unknown [priv]`) and the client sees a
  publickey denial or a connection reset. The device package ships
  `usr/lib/sysusers.d/sshd.conf`.
- **The module tree stays held** (`6.16.0-gb3ee311dab85.held`).
  Loading it, `msm` included, is what blacked the panel. `plymouth-start`
  stays masked.
