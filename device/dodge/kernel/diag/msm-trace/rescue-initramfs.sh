for s in /sys/block/sda/sda*; do grep -qx PARTNAME=userdata "$s/uevent" 2>/dev/null && dev=/dev/${s##*/}; done
[ -n "$dev" ] || { echo NODEV; exit 1; }
for i in 1 2 3 4 5 6 7 8 9 10; do [ "$(cat /sys/block/sda/${dev#/dev/}/ro)" = 0 ] && break; sleep 0.3; done
mkdir -p /mnt/fx; mount -t ext4 -o rw "$dev" /mnt/fx || { echo NOMOUNT; exit 1; }
D=/mnt/fx/usr/local/lib/omamobile.6.16.0-gbd9587d65/display
cp $D/msm.ko.pre-trace $D/msm.ko && sync && sha256sum $D/msm.ko && echo FIXED
umount /mnt/fx
