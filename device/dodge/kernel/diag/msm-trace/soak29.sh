#!/bin/bash
# soak29.sh N: gated warm reboots on persistent r29g (keep_gdsc_on=false); per boot gd29 (4 off/on, one 165 s idle cycle on the first IDLEN boots, after the deadline clean check).
# Any failure: roll back to msm.ko.qtbfix-gdscon and gated reboot, then stop.
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs
G() { for k in 1 2 3 4 5 6; do tools/dodge-battcheck >/dev/null && return 0; sleep 20; done; return 1; }
rollback() { echo "ROLLBACK $(date +%T): $1"; timeout 30 tools/phone-ssh 'cd /usr/local/lib/omamobile/display && cp msm.ko.qtbfix-gdscon msm.ko && sync && sha256sum msm.ko | cut -c1-12'
  until G; do echo "gate fail, retry"; done; timeout 15 tools/phone-ssh 'systemctl reboot'; echo "rollback reboot $(date +%T)"; exit 1; }
for n in $(seq 1 $1); do
 [ -e /tmp/stop29 ] && { echo "stop29 at $(date +%T)"; exit 0; }
 [ $(date +%s) -gt ${STOPAT:-9999999999} ] && { echo "STOPAT reached $(date +%T)"; exit 0; }
 T=S29-$n; G || { echo "$T gate failed 6x, stop"; exit 2; }
 timeout 420 bash device/dodge/kernel/diag/msm-trace/rbt.sh $T > $L/rbt-$T.txt 2>&1; J=$L/m-$T-journal-k.txt
 grep -q ABORT $L/m-$T.txt && { echo "$T ABORT (gate)"; exit 1; }
 tf=$(grep -cE "Failed to initialize panel|tx failed" $J); s=$(grep -o "up [0-9]*s dpms=[A-Za-z]*" $L/m-$T.txt | head -1)
 ln=$(grep -o "premsm intf1 .*line_count [0-9a-f]*" $J | grep -o "[0-9a-f]*$")
 echo "$T $(date +%T) $s premsm-ln:$ln txfail=$tf $(grep -E 'BAD|ended|back:' $L/m-$T.txt | tr '\n' ' ')"
 if [ "$tf" -gt 0 ] || grep -q BAD $L/m-$T.txt; then rollback "$T bad boot"; fi
 # wait for the phone-side clean check (80 s) first: a screen-off at 80 s reads as NOT clean and leaves the 240 s reboot armed
 for k in $(seq 1 12); do timeout 10 tools/phone-ssh 'journalctl -b --no-pager | grep -q "dodge-deadline: clean"' && break; sleep 10; done
 timeout 10 tools/phone-ssh 'journalctl -b --no-pager | grep -q "dodge-deadline: clean"' || rollback "$T deadline clean check did not pass"
 I=0; [ $n -le ${IDLEN:-2} ] && I=1
 timeout 520 tools/phone-ssh "sh /root/gd29.sh 4 $I" > $L/gd-$T.txt 2>&1; sed 's/^/   /' $L/gd-$T.txt
 if grep -q FAIL $L/gd-$T.txt || ! grep -q cyc4 $L/gd-$T.txt; then rollback "$T off/on cycle failure"; fi
done
