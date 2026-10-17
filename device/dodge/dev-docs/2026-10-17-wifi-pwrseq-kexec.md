<!-- SPDX-License-Identifier: MIT -->
# 2026-10-17 — kexec of the 7850 power node, link not back

**Goal.** Power the radio with the existing WCN7850 sequencer and see
an endpoint, without writing `boot_a`.
**Phone.** OnePlus 13 CPH2653.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** `kexec -c -l` accepted the image. SSH has not come back.
The USB gadget enumerates and the host network interface has no carrier.

## What we did

Stock's peach node uses the same six rails the board file already
names, and `pwrseq_wcn7850_vregs` already includes `vddio1p2`. Those
regulators are present on the running root. The live FDT's
`wcn7880-pmu` compatible was changed to `qcom,wcn7850-pmu` and its
status to `okay`. The source DTS matches that. Nothing was flashed.

A reboot cleared the PCIe PHY module. `kexec -c -l` of the same Image
and initrd, with that DTB and the running cmdline, printed `LOAD_OK`,
then `kexec -e` dropped the link at 15:08.

## What happened

By 15:10 the gadget `1d6b:0104` was back (NCM and ACM). The host
interface `enp7s0f3u1` stays `NO-CARRIER`, so there is no route to
`172.16.42.1` and `lspci` has not been read. The pass line for this
step is still an endpoint on the bus.

## Learning

The 7850 sequencer already has this node's rail list, so no new
sequence was written. Whether the endpoint appeared is unread until
the USB network has a carrier again.
