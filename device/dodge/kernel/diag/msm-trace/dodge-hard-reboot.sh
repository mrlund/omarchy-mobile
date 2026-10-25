#!/bin/sh
# SPDX-License-Identifier: MIT
# dodge-hard-reboot.sh <why>: emergency reboot for 7.x trial boots. A trial
# kernel can hang in a graceful shutdown (gpu1a: the GPU driver after an oops),
# where only a hands-on forced restart helps. Sync, sysrq sync, then reboot:
# no unit stops and no driver .shutdown callbacks.
# No sysrq u (emergency remount read-only): the rootfs has orphan_file, and a
# forced ro remount with deleted-but-open files running logs "Orphan file not
# empty on read-only fs" (ext4_mark_recovery_complete, EFSCORRUPTED) and sets
# the fs error flag (pr1b and pr1c exits, 2026-10-25). Without u the next
# mount replays the journal and clears the orphans, as for a power cut.
# Sysrq s runs as async work: wait for its "complete" line before b.
echo "dodge-hard-reboot: ${1:-manual}, sysrq s/b" > /dev/kmsg
sync
ns=$(dmesg | grep -c 'Emergency Sync complete')
echo s > /proc/sysrq-trigger
i=0
while [ "$i" -lt 40 ]; do
  [ "$(dmesg | grep -c 'Emergency Sync complete')" -gt "$ns" ] && break
  sleep 0.25; i=$((i + 1))
done
sync
sleep 0.5
echo b > /proc/sysrq-trigger
# not reached; last resort if sysrq is ignored
sleep 10; systemctl reboot --force --force
