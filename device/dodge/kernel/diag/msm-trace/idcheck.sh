#!/bin/bash
# SPDX-License-Identifier: MIT
# idcheck.sh: exits 1 on any hit. Scans the unpushed diff (origin/dodge-plan..HEAD + index) for identifiers. Prints only counts/paths, never values.
cd /home/ml/Repos/omarchy-mobile
D=$( { git diff origin/dodge-plan..HEAD; git diff --cached; } | grep '^+' )
SER=$(for d in /sys/bus/usb/devices/*; do grep -qs "OnePlus" $d/product && cat $d/serial; done | head -1)
bad=0
chk() { n=$(echo "$D" | grep -ciE "$2"); [ "$n" -gt 0 ] && { echo "HIT $1: $n lines"; bad=1; }; }
chk MAC '([0-9a-f]{2}:){5}[0-9a-f]{2}'
chk IMEI15 '(^|[^0-9a-fx])[0-9]{15}([^0-9]|$)'
chk ICCID '89[0-9]{17,18}'
chk phone '\+[0-9]{8,14}'
# private strings (SSID etc.) live outside the repo, one regex per line, never committed
P=~/.config/omarchy-mobile/private-ids
[ -f $P ] && while read -r x; do [ -n "$x" ] && chk private "$x"; done < $P
[ -f $P ] || { echo "no $P: private strings not checked"; bad=1; }
chk psk 'psk[=]|password[=]'
[ -n "$SER" ] && chk serial "$SER"
[ -z "$SER" ] && echo "note: phone serial not read (phone off?)"
echo "$( { git diff --stat origin/dodge-plan..HEAD; git diff --cached --stat; } | tail -2)"
[ $bad = 0 ] && { echo IDCHECK_OK; exit 0; }; echo IDCHECK_FAIL; exit 1
