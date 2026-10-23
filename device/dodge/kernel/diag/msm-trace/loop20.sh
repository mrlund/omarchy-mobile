#!/bin/bash
# loop20.sh FIRST LAST (env V=variant dir, P=tag prefix): one-shot warm boots until a bad boot (rbt.sh ends it itself);
# prints the QTB OT/fence line at the last dump point of each boot.
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs; V=${V:-r20}; KO=~/android/mainline/msm-variants/$V/msm.ko; P=${P:-R20}
for n in $(seq $1 $2); do T=$P-$n; timeout 480 bash /tmp/rbo.sh $T $KO 0 > $L/rbo-$T.txt 2>&1; J=$L/m-$T-journal-k.txt
 pre=$(grep -o "mdss-prereset 0.*ln [0-9a-f]*" $J | grep -o "ln [0-9a-f]*$")
 tf=$(grep -cE "Failed to initialize panel|tx failed" $J)
 q=$(grep -o "dodge-qtb: .*" $J | tail -1 | cut -c1-200)
 s=$(grep -o "up [0-9]*s dpms=[A-Za-z]*" $L/rbo-$T.txt | head -1)
 echo "$T $(date +%T) $s pre:$pre txfail=$tf last:[$q] $(grep -E 'BAD|ended|back:' $L/m-$T.txt | tr '\n' ' ')"
 if [ $tf -gt 0 ] || ! echo "$s" | grep -q "dpms=On"; then echo STOP; exit 1; fi
done
