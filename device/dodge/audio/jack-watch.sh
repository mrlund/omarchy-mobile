#!/bin/bash
# SPDX-License-Identifier: MIT
# dodge: USB-C headset plug test. Logs jack events and checks the headset
# mic and headphone path once a headset shows up.
# The phone's only USB-C port is also the SSH link, so this runs detached
# and writes to /var/log/omamobile/jack.log. Start it as root, unplug the
# cable, plug the headset (or a passive USB-C to 3.5 mm adapter with a
# 4-pole headset) for about 30 s, talking into its mic for the first 10 s,
# unplug it, reconnect the cable and read the log.
# What it does on its own:
# - Loads pmic_glink_altmode, which hands the Type-C audio mode to the
#   WCD939x USBSS and codec. Verified on 2026-10-20 not to disturb the USB
#   gadget.
# - Logs the jack controls, the UDC state, and the codec/typec dmesg lines.
# - 3 s after "Mic Jack" turns on: logs the PipeWire profile and default
#   source/sink, records 6 s from the default source, and logs the RMS.
# - Then plays a quiet 1 kHz tone (2 s at -36 dBFS) to the default sink and
#   logs the codec's HPH, MIC BIAS2 and ADC2 DAPM state while it plays.
# Usage: jack-watch.sh [seconds]   (default 600)
set -u
K=/usr/lib/modules/$(uname -r).held/kernel
[ -d "$K" ] || K=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
L=/var/log/omamobile/jack.log
mkdir -p "${L%/*}"
for m in drivers/gpu/drm/bridge/aux-hpd-bridge.ko drivers/soc/qcom/pmic_glink_altmode.ko; do
	insmod "$K/$m" 2>/dev/null || true
done
dur=${1:-600}
cat > /tmp/jack-probe.sh <<'PROBE'
#!/bin/bash
# Runs once per headset insertion; output goes to the jack log.
U() { su ml -c "XDG_RUNTIME_DIR=/run/user/1000 $*"; }
D=/sys/kernel/debug/asoc/OnePlus-dodge/audio-codec/dapm
echo "$(date +%T) probe: profile: $(U pactl list cards 2>/dev/null | sed -n 's/^\s*Active Profile: //p')"
echo "$(date +%T) probe: default source $(U pactl get-default-source 2>/dev/null), sink $(U pactl get-default-sink 2>/dev/null)"
U timeout 8 pw-record --rate 48000 --channels 1 --format s16 /tmp/jack-mic.wav >/dev/null 2>&1 &
sleep 7; wait
python3 - /tmp/jack-mic.wav <<'PY'
import sys, wave, struct, math, time
try:
    w = wave.open(sys.argv[1]); d = w.readframes(w.getnframes())
    a = struct.unpack("<%dh" % (len(d) // 2), d)[48000:]
    m = sum(a) / len(a); r = math.sqrt(sum((x - m) ** 2 for x in a) / len(a))
    print(time.strftime("%T"), "probe: headset mic RMS %.1f dBFS, peak %d, %d frames"
          % (20 * math.log10(max(r, .01) / 32768), max(abs(min(a)), max(a)), len(a)))
except Exception as e:
    print(time.strftime("%T"), "probe: mic recording failed:", e)
PY
python3 -c '
import wave, struct, math
w = wave.open("/tmp/jack-tone.wav", "w"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
v = int(32767 * 10 ** (-36 / 20))
w.writeframes(b"".join(struct.pack("<hh", s, s) for s in (int(v * math.sin(2 * math.pi * 1000 * i / 48000)) for i in range(96000))))'
U pw-play /tmp/jack-tone.wav >/dev/null 2>&1 &
sleep 1
for wdg in "HPHL PGA" "HPHR PGA" "HPHL" "HPHR" "MIC BIAS2" "ADC2"; do
	[ -e "$D/$wdg" ] && echo "$(date +%T) probe: dapm $(head -1 "$D/$wdg")"
done
wait
echo "$(date +%T) probe: done"
PROBE
chmod +x /tmp/jack-probe.sh
setsid bash -c '
	L='"$L"'; end=$((SECONDS + '"$dur"')); last=; lastmic=off
	echo "$(date +%T) start, typec: $(ls /sys/class/typec 2>/dev/null | tr "\n" " ")" >> "$L"
	dmesg -w --time-format iso | grep --line-buffered -iE "wcd|mbhc|usbss|typec|altmode|pmic_glink|jack" >> "$L" &
	dm=$!
	while [ $SECONDS -lt $end ]; do
		hp=$(amixer -c0 cget iface=CARD,name="Headphone Jack" 2>/dev/null | sed -n "s/.*: values=//p")
		mic=$(amixer -c0 cget iface=CARD,name="Mic Jack" 2>/dev/null | sed -n "s/.*: values=//p")
		udc=$(cat /sys/class/udc/*/state 2>/dev/null)
		cur="hp=$hp mic=$mic udc=$udc"
		[ "$cur" != "$last" ] && echo "$(date +%T) $cur" >> "$L" && last=$cur
		if [ "$mic" = on ] && [ "$lastmic" != on ]; then
			(sleep 3; /tmp/jack-probe.sh >> "$L" 2>&1) &
		fi
		lastmic=$mic
		sleep 0.3
	done
	kill $dm; wait; echo "$(date +%T) stop" >> "$L"
' </dev/null >/dev/null 2>&1 &
echo "logging to $L for ${dur}s"
