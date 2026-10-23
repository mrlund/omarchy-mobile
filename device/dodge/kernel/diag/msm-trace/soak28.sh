#!/bin/bash
# soak28.sh N: gated warm reboots on the persistent msm.ko (no one-shot), count premsm INTF1 line count + bad.
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs
waitclean() { for k in $(seq 1 30); do
  r=$(timeout 15 tools/phone-ssh 'cut -d. -f1 /proc/uptime; journalctl -b --no-pager | grep -oE "dodge-deadline: (clean|NOT clean)" | tail -1' 2>/dev/null | tr '\n' ' ')
  echo "  wait: $r"; case "$r" in *"dodge-deadline: clean"*) return 0;; esac; sleep 20; done; return 1; }
for n in $(seq 1 $1); do
 [ -e /tmp/stop28 ] && { echo "stop28 at $(date +%T)"; exit 0; }
 [ $(date +%s) -gt ${STOPAT:-9999999999} ] && { echo "STOPAT reached $(date +%T)"; exit 0; }
 T=Q28-$n; timeout 420 bash device/dodge/kernel/diag/msm-trace/rbt.sh $T > $L/rbt-$T.txt 2>&1; J=$L/m-$T-journal-k.txt
 grep -q ABORT $L/m-$T.txt && { echo "$T ABORT (gate)"; exit 1; }
 ln=$(grep -o "premsm intf1 .*line_count [0-9a-f]*" $J | grep -o "[0-9a-f]*$")
 tf=$(grep -cE "Failed to initialize panel|tx failed" $J); os=$(grep -c dodge-oneshot $J)
 s=$(grep -o "up [0-9]*s dpms=[A-Za-z]*" $L/m-$T.txt | head -1)
 echo "$T $(date +%T) $s premsm-ln:$ln txfail=$tf oneshot=$os $(grep -E 'BAD|ended|back:' $L/m-$T.txt | tr '\n' ' ')"
 if [ "$tf" -gt 0 ] || grep -q BAD $L/m-$T.txt; then waitclean || { echo "STOP: next boot not clean"; exit 1; }; fi
done
