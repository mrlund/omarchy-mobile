<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge) bring-up notes

Findings from this phone, newest first. The plan is [PLAN.md](PLAN.md).
Attempts live in [dev-docs/](dev-docs/).

## 2026-10-17: stock's DMA window also resets peach early

- **Host cap `ddr_range` start 0 size `0x68000000`, with the segments inside it, resets the firmware** before the memory acknowledgement. Same shape as the 36-bit aperture. The module on disk does not send the field. ath12k stays bound.

## 2026-10-17: stock PDC messages still get TME error 83

- **The AOSS accepted stock's four `wlan_pdc` strings for S5F** (mode, voltage enable, 876 mV up and down) before WLAN enable. There is no `qcom,vreg_ol_cpr` in the stock node. TME-Lite is still `err 83`. No `wlan`. ath12k stays bound.

## 2026-10-17: low DMA addresses still get TME error 83

- **A 28-bit DMA mask put the three firmware segments at `0x0e800000`, `0x0e400000`, and `0x0e3ff000`.** That is inside stock's low window. The firmware reached TME-Lite and answered `err 83` again, then reset. No `wlan`. ath12k stays bound.

## 2026-10-17: a 36-bit DMA window resets peach before TME

- **The firmware asks for three memory segments:** type 1 (7.4 MB), type 4 (4.1 MB), and type 11 (4 KB). Each received a DMA address. Type 11 was already allocated by the driver.
- **Advertising the stage-1 aperture (`0` size `0x1000000000`) makes the firmware reset** before it acknowledges that memory. No TME request on that boot. The module that does not send the window is on disk and is not loaded. ath12k stays bound.

## 2026-10-17: stock rails do not clear TME error 83

- **S5F and S4D at 876 mV, S7I at 1312 mV, and `wcn_sw` / `wcn_sw_ctrl` still get TME-Lite `err 83`.** The firmware resets and mode 7 times out. No `wlan`. ath12k stays bound.
- **Slot A has a seven-boot budget.** Linux never sets `boot_a`'s success bit, so a later restart drops into fastboot with the slot unbootable. `fastboot set_active a` restores the tries without touching slot B. The storage guard refuses the GPT write that would mark the boot successful. Do not restart until that bit is set.
- **Do not `insmod` ath12k twice on one boot.**

## 2026-10-17: the mode timeout is after a rejected TME-Lite download

- **The same PCI id is ported on the OnePlus 13s.**
  `renhiyama/pagani-linux` commit `c49d202` sends
  `tmel_peach_20.elf` over QMI before board data, skips a
  separate M3, and runs cold-boot calibration (WLAN mode 7)
  before mission mode. It names that as the fix for set-mode
  `-110`.
- **This phone's firmware rejects the TME-Lite request**
  (`result 1, err 83`) and then resets (`ignore reset dev
  flags`). Mode 0 and mode 7 both time out. The stock board ELF
  (`board.bin`, 125420 bytes) was sent and the reset still
  happened. No `wlan`.
- **Do not `insmod` ath12k twice on one boot.** The second load
  oopses in `mhi_queue_skb`. The module is bound. The desktop
  is up.

## 2026-10-17: peach Wi-Fi firmware reaches AMSS

- **`amss20.bin` is two ELF files.** The first 512 KiB is an ARM
  SBL. The WLAN firmware ELF starts at offset 512 KiB. BHIe has to
  send that second file on its own.
- **`BHI_EXECENV` is already SBL when MHI prints the wait.** The
  event-ring packet does not arrive. Reading the register and
  continuing is what gets the chip to AMSS. QMI then reports
  `WLAN.GNG.1.0-03342`. No `wlan` interface yet. The mode request
  timed out after a warning for memory type 11.
- **Do not reload ath12k on this boot.** A second `insmod` oopsed
  in `mhi_queue_skb` and the SMMU faulted (SID `0x1401`). The
  module is bound and the desktop is up. Leave it. If the session
  dies, `sync` then `echo b > /proc/sysrq-trigger`.

## 2026-10-17: the Omarchy root fills userdata

- **`resize2fs` online took `/dev/sda15` from 10.5 GiB to 453 GiB**
  (120554767 blocks of 4 KiB, the whole partition). The image had
  `resize_inode` and 1024 reserved GDT blocks. No `ufshcd` error.
  The 2026-10-16 grow was the Arch root this image replaced.

## 2026-10-16: SSH, and the timezone screen

- **The timezone screen is `systemd-firstboot`.** Its description is
  `Initial Setup`. `ConditionFirstBoot=yes` while `/etc/machine-id` is
  the word `uninitialized`, and the unit is `Before=sysinit`, so it
  holds the boot on the console (locale, keymap, timezone, root
  password) and `sshd` never starts. This phone has no keyboard and
  the touchscreen driver is not loaded. Seed machine-id, or mask the
  unit. Do not wait for someone to tap it.
- **OpenSSH 10.6 refuses a locked root when `UsePAM` is off.** The
  packaged config has `UsePAM yes` and `PermitRootLogin
  prohibit-password`. An early config with `UsePAM no` logged
  `User root not allowed because account is locked` and never tried
  `authorized_keys`. Leave the root password locked.
- **`openssh` 10.6p1-2 does not create the `sshd` user.** Without it,
  `sshd-session` exits (`unknown [priv]`) and the client sees a
  publickey denial or a connection reset. The device package ships
  `usr/lib/sysusers.d/sshd.conf`.
- **The module tree stays held** (`6.16.0-gb3ee311dab85.held`).
  Loading it, `msm` included, is what blacked the panel. `plymouth-start`
  stays masked.
