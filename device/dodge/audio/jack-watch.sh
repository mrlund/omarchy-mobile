#!/bin/bash
# SPDX-License-Identifier: MIT
# dodge: log USB-C headset (audio accessory) jack events for a plug test.
# The phone's only USB-C port is also the SSH link, so this runs detached
# and writes to /var/log/omamobile/jack.log: start it, unplug the cable,
# plug the headset (or a passive USB-C to 3.5 mm adapter) for ~20 s,
# unplug it, reconnect the cable and read the log.
# Loads pmic_glink_altmode, which delivers the Type-C audio mode to the
# WCD939x USBSS and codec (verified on 2026-10-20 not to disturb the USB
# gadget). Usage: jack-watch.sh [seconds]   (default 600)
set -u
K=/usr/lib/modules/$(uname -r).held/kernel
[ -d "$K" ] || K=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
L=/var/log/omamobile/jack.log
mkdir -p "${L%/*}"
for m in drivers/gpu/drm/bridge/aux-hpd-bridge.ko drivers/soc/qcom/pmic_glink_altmode.ko; do
	insmod "$K/$m" 2>/dev/null || true
done
dur=${1:-600}
setsid bash -c '
	L='"$L"'; end=$((SECONDS + '"$dur"')); last=
	echo "$(date +%T) start, typec: $(ls /sys/class/typec 2>/dev/null | tr "\n" " ")" >> "$L"
	dmesg -w --time-format iso | grep --line-buffered -iE "wcd|mbhc|usbss|typec|altmode|pmic_glink|jack" >> "$L" &
	dm=$!
	while [ $SECONDS -lt $end ]; do
		hp=$(amixer -c0 cget iface=CARD,name="Headphone Jack" 2>/dev/null | sed -n "s/.*: values=//p")
		mic=$(amixer -c0 cget iface=CARD,name="Mic Jack" 2>/dev/null | sed -n "s/.*: values=//p")
		udc=$(cat /sys/class/udc/*/state 2>/dev/null)
		cur="hp=$hp mic=$mic udc=$udc"
		[ "$cur" != "$last" ] && echo "$(date +%T) $cur" >> "$L" && last=$cur
		sleep 0.3
	done
	kill $dm; echo "$(date +%T) stop" >> "$L"
' </dev/null >/dev/null 2>&1 &
echo "logging to $L for ${dur}s"
