#!/bin/bash
# sample.sh KO PREFIX N: N one-shot warm boots, no stop on bad, one-line summary each (bad boots get rebooted by the next iteration)
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs
for n in $(seq 1 $3); do T=$2$n; bash /tmp/rbo.sh $T "$1" 0 > $L/rbo-$T.txt 2>&1
 s=$(grep -E "gate|cb9faults" $L/rbo-$T.txt | tr '\n' ' ' | cut -c1-120); pre=$(grep -m1 -o 'mdss-prereset 0.*intf1 tg 0 ar [0-9a-f]* ln [0-9a-f]*' $L/m-$T-journal-k.txt | grep -o 'ln [0-9a-f]*$')
 echo "$T $(date +%T) $s pre:$pre os:$(grep -c dodge-oneshot $L/m-$T-journal-k.txt) $(head -c 300 $L/rbo-$T.txt | head -2 | tr "\n" " ")"; grep -o "dodge-(stop|wait|preset|c).*" -E $L/m-$T-journal-k.txt | cut -c1-200; grep -o "mdss-prereset dsierr.*" $L/m-$T-journal-k.txt
done
