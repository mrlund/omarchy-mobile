#!/bin/sh
# dodge-deadline-check.sh: cancel the deadline reboot only on a clean boot
# (no DSI tx failure / panel init failure / frame-done timeout, dpms On).
# Never on a one-shot 7.x trial boot (or with /root/dodge-deadline-hard): those
# boots test more than the display, so a clean display must not cancel the reboot.
# (wifibt1 2026-10-24: clean display cancelled it at 80 s, then a hung host
# check held the phone on 7.3 for ~8 min.)
# Trial = a 7.x kernel WITHOUT "dodge.flashed" on its cmdline. Only the flashed
# default 7.3 image (2026-10-24, packed with that word in STAGE2_CMDLINE) has it,
# so every older or one-shot trial image stays in trial mode (fail-safe). The
# flashed default behaves like 6.16: cancelled once the display is clean.
case "$(uname -r)" in
7.*) grep -qw dodge.flashed /proc/cmdline || { echo "dodge-deadline: $(uname -r) trial boot (no dodge.flashed), reboot stays armed" > /dev/kmsg; exit 0; } ;;
esac
[ -e /root/dodge-deadline-hard ] && { echo "dodge-deadline: hard mode, reboot stays armed" > /dev/kmsg; exit 0; }
bad=$(dmesg | grep -cE "tx failed|Failed to initialize panel|frame done timeout|kickoff timeout")
dp=$(cat /sys/class/drm/card*-DSI-1/dpms 2>/dev/null | head -n1)
if [ "${FORCE_BAD:-0}" = 0 ] && [ "$bad" = 0 ] && [ "$dp" = On ]; then
	systemctl stop dodge-deadline.timer
	echo "dodge-deadline: clean (dpms $dp), reboot cancelled" > /dev/kmsg
else
	echo "dodge-deadline: NOT clean (fails $bad, dpms $dp, force ${FORCE_BAD:-0}), reboot stays armed" > /dev/kmsg
fi
