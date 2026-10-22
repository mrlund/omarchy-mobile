#!/bin/bash
# rbo.sh TAG KO [N]: stage KO as one-boot msm.ko (91-dodge-oneshot.conf), gated warm reboot, trace summary
cd /home/ml/Repos/omarchy-mobile; L=~/android/mainline/logs
timeout 60 tools/phone-ssh 'cat > /root/msm.oneshot.ko && sync && sha256sum /root/msm.oneshot.ko | cut -c1-16' < "$2" || exit 1
bash /tmp/rbt.sh "$1" 0 >/dev/null
grep -E "gate|ABORT|dpms" $L/m-$1.txt
grep -E "dodge-oneshot" $L/m-$1-journal-k.txt | sed 's/.*dodge-oneshot: //' | cut -c1-16
echo "cb9faults=$(grep -c 'cb=9' $L/m-$1-journal-k.txt) txfail=$(grep -c 'tx failed' $L/m-$1-journal-k.txt)"
grep -E "dodge-trace|cb=9|tx failed|Initialized msm" $L/m-$1-journal-k.txt | grep -v "dsi-dma" | head -${3:-30} | sed 's/omamobile kernel: //; s/ | vbif/|vbif/' | cut -c1-300
