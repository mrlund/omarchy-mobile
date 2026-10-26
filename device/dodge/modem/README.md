<!-- SPDX-License-Identifier: MIT -->
# dodge modem

Everything here is inert unless `/etc/omamobile/modem-probe.enable` exists.
Default: off (2026-10-21; a SIM is in since 2026-10-26, the modem stays offline).

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
rmtfs, tqftpserv and ModemManager work, the SIM reads (PIN1 disabled), but
the modem stays offline with no RF bands, so there's no registration and no
data. Details: [../dev-docs/2026-10-26-modem-sim-73.md](../dev-docs/2026-10-26-modem-sim-73.md). Details:
[../dev-docs/2026-10-21-modem.md](../dev-docs/2026-10-21-modem.md).
