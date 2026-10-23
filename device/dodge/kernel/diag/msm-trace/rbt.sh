#!/bin/bash
# rbt.sh TAG: battery gate (full-battery rule), warm reboot, wait for SSH,
# let msm settle, save logs/m-TAG.txt + m-TAG-journal-k.txt, one-line summary.
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs; T=$1; O=$L/m-$T.txt
g=$(tools/dodge-battcheck 2>&1); echo "gate: $(echo $g | tr '\n' ' ')" > $O
if ! echo "$g" | grep -q BATT_OK; then
	c=$(echo "$g" | grep -o 'cap [0-9]*' | grep -o '[0-9]*')
	if [ "${c:-0}" -ge 95 ]; then echo "gate: full-battery rule, passing" >> $O; else echo "ABORT battery" >> $O; cat $O; exit 2; fi
fi
t0=$(date +%s)
timeout 15 tools/phone-ssh 'systemctl reboot' </dev/null >/dev/null 2>&1
sleep 20
for i in $(seq 1 40); do timeout 8 tools/phone-ssh 'true' </dev/null >/dev/null 2>&1 && break; sleep 5; done
sleep 30
timeout 40 tools/phone-ssh 'journalctl -k -b --no-pager' </dev/null > $L/m-$T-journal-k.txt 2>&1
s=$(timeout 20 tools/phone-ssh 'echo "up $(cut -d. -f1 /proc/uptime)s dpms=$(cat /sys/class/drm/card*-DSI-1/dpms 2>/dev/null)"' </dev/null 2>&1)
J=$L/m-$T-journal-k.txt
echo "$T $(date +%T) $s tx=$(grep -c 'tx failed' $J) cb9=$(grep -c 'cb=9' $J) oneshot=$(grep -o 'dodge-oneshot.*' $J | cut -c15-30 | tr '\n' ' ') after $(( $(date +%s) - t0 ))s" >> $O
grep -o "dodge-rail.*\|panel power off.*\|Failed to initialize panel.*" $J >> $O
cat $O
