#!/bin/bash
# rbp.sh TAG PANEL_KO: stage a one-boot panel module (92-dodge-panel-oneshot.conf), then rbt.sh
cd /home/ml/Repos/omarchy-mobile
timeout 60 tools/phone-ssh 'cat > /root/panel.oneshot.ko && sync && sha256sum /root/panel.oneshot.ko | cut -c1-16' < "$2" || exit 1
bash device/dodge/kernel/diag/msm-trace/rbt.sh "$1"
