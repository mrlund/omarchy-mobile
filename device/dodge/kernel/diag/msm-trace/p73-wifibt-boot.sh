#!/bin/bash
# usage: p73-wifibt-boot.sh <tag> <image>  one-shot 7.3 boot, display/audio/wifi/bt checks, back to 6.16
TAG=$1; IMG=$2; cd /home/ml/Repos/omarchy-mobile
SS="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=10 root@172.16.42.1"
S="timeout 25 $SS"   # every ssh call is bounded; the long check uses timeout 90 $SS
L=/home/ml/android/mainline/logs
HARD=${HARD:-225}    # host watchdog: force the phone off 7.x at fastboot-boot + HARD s
REBOOT_AT=${REBOOT_AT:-190}  # normal path sends systemctl reboot by fastboot-boot + this; 6.16 is back ~40 s later (< 240 s)
left() { echo $((REBOOT_AT-(SECONDS-T0))); }
GATE() { tools/dodge-battcheck || { $S '[ "$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity)" -eq 100 ]' && echo "BATT_OK (100% rule)"; }; }
[ -f "$IMG" ] || { echo "no image $IMG"; exit 1; }
sha256sum "$IMG"
if [ "${FROM_FASTBOOT:-0}" = 1 ]; then
  echo "$(date +%T) continuing from fastboot (gate passed just before)"
else
  $S 'touch /root/dodge-deadline; sync'
  echo "$(date +%T) gate"
  GATE || { echo "$(date +%T) gate failed, not booting"; exit 1; }
  $S '/usr/local/bin/reboot-to bootloader'
fi
for i in $(seq 60); do fastboot devices | grep -q . && break; sleep 2; done
fastboot devices | grep -q . || { echo "$(date +%T) no fastboot"; exit 1; }
echo "$(date +%T) fastboot boot"; T0=$SECONDS
fastboot boot "$IMG"
# Host-side hard watchdog, independent of the check below: at T0+HARD, if the
# phone still runs a 7.x kernel, reboot it (then force) no matter what the
# check is doing. The on-phone dodge-deadline timer is the primary guard.
( sleep $HARD; r=$($S 'uname -r' 2>/dev/null)
  if [[ $r == 7.* ]]; then echo "$(date +%T) HOST WATCHDOG: still on $r at t=$HARD, rebooting" >&2
    timeout 15 $SS 'systemctl reboot' ; sleep 40
    r=$($S 'uname -r' 2>/dev/null); [[ $r == 7.* ]] && { echo "$(date +%T) HOST WATCHDOG: forcing" >&2; timeout 15 $SS 'systemctl reboot --force --force'; }
  fi ) & WD=$!
trap 'kill $WD 2>/dev/null; pkill -P $$ ssh 2>/dev/null' EXIT
up=0
while ((SECONDS-T0<200)); do
  $S 'uname -r' 2>/dev/null | grep -q '^7\.3' && { up=1; echo "$(date +%T) ssh up t=$((SECONDS-T0))"; break; }; sleep 3
