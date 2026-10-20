#!/bin/bash
# SPDX-License-Identifier: MIT
# dodge audio bring-up, run on the phone as root after
# omamobile-adsp-battery.service has the ADSP running.
# Order matters: the FastRPC audio heap must be assigned before q6apm
# probes, or APM_CMD_GET_SPF_STATE times out.
# Never rmmod dodge-snd or unbind q6apm-dai after the topology loaded:
# that oopsed in snd_soc_unregister_component_by_driver (2026-10-20).
set -u
HELD=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
A=/root/audio
log() { echo "audio-bringup: $*"; }
loaded() { awk -v m="$1" '$1==m {f=1} END{exit !f}' /proc/modules; }
load() {
	local ko=$1; shift || true
	local n; n=$(basename "$ko" .ko); n=${n//-/_}
	loaded "$n" && return 0
	insmod "$ko" "$@" || { log "insmod $ko failed"; exit 1; }
}
for _ in $(seq 40); do
	[ "$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)" = running ] && break
	sleep 0.5
done
[ "$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)" = running ] || { log "ADSP not running"; exit 1; }

load "$A/fastrpc-audio.ko" audio_heap_vmids=1
for _ in $(seq 20); do [ -e /dev/fastrpc-adsp-secure ] && break; sleep 0.5; done
if ! systemctl is-active -q x-adsprpcd; then
	systemd-run --unit=x-adsprpcd -p WorkingDirectory=$A/fastrpc-src \
		-E LD_LIBRARY_PATH=$A/fastrpc-src/build \
		$A/fastrpc-src/build/adsprpcd audiopd adsp
fi
for _ in $(seq 40); do
	dmesg | grep -c "assigned audio heap" >/dev/null && break
	sleep 0.5
done
dmesg | grep -c "assigned audio heap" >/dev/null || { log "audio heap not assigned"; exit 1; }

load "$HELD/drivers/soc/qcom/apr.ko"
load "$HELD/sound/soc/qcom/qdsp6/snd-q6dsp-common.ko"
load "$HELD/sound/soc/qcom/qdsp6/snd-q6apm.ko"
load "$HELD/sound/soc/qcom/qdsp6/q6prm.ko"
load "$HELD/sound/soc/qcom/qdsp6/q6prm-clocks.ko"
for _ in $(seq 40); do
	[ -e /sys/bus/platform/devices/6800000.remoteproc:glink-edge:gpr:service@1:dais ] && break
	sleep 0.5
done
load "$HELD/sound/soc/qcom/qdsp6/q6apm-dai.ko"
# q6i2s_ops with .set_fmt, so the CPU can be the I2S clock provider
load "$A/q6apm-lpass-dais.ko"
# Speaker amplifiers: needs a DTB with i2c_hub_4 enabled (i2c-1 at
# bring-up). Their register tables, /lib/firmware/aw882308-3{4,5}.bin, come
# from the phone's own ACF (tools/aw-acf-regs.py) and stay off git.
case " $* " in *" amps=1 "*)
	bus=$(basename "$(dirname "$(readlink -f /sys/bus/platform/devices/990000.i2c/i2c-*/name)")")
	[ "$bus" = i2c-1 ] || { log "hub I2C4 is $bus, aw882308 expects i2c-1"; exit 1; }
	load "$A/aw882308.ko"
	for a in 0x34 0x35; do
		[ -e /sys/bus/i2c/devices/1-00${a#0x} ] ||
			echo aw882308 $a > /sys/bus/i2c/devices/i2c-1/new_device
	done
	;;
esac
load "$A/dodge-snd.ko" "$@"
sleep 1
cat /proc/asound/cards
