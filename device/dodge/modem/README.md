<!-- SPDX-License-Identifier: MIT -->
# dodge modem

Everything here is inert unless `/etc/omamobile/modem-probe.enable` exists.
Default: off (2026-10-21; since 2026-10-26 it registers on LTE, then crashes without IPA).

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
   can't work through it.
6. ModemManager (drop-in `ModemManager-omamobile.conf`) starts after the units
   above. Without the flag its condition skips it.

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
