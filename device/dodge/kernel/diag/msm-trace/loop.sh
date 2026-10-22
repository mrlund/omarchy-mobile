#!/bin/bash
# loop.sh KO FIRST LAST: one-shot warm boots G<FIRST..LAST>, dpms/idle per good boot, stop on first bad
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs
for n in $(seq $2 $3); do T=G$n; bash /tmp/rbo.sh $T "$1" 0 > $L/rbo-$T.txt 2>&1
 s=$(grep -E "gate|dpms=|cb9faults" $L/rbo-$T.txt | tr '\n' ' ' | cut -c1-150); pre=$(grep -o "mdss-prereset 0|.*intf1 tg 0 ar [0-9a-f]* ln [0-9a-f]*" $L/m-$T-journal-k.txt | grep -o "ln [0-9a-f]*$")
 f=$(grep -o "iova=0x[0-9a-f]*, fsynr=0x[0-9a-f]*, cbfrsynra=0x[0-9a-f]*, cb=9" $L/m-$T-journal-k.txt | head -1); id=$(grep -o "dodge-idmap.*" $L/m-$T-journal-k.txt)
 echo "$T $(date +%T) $s pre:$pre $id $f"
 echo "$s" | grep -q "cb9faults=0 txfail=0" || { echo BAD; exit 1; }
 timeout 260 tools/phone-ssh 'bash -s' < /tmp/dp.sh | tr '\n' ' '; echo
done
