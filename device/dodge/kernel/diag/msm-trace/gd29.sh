#!/bin/sh
# gd29.sh [CYC] [IDLE] (on phone): GDSC-collapse check. CYC screen off/on cycles with 12 s off
# (MDSS runtime suspend -> mdss_gdsc off when keep_gdsc_on is false), then IDLE x (165 s idle-off + wake).
# Prints FAIL if dpms does not come back On, the GDSC did not go off, or tx failed appears.
B() { runuser -u ml -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | tail -1) omarchy-brightness-display "$1" >/dev/null 2>&1; }
D=/sys/class/drm/card1-DSI-1/dpms; R=/sys/devices/platform/soc@0/ae00000.display-subsystem/power/runtime_status
tf() { dmesg | grep -cE "tx failed|Failed to initialize panel|kickoff timeout"; }; t0=$(tf)
G() { grep -E "^mdss_gdsc " /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | head -1 | awk '{print $2}'; }
chk() { d=$(( $(tf) - t0 )); case "$2" in off*) ;; *) echo "FAIL gdsc-not-off";; esac; [ "$3" = On ] || echo "FAIL no-wake"; [ $d -eq 0 ] || echo "FAIL txdelta=$d"; echo "$1 gdsc:$2 wake=$3 txdelta=$d"; }
echo "on: gdsc=$(G) rpm=$(cat $R)"
i=0; while [ $i -lt ${1:-4} ]; do i=$((i+1)); B off; sleep 12; g=$(G); B on; sleep 4; chk cyc$i "$g" "$(cat $D)"; done
j=0; while [ $j -lt ${2:-0} ]; do j=$((j+1)); B off; sleep 165; g=$(G); B on; sleep 4; chk idle$j "$g" "$(cat $D)"; done
