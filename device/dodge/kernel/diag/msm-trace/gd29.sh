#!/bin/sh
# gd29.sh (on phone): GDSC-collapse check. 4 screen off/on cycles with 12 s off (MDSS runtime suspend -> GDSC off when keep_gdsc_on is false), then idle-off 165 s + wake. Reports MDSS GDSC state while off and the tx-failed delta.
B() { runuser -u ml -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | tail -1) omarchy-brightness-display "$1" >/dev/null 2>&1; }
D=/sys/class/drm/card1-DSI-1/dpms; tf() { dmesg | grep -cE "tx failed|Failed to initialize panel"; }; t0=$(tf)
G() { grep -E "^mdss_gdsc " /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | head -1 | awk '{print $1"="$2}'; }
echo "on: $(G) rpm=$(cat /sys/devices/platform/soc@0/ae00000.display-subsystem/power/runtime_status 2>/dev/null)"
for i in 1 2 3 4; do B off; sleep 12; a=$(cat $D); g=$(G); r=$(cat /sys/devices/platform/soc@0/ae00000.display-subsystem/power/runtime_status 2>/dev/null); B on; sleep 4; echo "cyc$i off=$a gdsc:$g rpm:$r on=$(cat $D) txdelta=$(( $(tf) - t0 ))"; done
sleep 165; a=$(cat $D); g=$(G); B on; sleep 4
echo "idle165 dpms=$a gdsc:$g wake=$(cat $D) txdelta=$(( $(tf) - t0 ))"
