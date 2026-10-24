#!/bin/sh
# wake-timing.sh [CYC] (on phone, root): CYC screen off/on cycles with omarchy-brightness-display as ml.
# Off wait: 2 s, every 3rd cycle 10-20 s. Per wake: ms to DSI dpms On and ms to the first new frame
# (encoder-0 "vsync" counter in msm debugfs; also the "msm" DPU irq count). A wake slower than 2 s
# (or no frame within 10 s) dumps at once: dmesg tail, DSI/MDSS state from sysfs + msm debugfs, GDSC,
# MDSS runtime PM, and whether MDSS went through a runtime resume (= msm_mdss_enable ran, which is
# where the SM8750 QTB read sits on 7.3/0030; there is no log for the read itself). All read-only;
# no register reads (never mmss_noc). /tmp/soak-off is set while the screen is meant to be off.
CYC=${1:-30}
B() { runuser -u ml -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | tail -1) omarchy-brightness-display "$1" >/dev/null 2>&1; }
D=$(ls /sys/class/drm/card*-DSI-1/dpms | head -1); R=$(ls /sys/devices/platform/soc@0/*display-subsystem/power/runtime_status | head -1)
RA=${R%runtime_status}runtime_active_time; E=$(ls -d /sys/kernel/debug/dri/*/encoder-0 | head -1); DR=${E%/encoder-0}
G() { grep -E "^mdss_gdsc " /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | head -1 | awk '{print $2}'; }
V() { grep -o "vsync: *[0-9]*" $E/status | grep -o "[0-9]*$"; }
Q() { grep -E " msm$" /proc/interrupts | awk '{s=0; for(i=2;i<=NF-4;i++) s+=$i; print s}'; }
ms() { echo $(( $(date +%s%N) / 1000000 )); }
tf() { dmesg | grep -cE "tx failed|Failed to initialize panel|kickoff timeout"; }; t0=$(tf)
dump() { echo "---- SLOW $1 at $(date +%T)"; echo "dpms=$(cat $D) status=$(cat ${D%dpms}status) rpm=$(cat $R) gdsc=$(G) vsync=$(V) irq=$(Q)"
  echo "hypr=$(pidof Hyprland)"; cat $E/status; cat $DR/crtc-0/status 2>/dev/null | head -8; head -40 $DR/state 2>/dev/null
  dmesg | grep -c "cannot map the display QTB" | sed 's/^/qtb-map-warn=/'; dmesg | tail -25; echo "---- end"; }
echo "$(date +%T) start: k=$(uname -r) dpms=$(cat $D) gdsc=$(G) rpm=$(cat $R) vsync=$(V) irq=$(Q) qtb-map-warn=$(dmesg | grep -c 'cannot map the display QTB')"
i=0; while [ $i -lt $CYC ]; do i=$((i+1)); w=2; [ $((i%3)) = 0 ] && w=$((10 + (i*7)%11))
  touch /tmp/soak-off; B off; sleep $w
  g=$(G); r=$(cat $R); ra=$(cat $RA); v0=$(V); q0=$(Q); s=$(ms); tD=-1; tF=-1
  B on & bp=$!
  while :; do n=$(( $(ms) - s )); [ $tD -lt 0 ] && [ "$(cat $D)" = On ] && tD=$n; [ $tF -lt 0 ] && [ "$(V)" != "$v0" ] && tF=$n
    [ $tD -ge 0 ] && [ $tF -ge 0 ] && break; [ $n -gt 10000 ] && break; sleep 0.05; done
  wait $bp; rb=$(( $(ms) - s )); ra2=$(cat $RA); res=$([ "$r" = suspended ] && [ "$(cat $R)" = active ] && echo yes || echo no)
  d=$(( $(tf) - t0 )); f=""; { [ $tD -lt 0 ] || [ $tD -gt 2000 ] || [ $tF -lt 0 ] || [ $tF -gt 2000 ]; } && f=" SLOW"
  [ $d -ne 0 ] && f="$f FAIL-txdelta=$d"
  echo "$(date +%T) cyc$i off=${w}s gdsc-off:$g rpm-off:$r resumed:$res dpmsOn_ms=$tD frame_ms=$tF brightness_cmd_ms=$rb vsync+$(( $(V) - v0 )) irq+$(( $(Q) - q0 ))$f"
  [ -n "$f" ] && { dump cyc$i; sleep 3; echo "cyc$i after+3s: dpms=$(cat $D) vsync=$(V)"; }
  rm -f /tmp/soak-off; sleep 2; done
echo "$(date +%T) end: dpms=$(cat $D) txdelta=$(( $(tf) - t0 )) hypr=$(pidof Hyprland)"
