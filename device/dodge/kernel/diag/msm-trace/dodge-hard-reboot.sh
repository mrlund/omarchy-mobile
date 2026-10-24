#!/bin/sh
# SPDX-License-Identifier: MIT
# dodge-hard-reboot.sh <why>: emergency reboot for 7.x trial boots. A trial
# kernel can hang in a graceful shutdown (gpu1a: the GPU driver after an oops),
# where only a hands-on forced restart helps. Sysrq sync, remount read-only,
# then reboot: no unit stops and no driver .shutdown callbacks.
echo "dodge-hard-reboot: ${1:-manual}, sysrq s/u/b" > /dev/kmsg
sync
echo s > /proc/sysrq-trigger; sleep 1
echo u > /proc/sysrq-trigger; sleep 2
echo b > /proc/sysrq-trigger
# not reached; last resort if sysrq is ignored
sleep 10; systemctl reboot --force --force
