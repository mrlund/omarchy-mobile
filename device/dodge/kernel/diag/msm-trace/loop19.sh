#!/bin/bash
# loop19.sh FIRST LAST: r19 one-shot warm boots until a bad (prereset ln c60) or failing boot
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs; KO=~/android/mainline/msm-variants/r19/msm.ko
for n in $(seq $1 $2); do T=R19-$n; bash /tmp/rbo.sh $T $KO 0 > $L/rbo-$T.txt 2>&1; J=$L/m-$T-journal-k.txt
 pre=$(grep -o "mdss-prereset 0|.*intf1 tg 0 ar [0-9a-f]* ln [0-9a-f]*" $J | grep -o "ln [0-9a-f]*$")
 md=$(grep -o "mem-dma #[0-9]* .*-> -*[0-9]*" $J | sed 's/type.*->/->/' | tr '\n' ' ')
 tpt=$(grep -c "dodge-tpg.*TIMEOUT" $J); tf=$(grep -cE "Failed to initialize panel|tx failed" $J); pp=$(grep -ciE "pp done|frame done|vblank.*time|kickoff timed|underrun" $J)
 s=$(grep -E "dpms=" $L/rbo-$T.txt | grep -o "up.*dpms=[A-Za-z]*" | head -1)
 echo "$T $(date +%T) $s pre:$pre md:[$md] tpgTO=$tpt txfail=$tf pp=$pp"
 if [ "$pre" = "ln c60" ] || [ $tpt -gt 0 ] || [ $tf -gt 0 ] || [ $pp -gt 0 ] || ! echo "$s" | grep -q "dpms=On"; then echo STOP; exit 1; fi
done
