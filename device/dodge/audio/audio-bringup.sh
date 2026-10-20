#!/bin/bash
# SPDX-License-Identifier: MIT
# dodge speaker audio bring-up, run as root by omamobile-dodge-audio.service
# after omamobile-adsp-battery.service has the ADSP running. Installed as
# /usr/local/lib/omamobile/audio-bringup.sh. Needs a DTB with the sound card
# and amplifier nodes, and the patched modules in the module tree.
# Order matters: the FastRPC audio heap must be assigned before q6apm
# probes, or APM_CMD_GET_SPF_STATE times out.
# Never rmmod the card or unbind q6apm-dai after the topology loaded:
# that oopsed in snd_soc_unregister_component_by_driver (2026-10-20).
set -u
K=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
RPC=/usr/local/lib/omamobile/fastrpc
log() { echo "audio-bringup: $*"; }
load() {
	local ko=$1; shift || true
	local err
	err=$(insmod "$K/$ko" "$@" 2>&1) && return 0
	case $err in *"File exists"*) return 0 ;; esac	# already loaded
	log "insmod $ko failed: $err"; exit 1
}
[ -e /proc/device-tree/sound/compatible ] || { log "no sound node in this DTB"; exit 1; }
for _ in $(seq 40); do
	[ "$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)" = running ] && break
	sleep 0.5
done
[ "$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)" = running ] || { log "ADSP not running"; exit 1; }

load drivers/misc/fastrpc.ko audio_heap_vmids=1
[ "$(cat /sys/module/fastrpc/parameters/audio_heap_vmids 2>/dev/null)" = Y ] ||
	log "warning: fastrpc loaded without audio_heap_vmids"
for _ in $(seq 20); do [ -e /dev/fastrpc-adsp-secure ] && break; sleep 0.5; done
if ! systemctl is-active -q x-adsprpcd; then
	systemd-run --unit=x-adsprpcd -p WorkingDirectory=$RPC \
		-E LD_LIBRARY_PATH=$RPC $RPC/adsprpcd audiopd adsp
fi
for _ in $(seq 40); do
	dmesg | grep -q "assigned audio heap" && break
	sleep 0.5
done
dmesg | grep -q "assigned audio heap" || { log "audio heap not assigned"; exit 1; }

load drivers/soc/qcom/apr.ko
load sound/soc/qcom/qdsp6/snd-q6dsp-common.ko
load sound/soc/qcom/qdsp6/snd-q6apm.ko
load sound/soc/qcom/qdsp6/q6prm.ko
load sound/soc/qcom/qdsp6/q6prm-clocks.ko
for _ in $(seq 40); do
	[ -e /sys/bus/platform/devices/6800000.remoteproc:glink-edge:gpr:service@1:dais ] && break
	sleep 0.5
done
load sound/soc/qcom/qdsp6/q6apm-dai.ko
load sound/soc/qcom/qdsp6/q6apm-lpass-dais.ko	# patched: I2S .set_fmt

# Speaker amplifiers on hub I2C4. Register tables /lib/firmware/aw882308-3{4,5}.bin
# come from the phone's own ACF (audio/tools/aw-acf-regs.py) and stay off git.
load drivers/i2c/busses/i2c-qcom-geni.ko
load sound/soc/codecs/snd-soc-aw882308.ko

# Machine driver (patched: MI2S format, no jack on MI2S links).
load drivers/soundwire/soundwire-bus.ko
load sound/soc/qcom/snd-soc-qcom-common.ko
load sound/soc/qcom/snd-soc-qcom-sdw.ko
load sound/soc/qcom/snd-soc-sc8280xp.ko
for _ in $(seq 20); do grep -q OnePlusdodge /proc/asound/cards && break; sleep 0.5; done
cat /proc/asound/cards
