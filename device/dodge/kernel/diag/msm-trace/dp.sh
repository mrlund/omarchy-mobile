#!/bin/bash
# dp.sh: on-phone screen off/on x3 (omarchy-brightness-display) + idle-off (150 s) wake; dpms + tx-failed delta
B() { runuser -u ml -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | tail -1) omarchy-brightness-display "$1" >/dev/null 2>&1; }
D=/sys/class/drm/card1-DSI-1/dpms; tf() { dmesg | grep -c "tx failed"; }; t0=$(tf)
for i in 1 2 3; do B off; sleep 4; a=$(cat $D); B on; sleep 3; echo "cyc$i off=$a on=$(cat $D)"; done
sleep 165; a=$(cat $D); B on; sleep 3
echo "idle165 dpms=$a wake=$(cat $D) txfail_delta=$(( $(tf) - t0 )) bl=$(cat /sys/class/backlight/*/brightness | head -1)"
