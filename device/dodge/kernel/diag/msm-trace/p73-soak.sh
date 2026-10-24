#!/bin/bash
# p73-soak.sh <tag> <img>: one gated 7.3 one-shot soak, longer than the 240 s rule, under these conditions:
#  - the on-phone deadline is extended (never removed) via /root/dodge-deadline-soak (DL73 s of 7.x uptime,
#    max 880 s ~ 15 min from fastboot boot); dodge-deadline-arm.sh consumes the flag on the next boot either way
#  - first check must show the display healthy (DSI On, 0 tx failed), else immediate reboot
#  - a host monitor checks ssh + display health every 30 s and reboots the phone at the first failure or missed check
#  - host hard watchdog at HARD s (default 900)
# Soak: CYC screen off/on cycles (omarchy-brightness-display as ml, 12 s off -> MDSS runtime suspend/GDSC off),
# one IDLE s idle-off, gateway ping every 30 s (monitor), dmesg errors/WARNs at the end.
# MODE=wake: instead run wake-timing.sh CYC on the phone (per-wake ms to dpms On / first frame, dump on a slow wake).
TAG=$1; IMG=$2; CYC=${CYC:-10}; IDLE=${IDLE:-150}; DL73=${DL73:-840}; HARD=${HARD:-900}
cd /home/ml/Repos/omarchy-mobile; L=/home/ml/android/mainline/logs; P=$L/p73-$TAG
SS="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=10 root@$(tools/phone-ip 2>/dev/null || echo 172.16.42.1)"
S="timeout 25 $SS"
log() { echo "$(date +%T) t=$((SECONDS-T0)) $*" | tee -a $P-soak.txt; }
kill73() { log "REBOOT: $*"; touch $P.failed; $S "dmesg | tail -150" > $P-dmesg-kill.txt 2>&1; timeout 15 $SS 'systemctl reboot'; sleep 40
  r=$($S 'uname -r' 2>/dev/null); [[ $r == 7.* ]] && timeout 15 $SS 'systemctl reboot --force --force'; }
sha256sum "$IMG"; rm -f $P.failed $P-soak.txt; T0=$SECONDS
$S "touch /root/dodge-deadline; echo $DL73 > /root/dodge-deadline-soak; sync" || exit 1
for k in 1 2 3 4 5 6; do tools/dodge-gate && break; [ $k = 6 ] && { $S 'rm -f /root/dodge-deadline-soak'; echo "gate failed"; exit 1; }; sleep 15; done
$S '/usr/local/bin/reboot-to bootloader'
for i in $(seq 60); do fastboot devices | grep -q . && break; sleep 2; done
fastboot devices | grep -q . || { echo "no fastboot"; exit 1; }
T0=$SECONDS; log "fastboot boot"; fastboot boot "$IMG"
( sleep $HARD; r=$($S 'uname -r' 2>/dev/null)
  if [[ $r == 7.* ]]; then echo "$(date +%T) HOST WATCHDOG at $HARD s" >> $P-soak.txt; timeout 15 $SS 'systemctl reboot'; sleep 40
    r=$($S 'uname -r' 2>/dev/null); [[ $r == 7.* ]] && timeout 15 $SS 'systemctl reboot --force --force'; fi ) & WD=$!
up=0; while ((SECONDS-T0<150)); do
  $S 'case "$(uname -r)" in 7.3*) ;; *) exit 1;; esac; pidof Hyprland >/dev/null && ls /run/user/1000/hypr/*/.socket.sock >/dev/null 2>&1' && { up=1; break; }; sleep 3; done
