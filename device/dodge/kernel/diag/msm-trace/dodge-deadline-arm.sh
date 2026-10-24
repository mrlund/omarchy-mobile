#!/bin/sh
# dodge-deadline-arm.sh (runs on the phone from 93-dodge-deadline.conf, before msm loads).
# Hard deadline for diag boots: if a one-shot module was taken this boot, or
# /root/dodge-deadline exists (diag campaign running), arm a reboot timer
# at 240 s of uptime (CLOCK_MONOTONIC since kernel boot, so a late timer
# start cannot push it out). A check at 80 s uptime cancels it only if the
# boot is clean. Env overrides for testing: DL, CK (s), ON=--on-active, FORCE_BAD=1.
DL=${DL:-240}; CK=${CK:-80}; ON=${ON:---on-boot}
# 7.x is kexec'd from a 6.16 stage 1 (~20 s), so arm 220 s of 7.x uptime to keep
# the 240 s budget from fastboot boot; the 80 s check never cancels on 7.x.
case "$(uname -r)" in 7.*) DL=${DL73:-220} ;; esac
[ -e /run/msm.oneshot.ko ] || [ -e /run/panel.oneshot.ko ] || [ -e /root/msm.oneshot.ko ] || \
  [ -e /root/panel.oneshot.ko ] || [ -e /root/dodge-deadline ] || exit 0
systemctl stop dodge-deadline.timer dodge-deadline-check.timer 2>/dev/null
systemd-run --no-block --unit=dodge-deadline $ON=$DL --timer-property=AccuracySec=1s --timer-property=DefaultDependencies=no \
  /bin/sh -c 'echo "dodge-deadline: deadline reached, rebooting" > /dev/kmsg; sync; systemctl reboot; sleep 45; sync; systemctl reboot --force --force' \
  || { echo "dodge-deadline: ARM FAILED" > /dev/kmsg; exit 0; }
systemd-run --no-block --unit=dodge-deadline-check $ON=$CK --timer-property=AccuracySec=1s --timer-property=DefaultDependencies=no \
  --setenv=FORCE_BAD=${FORCE_BAD:-0} /bin/sh /root/dodge-deadline-check.sh
echo "dodge-deadline: armed $ON=${DL} s, clean check at ${CK} s (uptime $(cut -d. -f1 /proc/uptime) s)" > /dev/kmsg