done
if [ $up = 1 ]; then
  IRQ='echo "== uptime $(cut -d" " -f1 /proc/uptime) dmesg_last=$(dmesg | tail -1 | cut -c1-14)"; grep -iE "mhi|ath12k|pci|msi|its" /proc/interrupts | tr -s " "; lspci -vvv -s 01:00.0 2>/dev/null | grep -A2 -E "MSI(-X)?:"; grep -E "gpio16 |gpio102 " /sys/kernel/debug/gpio | head -2; grep -E "unit:" /sys/kernel/debug/pwrseq 2>/dev/null; ls /sys/bus/platform/drivers/pci-pwrctrl-pwrseq/ 2>/dev/null | grep -c wifi; ls /sys/bus/pci/devices/0000:01:00.0/msi_irqs 2>/dev/null | tr "\n" " "; echo; for f in msi-map msi-map-mask interrupt-names; do p=$(ls -d /proc/device-tree/soc@0/pci@1c00000/$f 2>/dev/null); [ -n "$p" ] && { echo "$f:"; od -An -tx1 "$p" | head -3; }; done'
  for i in 1 2 3 4 5 6; do
    $S 'echo "uname $(uname -r) uptime $(cut -d" " -f1 /proc/uptime)"; systemctl list-timers --all --no-pager "dodge-deadline*"; dmesg | grep dodge-deadline' > $L/p73-$TAG-timers.txt 2>&1
    grep -q "dodge-deadline.timer" $L/p73-$TAG-timers.txt && break; sleep 3
  done
  cat $L/p73-$TAG-timers.txt
  # MSI sampling while BHI waits: 7.x only, uptime 10..95 s
  : > $L/p73-$TAG-irq.txt
  $S 'case "$(uname -r)" in 7.*) ;; *) echo NOT73; exit;; esac; echo "uname $(uname -r) uptime $(cut -d" " -f1 /proc/uptime)"; for d in 00:00.0 01:00.0; do echo "=== $d"; lspci -vvv -s $d; done' > $L/p73-$TAG-lspci-full.txt 2>&1
  $S 'echo "== pwrctrl/pwrseq at uptime $(cut -d" " -f1 /proc/uptime)"; lsmod | grep -E "pwrseq|pwrctrl"; ls /sys/bus/platform/drivers/pci-pwrctrl-pwrseq/ /sys/bus/platform/drivers/pwrseq-qcom_wcn/ 2>&1; cat /sys/kernel/debug/pwrseq 2>&1; grep -E "gpio16 |gpio102 |gpio104 " /sys/kernel/debug/gpio; dmesg | grep -iE "pwrseq|pwrctrl|wcn7880|wifi@0" | grep -v "Modules linked"' > $L/p73-$TAG-pwrctrl.txt 2>&1
  while ((SECONDS-T0<130)); do
    o=$($S 'u=$(cut -d. -f1 /proc/uptime); case "$(uname -r)" in 7.*) ;; *) echo NOT73; exit;; esac; dmesg | grep -qE "did not load image over BHI|failed to power up" && { echo DONE; exit; }; '"$IRQ" 2>&1)
    case "$o" in *NOT73*|*DONE*) echo "$o" | head -1 >> $L/p73-$TAG-irq.txt; break;; esac
    echo "$o" >> $L/p73-$TAG-irq.txt; sleep 12
  done
  # give ath12k/BT units time
  for i in $(seq 20); do $S 'ip link show wlan0 >/dev/null 2>&1 && systemctl is-active -q omamobile-bt' && break; ((SECONDS-T0>110)) && break; sleep 3; done
  sleep 10
  echo "$(date +%T) checks t=$((SECONDS-T0))"
  $S 'uname -r; echo txfail=$(dmesg | grep -cE "tx failed|Failed to initialize panel"); cat /sys/class/drm/card*-DSI-1/status /sys/class/drm/card*-DSI-1/dpms; ip -4 a show usb0 | grep -o "inet [0-9.]*"; cat /sys/class/input/*/name | tr "\n" ";"; echo; systemctl --failed --no-legend; echo hypr=$(pidof Hyprland); echo cap=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity 2>/dev/null)' > $L/p73-$TAG-health.txt 2>&1
  CT=$(( $(left) - 30 )); ((CT>90)) && CT=90
  if ((CT<15)); then echo "long check skipped (left $(left) s)" > $L/p73-$TAG-check.txt; else
  timeout -k 5 $CT $SS 'set +e
    echo "== audio silence"; r0=$(dmesg | grep -c "aw882308.*running:")
    timeout 8 aplay -q -D hw:0,0 -f S16_LE -r 48000 -c 2 -d 3 /dev/zero; echo aplay_rc=$?
    head -c 576000 /dev/zero > /tmp/silence.raw; chmod 644 /tmp/silence.raw
    U=$(id -u ml); timeout 8 runuser -u ml -- env XDG_RUNTIME_DIR=/run/user/$U pw-play -a --format s16 --rate 48000 --channels 2 /tmp/silence.raw; echo pwplay_rc=$?
    echo aw_running_new=$(( $(dmesg | grep -c "aw882308.*running:") - r0 ))
    echo "== units"; for u in omamobile-wifi-pcie omamobile-wifi-ath12k omamobile-bt NetworkManager bluetooth; do echo "$u $(systemctl is-active $u)"; done
    journalctl -b --no-pager -o cat -u omamobile-wifi-pcie -u omamobile-wifi-ath12k -u omamobile-bt | grep -v "address set\|generated" | tail -20
    echo "== pci"; lspci -n 2>/dev/null | grep -i 17cb
    echo "== ath12k dmesg"; dmesg | grep -iE "ath12k|qrtr|mhi" | sed -E "s/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/gi" | tail -40
    echo "== wlan"; ip -br link show wlan0 | sed -E "s/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/gi"
    echo wlan_ipv4=$(ip -4 a show wlan0 2>/dev/null | grep -c inet)
    iw dev wlan0 scan >/tmp/scan.txt 2>&1; echo scan_rc=$? bss=$(grep -c "^BSS" /tmp/scan.txt)
    echo nm_wlan=$(nmcli -t -f GENERAL.STATE dev show wlan0 2>/dev/null)
    echo "== bt"; timeout 5 btmgmt info 2>&1 | grep -E "^hci|current settings" | sed -E "s/([0-9a-f]{2}:){5}[0-9a-f]{2}/<addr>/gi"
    echo hci0_up=$(cat /sys/class/bluetooth/hci0/../uevent >/dev/null 2>&1 && echo present; timeout 3 hciconfig hci0 2>/dev/null | grep -c "UP RUNNING")
    timeout 5 bluetoothctl power on 2>&1 | tail -1
    n=$(timeout 15 bluetoothctl --timeout 12 scan on 2>/dev/null | grep -c "NEW.*Device"); echo bt_scan_new_devices=$n
    echo "== bt dmesg"; dmesg | grep -iE "bluetooth|hci_uart|qca" | sed -E "s/([0-9a-f]{2}:){5}[0-9a-f]{2}/<addr>/gi" | tail -25
    uptime' > $L/p73-$TAG-check.txt 2>&1
  fi
  echo "$(date +%T) check done rc=$? t=$((SECONDS-T0))"
  $S "$IRQ" >> $L/p73-$TAG-irq.txt 2>&1
  $S 'for d in 0000:00:00.0 0000:01:00.0; do g=$(readlink /sys/bus/pci/devices/$d/iommu_group); echo "$d group=${g##*/} type=$(cat /sys/bus/pci/devices/$d/iommu_group/type 2>/dev/null) devs=$(ls /sys/bus/pci/devices/$d/iommu_group/devices 2>/dev/null | tr "\n" " ")"; cat /sys/bus/pci/devices/$d/iommu_group/reserved_regions 2>/dev/null; done; grep -iE "smmu" /proc/interrupts | tr -s " " | awk "{s=0; for(i=2;i<=9;i++) s+=\$i; if (s) print \$1, s, \$NF}"; dmesg | grep -iE "smmu|iommu" | grep -viE "probing|SMMUv2|stage|coherent|stream|context banks|page sizes|IPA" | tail -15' > $L/p73-$TAG-iommu.txt 2>&1
  $S 'uname -r; dmesg' > $L/p73-$TAG-dmesg.txt 2>&1
  (( $(left) > 8 )) && timeout 15 $SS 'journalctl -b --no-pager' > $L/p73-$TAG-journal.txt 2>&1
  echo "$(date +%T) captured t=$((SECONDS-T0))"; cat $L/p73-$TAG-health.txt
  $S 'systemctl reboot' ; echo "$(date +%T) reboot sent t=$((SECONDS-T0))"
else
  echo "$(date +%T) 7.3 ssh never came up; deadline/panic will reboot"
fi
# back to 6.16
for i in $(seq 100); do r=$($S 'uname -r' 2>/dev/null); [[ $r == 6.16* ]] && break; sleep 3; done
echo "$(date +%T) back: $r t=$((SECONDS-T0))"
sleep 15
$S 'uname -r; cat /sys/class/drm/card*-DSI-1/status /sys/class/drm/card*-DSI-1/dpms; echo hypr=$(pidof Hyprland); echo cap=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity)' 2>&1 | tee $L/p73-$TAG-back.txt
