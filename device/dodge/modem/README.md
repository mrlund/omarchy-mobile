<!-- SPDX-License-Identifier: MIT -->
# dodge modem

Everything here is inert unless `/etc/omamobile/modem-probe.enable` exists.
Default: **on** since 2026-10-27 with the flashed `7.3.0-rc6-dodge-gpu2` (IPA),
which gives working mobile data. It was off from 2026-10-21 (from 2026-10-26 it
registered on LTE, then crashed without IPA). On a kernel without an enabled IPA
DT node (gpu1, s1, 6.16) `omamobile-modem-efs` exits without touching the
copies, so rmtfs and the MPSS are never started and a rollback stays safe with
the flag on (the MPSS is only probed).

With the flag, at boot:

1. `adsp-battery.sh` loads `qcom_q6v5_pas` with `only_adsp=0`. The MPSS and CDSP
   get probed; the CDSP fails its load (no firmware), which is harmless.
2. `omamobile-rmtfs.service` loads `qcom_rmtfs_mem`, waits for
   `/dev/qcom_rmtfs_mem1`, and runs **only** `rmtfs -r -o
   /var/lib/omamobile/modem-efs -v`: read-only copies of the EFS partitions,
   with modem writes kept in RAM. Never `-P`.
3. `omamobile-tqftpserv.service` serves MCFG from `/lib/firmware`.
4. `omamobile-modem.service` starts the MPSS by name.
5. `omamobile-mm-netport.service` creates the tun `rmnet_mm0`, which
   `78-omamobile-mm-fake-net.rules` tags as the qcom-soc net port. ModemManager
   refuses a QMI modem without one, and SM8750 IPA isn't in 6.16 yet. Data
   can't work through it. gpu2 skips this unit (its skip-units file): IPA
   provides the real `rmnet_ipa0`.
6. `omamobile-cellular.nmconnection` (installed into NetworkManager, mode 600)
   is a gsm profile: APN `internet`, autoconnect with priority -10 and
   unlimited retries, route metric 700 for IPv4 and IPv6, no secrets. NM, not
   networkd, owns the bearer and applies its IP config. Wi-Fi (metric 600)
   stays the default route while it is up; with Wi-Fi off the default moves to
   the cellular `qmapmux0.0`. NM may still pick cellular as the IPv6 default
   when the Wi-Fi network has no IPv6. Tested end to end on gpu2 2026-10-27
   (NM autoconnects about 14 s after ModemManager sees the modem).
7. ModemManager (drop-in `ModemManager-omamobile.conf`) starts after the units
   above. Without the flag its condition skips it.

Since 2026-10-27, with the IPA trial kernel, two more units bracket the stack:
`omamobile-modem-efs.service` runs before rmtfs. It needs an enabled IPA DT
node (otherwise nothing starts and the copies are left alone). It snapshots the
copies to `/var/lib/omamobile/efs-snapshots/auto-*` (newest 12 kept), then
restores the named good set `/var/lib/omamobile/efs-good/<name>`. The name is
in `/etc/omamobile/modem-efs-good`, and good sets are never rotated.
`omamobile-modem-online.service` runs before ModemManager. It provisions SIM
slot 1 if needed, goes online, waits for registration and snapshots `reg`. A
set the modem has written to for a few minutes crashes the next boot (rtsar),
so the good set is restored on every boot. See
[../dev-docs/2026-10-27-option-b-efs-timeline-and-units.md](../dev-docs/2026-10-27-option-b-efs-timeline-and-units.md).

Install: copy this directory to the phone and run `./install` as root. It
needs `/usr/local/bin/rmtfs` and `tqftpserv` (linux-msm git), `qcom_rmtfs_mem.ko`
(built at `KERNELRELEASE=6.16.0-gb3ee311dab85`) in
`/usr/local/lib/omamobile/modem/`, the firmware in
`/lib/firmware/qcom/sm8750/OnePlus/` and the EFS copies. None of those are in git.
The EFS dir also needs the OnePlus NV backup, or the modem has no RF bands.
Make read-only copies of the current slot's partitions, `dd if=` only:
`oplusstanvbk_a` -> `oem_stanvbk`, `oplusdycnvbk` -> `oem_dycnvbk` (mode 600;
the dynamic one is per-unit calibration, keep it off the repo).

On 7.x the helper loads the in-tree `rmtfs_mem.ko` from
`/usr/lib/modules/<release>.held` when the 6.16 `qcom_rmtfs_mem.ko` is not in
the overlay, and the MPSS needs the `mpss` node enabled in the DT (gpu1 has it;
the PR branch keeps it disabled).

Turn on: `touch /etc/omamobile/modem-probe.enable`, then reboot. Turn off:
remove the file and reboot. **Never stop the modem remoteproc** (`echo stop`,
`systemctl stop omamobile-modem` with an old unit, or a shutdown that runs
one): on 7.3 it hard-resets the phone at once, with no kernel log and the
filesystems still mounted. The unit has no ExecStop and `omamobile-modem stop`
only logs. A phone running an older unit needs a runtime drop-in with an empty
`ExecStop=` before any reboot.

Status 2026-10-26 (7.3 gpu1, SIM inserted): the MPSS boots and QMI,
rmtfs, tqftpserv and ModemManager work. The helper sets remoteproc `recovery`
to `disabled` before starting the MPSS, so a modem crash doesn't make the
kernel stop it (which would reset the phone). With the NV backup copies and
the opt-in `omamobile-rmtfs-rw-copies.conf` (rmtfs writes to the copies,
never the partitions) the MCFG commits, and after a manual slot-1
provisioning session plus `online` the modem registers on LTE. About 30 s
later it crashes because there is no IPA data path for the LTE bearer. No
data. Default: flag off.
Details:
[../dev-docs/2026-10-26-modem-efs-rw-73.md](../dev-docs/2026-10-26-modem-efs-rw-73.md),
[../dev-docs/2026-10-26-modem-nvbk-73.md](../dev-docs/2026-10-26-modem-nvbk-73.md),
[../dev-docs/2026-10-26-modem-sim-73.md](../dev-docs/2026-10-26-modem-sim-73.md),
[../dev-docs/2026-10-21-modem.md](../dev-docs/2026-10-21-modem.md).
