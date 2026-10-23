#!/bin/bash
# loop20x.sh N "VAR1:PFX1 VAR2:PFX2 ...": interleaved A/B one-shot warm boots, N rounds, does not stop on a bad boot.
# After a bad boot (fallback comes up next), waits until the phone's own deadline check has declared the running boot clean
# (or the phone timer has rebooted it and the next boot is clean) before the next one-shot is staged.
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs
waitclean() { for k in $(seq 1 30); do
  r=$(timeout 15 tools/phone-ssh 'cut -d. -f1 /proc/uptime; journalctl -b --no-pager | grep -oE "dodge-deadline: (clean|NOT clean)" | tail -1' 2>/dev/null | tr '\n' ' ')
  echo "  wait: $r"; case "$r" in *"dodge-deadline: clean"*) return 0;; esac; sleep 20; done; return 1; }
for n in $(seq 1 $1); do for vp in $2; do V=${vp%%:*}; P=${vp##*:}; T=$P-$n; KO=~/android/mainline/msm-variants/$V/msm.ko
 timeout 480 bash /tmp/rbo.sh $T $KO 0 > $L/rbo-$T.txt 2>&1; J=$L/m-$T-journal-k.txt
 if grep -q ABORT $L/rbo-$T.txt; then echo "$T ABORT (gate)"; cat $L/rbo-$T.txt | head -3; exit 1; fi
 pre=$(grep -o "mdss-prereset 0.*ln [0-9a-f]*" $J | grep -o "ln [0-9a-f]*$")
 tf=$(grep -cE "Failed to initialize panel|tx failed" $J)
 q=$(grep -o "dodge-qtb: .*" $J | tail -1 | cut -c1-80)
 s=$(grep -o "up [0-9]*s dpms=[A-Za-z]*" $L/rbo-$T.txt | head -1)
 echo "$T $(date +%T) $s pre:$pre txfail=$tf last:[$q] $(grep -E 'BAD|ended|back:' $L/m-$T.txt | tr '\n' ' ')"
 if [ "$tf" -gt 0 ] || grep -q BAD $L/m-$T.txt; then waitclean || { echo "STOP: fallback not clean"; exit 1; }; fi
done; done
