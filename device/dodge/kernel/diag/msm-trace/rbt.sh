#!/bin/bash
# rbt.sh TAG: battery gate (full-battery rule), warm reboot, wait for SSH,
# let msm settle, save logs/m-TAG.txt + m-TAG-journal-k.txt, one-line summary.
# Hard deadline (host side): every SSH call runs under timeout, the SSH wait
# is capped, and a bad boot (tx failed / panel init failed / kickoff timeout /
# 5+ frame-done timeouts / dpms not On) gets HOOK (optional phone script, 20 s timeout) and then an
# immediate gated reboot back to the fallback. The phone-side
# dodge-deadline timer (93-dodge-deadline.conf) reboots at 240 s uptime
# regardless, so a hung host or SSH cannot leave a bad boot running.
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs; T=$1; O=$L/m-$T.txt
gate() {
	g=$(timeout 30 tools/dodge-battcheck 2>&1); echo "gate: $(echo $g | tr '\n' ' ')" >> $O
	echo "$g" | grep -q BATT_OK && return 0
	c=$(echo "$g" | grep -o 'cap [0-9]*' | grep -o '[0-9]*')
	[ "${c:-0}" -ge 95 ] && { echo "gate: full-battery rule, passing" >> $O; return 0; }
	return 1
}
: > $O
gate || { echo "ABORT battery" >> $O; cat $O; exit 2; }
t0=$(date +%s)
timeout 15 tools/phone-ssh 'systemctl reboot' </dev/null >/dev/null 2>&1
sleep 20
for i in $(seq 1 24); do timeout 8 tools/phone-ssh 'true' </dev/null >/dev/null 2>&1 && break; sleep 5; done
sleep 30
J=$L/m-$T-journal-k.txt
timeout 40 tools/phone-ssh 'journalctl -k -b --no-pager' </dev/null > $J 2>&1
s=$(timeout 20 tools/phone-ssh 'echo "up $(cut -d. -f1 /proc/uptime)s dpms=$(cat /sys/class/drm/card*-DSI-1/dpms 2>/dev/null)"' </dev/null 2>&1)
echo "$T $(date +%T) $s tx=$(grep -c 'tx failed' $J) cb9=$(grep -c 'cb=9' $J) oneshot=$(grep -o 'dodge-oneshot.*' $J | cut -c15-30 | tr '\n' ' ') after $(( $(date +%s) - t0 ))s" >> $O
grep -o "dodge-rail.*\|panel power off.*\|Failed to initialize panel.*\|dodge-deadline.*" $J >> $O
# 1-2 frame-done timeouts on the first commit are a known transient on good boots
# (R20-4/6/16, R20b-6: no tx failure, display recovers); a real bad boot has 100+.
fd=$(grep -c "frame done timeout" $J)
if grep -qE "tx failed|Failed to initialize panel|kickoff timeout" $J || [ "$fd" -ge 5 ] || ! echo "$s" | grep -q "dpms=On"; then
	echo "BAD boot: ending it now" >> $O
	[ -n "$HOOK" ] && timeout 20 tools/phone-ssh "sh $HOOK" </dev/null > $L/m-$T-hook.txt 2>&1
	if gate; then timeout 15 tools/phone-ssh 'systemctl reboot' </dev/null >/dev/null 2>&1; echo "bad boot ended by host reboot at $(date +%T) ($(( $(date +%s) - t0 ))s)" >> $O
	else echo "gate failed: leaving it to the phone deadline timer (240 s uptime)" >> $O; fi
	sleep 20
	for i in $(seq 1 24); do timeout 8 tools/phone-ssh 'true' </dev/null >/dev/null 2>&1 && break; sleep 5; done
	echo "back: $(timeout 20 tools/phone-ssh 'echo up $(cut -d. -f1 /proc/uptime)s dpms=$(cat /sys/class/drm/card*-DSI-1/dpms)' </dev/null 2>&1)" >> $O
fi
cat $O
