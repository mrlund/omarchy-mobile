#!/bin/sh
# dodge-deadline-check.sh: cancel the deadline reboot only on a clean boot
# (no DSI tx failure / panel init failure / frame-done timeout, dpms On).
bad=$(dmesg | grep -cE "tx failed|Failed to initialize panel|frame done timeout|kickoff timeout")
dp=$(cat /sys/class/drm/card1-DSI-1/dpms 2>/dev/null)
if [ "${FORCE_BAD:-0}" = 0 ] && [ "$bad" = 0 ] && [ "$dp" = On ]; then
	systemctl stop dodge-deadline.timer
	echo "dodge-deadline: clean (dpms $dp), reboot cancelled" > /dev/kmsg
else
	echo "dodge-deadline: NOT clean (fails $bad, dpms $dp, force ${FORCE_BAD:-0}), reboot stays armed" > /dev/kmsg
fi
