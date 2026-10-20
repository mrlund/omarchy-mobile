# SPDX-License-Identifier: BSD-3-Clause
# AudioReach topology for the OnePlus 13 (dodge, SM8750).
# Derived from linux-msm/audioreach-topology SM8550-HDK.m4 and
# Google-SC7180-WSA-Speakers-SEC-I2S-VA-DMIC-WCD-TX3.m4 (Copyright, Linaro Ltd, 2023).
# Speakers: two smart amplifiers on Secondary MI2S (TLMM i2s1), playback on SD0.
# Build: m4 -I <audioreach-topology> OnePlus-dodge.m4 > OnePlus-dodge.conf
#        alsatplg -c OnePlus-dodge.conf -o OnePlus-dodge-tplg.bin
# Install on the phone as /lib/firmware/qcom/sm8750/OnePlus-dodge-tplg.bin
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
dnl Playback MultiMedia1
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004001, 0x00004001, 0x00006001, `110000')
dnl Secondary MI2S Playback (speaker amplifiers)
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-playback.m4, `Secondary', SECONDARY_MI2S_RX,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_SECONDARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,
	0x00004005, 0x00004005, 0x00006050, `SECONDARY_MI2S_RX')
dnl
STREAM_DEVICE_PLAYBACK_MIXER(SECONDARY_MI2S_RX, ``SECONDARY_MI2S_RX'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(SECONDARY_MI2S_RX, ``SECONDARY_MI2S_RX Audio Mixer'', ``MultiMedia1, stream0.logger1'')
