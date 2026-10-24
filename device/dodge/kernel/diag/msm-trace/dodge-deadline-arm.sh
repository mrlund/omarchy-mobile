#!/bin/sh
# dodge-deadline-arm.sh (runs on the phone from 93-dodge-deadline.conf, before msm loads).
# Hard deadline for diag boots: if a one-shot module was taken this boot, or
# /root/dodge-deadline exists (diag campaign running), arm a reboot timer
# at 240 s of uptime (CLOCK_MONOTONIC since kernel boot, so a late timer
# start cannot push it out). A check at 80 s uptime cancels it only if the
# boot is clean. Env overrides for testing: DL, CK (s), ON=--on-active, FORCE_BAD=1.
DL=${DL:-240}; CK=${CK:-80}; ON=${ON:---on-boot}
# 7.x is kexec'd from a 6.16 stage 1 (~20 s), so arm 220 s of 7.x uptime to keep
# the 240 s budget from fastboot boot. On a 7.x trial boot (no "dodge.flashed" on
# the cmdline) the 80 s check never cancels; on the flashed default 7.3 it
# cancels on a clean display, like 6.16. The soak flag only applies to trials.
TRIAL=0
case "$(uname -r)" in 7.*) DL=${DL73:-220}; grep -qw dodge.flashed /proc/cmdline || TRIAL=1 ;; esac
# Soak flag (set only by p73-soak.sh, for one boot): /root/dodge-deadline-soak
# holds the 7.x deadline in s, capped at 880 s (about 15 min from fastboot boot).
# It is read and removed here on every boot, so it never outlives the next boot.
# The deadline is extended, never removed.
if [ -e /root/dodge-deadline-soak ]; then
  sk=$(tr -cd 0-9 < /root/dodge-deadline-soak); rm -f /root/dodge-deadline-soak; sync
  case "$TRIAL" in 1) [ -n "$sk" ] && [ "$sk" -gt "$DL" ] && { [ "$sk" -gt 880 ] && sk=880; DL=$sk;
    echo "dodge-deadline: soak flag, 7.x deadline extended to ${DL} s (flag consumed)" > /dev/kmsg; } ;;
  *) echo "dodge-deadline: stale soak flag removed on $(uname -r) (not a trial boot)" > /dev/kmsg ;; esac
fi
[ -e /run/msm.oneshot.ko ] || [ -e /run/panel.oneshot.ko ] || [ -e /root/msm.oneshot.ko ] || \
  [ -e /root/panel.oneshot.ko ] || [ -e /root/dodge-deadline ] || exit 0
systemctl stop dodge-deadline.timer dodge-deadline-check.timer 2>/dev/null
# Trial boots (7.x without dodge.flashed) reboot through sysrq (dodge-hard-reboot.sh),
# so a trial kernel stuck in shutdown cannot need hands; others shut down gracefully.
if [ "$TRIAL" = 1 ] && [ -r /root/dodge-hard-reboot.sh ]; then
  DLCMD='echo "dodge-deadline: deadline reached, hard reboot (trial)" > /dev/kmsg; exec /bin/sh /root/dodge-hard-reboot.sh deadline'
else
  DLCMD='echo "dodge-deadline: deadline reached, rebooting" > /dev/kmsg; sync; systemctl reboot; sleep 45; sync; systemctl reboot --force --force'
fi
systemd-run --no-block --unit=dodge-deadline $ON=$DL --timer-property=AccuracySec=1s --timer-property=DefaultDependencies=no \
  /bin/sh -c "$DLCMD" \
  || { echo "dodge-deadline: ARM FAILED" > /dev/kmsg; exit 0; }
systemd-run --no-block --unit=dodge-deadline-check $ON=$CK --timer-property=AccuracySec=1s --timer-property=DefaultDependencies=no \
  --setenv=FORCE_BAD=${FORCE_BAD:-0} /bin/sh /root/dodge-deadline-check.sh
echo "dodge-deadline: armed $ON=${DL} s, clean check at ${CK} s, trial=$TRIAL (uptime $(cut -d. -f1 /proc/uptime) s)" > /dev/kmsg