H='tf=$(dmesg | grep -cE "tx failed|Failed to initialize panel|kickoff timeout"); fd=$(dmesg | grep -c "frame done timeout"); dp=$(cat /sys/class/drm/card*-DSI-1/dpms | head -1); off=$([ -e /tmp/soak-off ] && echo 1 || echo 0); gw=$(ip r | awk "/^default/{print \$3; exit}"); pr=$(ping -c3 -W3 $gw 2>/dev/null | grep -o "[0-9]* received" | cut -d" " -f1); pg=$([ "${pr:-0}" -gt 0 ] && echo ok${pr}/3 || echo FAIL0/3); st=$(nmcli -t -f STATE g); echo "k=$(uname -r) tf=$tf fd=$fd dpms=$dp off=$off ping=$pg nm=$st hypr=$(pidof Hyprland)"'
if [ $up = 1 ]; then
  sleep 5; first=$($S "$H"); log "first: $first"
  $S 'dmesg | grep dodge-deadline; systemctl list-timers --all --no-pager "dodge-deadline*"' > $P-timers.txt 2>&1
  if [[ $first != *"tf=0 "* || $first != *"dpms=On"* ]]; then kill73 "first check not healthy"; else
    grep -q "extended to $DL73" $P-timers.txt || log "WARN: soak extension not seen in dmesg (deadline stays at default = shorter)"
    # host monitor: every 30 s
    ( while sleep 30; do [ -e $P.done ] && exit 0; o=$($S "$H" 2>&1); rc=$?; echo "$(date +%T) t=$((SECONDS-T0)) mon rc=$rc $o" >> $P-soak.txt
        if [ $rc != 0 ] || [[ $o != *"k=7.3"* ]]; then echo "$(date +%T) MON missed check" >> $P-soak.txt; kill73 "missed check"; exit 1; fi
        if [[ $o != *"tf=0 "* ]] || { [[ $o == *"off=0"* ]] && [[ $o != *"dpms=On"* ]]; }; then kill73 "display health: $o"; exit 1; fi
      done ) & MON=$!
    if [ "${MODE:-}" = wake ]; then timeout 600 $SS "sh -s $CYC" > $P-cycles.txt 2>&1 < device/dodge/kernel/diag/msm-trace/wake-timing.sh
    else
    timeout $((CYC*20+IDLE+60)) $SS "CYC=$CYC IDLE=$IDLE sh -s" > $P-cycles.txt 2>&1 <<'PH'
B() { runuser -u ml -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | tail -1) omarchy-brightness-display "$1" >/dev/null 2>&1; }
D=$(ls /sys/class/drm/card*-DSI-1/dpms | head -1); R=$(ls /sys/devices/platform/soc@0/*display-subsystem/power/runtime_status | head -1)
G() { grep -E "^mdss_gdsc " /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | head -1 | awk '{print $2}'; }
tf() { dmesg | grep -cE "tx failed|Failed to initialize panel|kickoff timeout"; }; t0=$(tf)
chk() { d=$(( $(tf) - t0 )); case "$2" in off*) ;; *) echo "FAIL gdsc-not-off";; esac; [ "$3" = On ] || echo "FAIL no-wake"; [ $d -eq 0 ] || echo "FAIL txdelta=$d"; echo "$(date +%T) $1 gdsc:$2 rpm-off:$4 wake=$3 txdelta=$d"; }
echo "$(date +%T) on: gdsc=$(G) rpm=$(cat $R)"
i=0; while [ $i -lt $CYC ]; do i=$((i+1)); touch /tmp/soak-off; B off; sleep 12; g=$(G); r=$(cat $R); B on; sleep 4; rm -f /tmp/soak-off; chk cyc$i "$g" "$(cat $D)" "$r"; done
touch /tmp/soak-off; B off; sleep $IDLE; g=$(G); r=$(cat $R); B on; sleep 4; rm -f /tmp/soak-off; chk idle$IDLE "$g" "$(cat $D)" "$r"
PH
    fi
    log "cycles rc=$? $(grep -c FAIL $P-cycles.txt) FAIL"; touch $P.done; sleep 1
    [ -e $P.failed ] || { $S "$H" | sed 's/^/final: /' | tee -a $P-soak.txt
      $S 'dmesg' > $P-dmesg.txt; $S 'journalctl -b --no-pager' > $P-journal.txt
      grep -nE "WARNING|Call trace|BUG|Oops|error|fail" $P-dmesg.txt | grep -vE "dodge-deadline" > $P-dmesg-errs.txt
      log "dmesg error/warn lines: $(wc -l < $P-dmesg-errs.txt) (WARNING/Call trace: $(grep -cE 'WARNING|Call trace' $P-dmesg.txt))"
      kill $MON 2>/dev/null; log "reboot to 6.16"; $S 'systemctl reboot'; }
    wait $MON 2>/dev/null
  fi
else log "desktop never came up; deadline/watchdog will reboot"; fi
for i in $(seq 100); do r=$($S 'uname -r' 2>/dev/null); [[ $r == 6.16* ]] && break; sleep 3; done
kill $WD 2>/dev/null; log "back: $r"; sleep 15
$S 'uname -r; echo txfail=$(dmesg | grep -c "tx failed"); cat /sys/class/drm/card*-DSI-1/status /sys/class/drm/card*-DSI-1/dpms; echo hypr=$(pidof Hyprland); nmcli -t -f STATE g; ls /root/dodge-deadline-soak 2>&1; dmesg | grep "soak flag"; echo cap=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity)' 2>&1 | tee $P-back.txt
