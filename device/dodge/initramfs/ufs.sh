# SPDX-License-Identifier: MIT
# Sourced by the dodge init. The userdata decision only. It does not
# change read-only state and it does not mount anything.

# Print "allow <dev>" when exactly one partition is named userdata,
# otherwise "stop <count> <devs...>". root is a /sys/block directory.
ufs_userdata_decision() {
  root=${1:-/sys/block}
  count=0
  devs=""
  for p in "$root"/sd*/sd*; do
    [ -e "$p/uevent" ] || continue
    name=$(sed -n 's/^PARTNAME=//p' "$p/uevent" 2>/dev/null)
    [ "$name" = userdata ] || continue
    count=$((count + 1))
    devs="$devs ${p##*/}"
  done
  devs=${devs# }
  if [ "$count" -eq 1 ]; then
    echo "allow $devs"
  else
    echo "stop $count${devs:+ $devs}"
  fi
}
