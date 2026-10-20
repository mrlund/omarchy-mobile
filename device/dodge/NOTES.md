<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge) bring-up notes

Findings from this phone, newest first. The plan is [PLAN.md](PLAN.md).
Attempts live in [dev-docs/](dev-docs/).

## 2026-10-20: the audio framework answers

- **`APM_CMD_GET_SPF_STATE` returns once the audio heap is assigned.** It times out with or without `adsprpcd` until then. Stock's ADSP FastRPC node sets `qcom,vmids` to `0x16 0x25` (LPASS and the ADSP heap). This 6.16 driver sent `pageslen` 0, so the DSP was told the heap was empty.
- **The open daemon stays in its poll loop.** The assign was `phys 0xf1e00000`, `size 0x300000`, two VMIDs. The phone did not reset. `q6prm` probed afterwards and did not time out. There is still no ALSA card, and soundwire stays disabled. Do not play audio.
- **The running DTB has the FastRPC node and `splash fb`.** `/dev/fastrpc-adsp-secure` exists. The VMIDs are not in that DTB yet; the loaded module supplies them with `audio_heap_vmids=1`. The first image of this series omitted the splash framebuffer and Hyprland had no DRM device.
- **A dead-man reboot fired while that timer was still armed.** The desktop came back. Slot A's try count was not read afterwards.

## 2026-10-19: the ADSP reports a battery percent

- **Capacity reads 69, status Discharging, 4.059 V, 34.1 °C.** The supplies are `qcom-battmgr-bat`. The ADSP is `running`. The modem and the CDSP were not started.
- **`qrtr-smd` has to be loaded before PDR looks up `msm/adsp/charger_pd`.** `pd_mapper` also needs a `qcom,sm8750` domain list, the same one as SM8550. Without either, every property returns `EAGAIN`.
- **Load the PAS driver with `only_adsp=1`.** The board enables the modem and CDSP nodes, and probing the modem assigns its RAM to the modem VM.
- **A cold boot brings the percent back.** `omamobile-adsp-battery.service` finished successfully, the ADSP was running, and capacity was 67. The USB supply was an SDP at 500 mA. The battery status stayed Discharging.
- **These figures are suspect.** The pack should have been charging from USB and the percent should have been nearer 85. `voltage_max` read 8.9 V, `charge_full` failed, and `power_now` did not match the current. Review the battmgr property scaling and the unknown notifications before trusting the gauge. Left as-is on 2026-10-20.

## 2026-10-19: the DT fuel gauge does not answer

- **`ti,bq27541` at I2C `0x55` NACKs.** The bus at `98c000` comes up. Address `0x36` ACKs and returns `0xffff`. Stock's percent path is `oplus_adsp_gauge` behind `oplus,virtual_gauge`, not this node.
- **The PMIC temperature alarms probe.** All nine sit in stage 0, which this driver reports as 37.0 °C. They are not loaded at boot.

## 2026-10-19: IO LDO high-power mode does not clear the aux assert

- **L2F and L3F at stock's 30 mA sit in high-power mode.** `fw_caps` stays `0xf`. Aux is still QMI error 90, and the dump asserts in the same aux-MAC wakeup (`line#192`). Mode 0 times out. No `wlan`. ath12k stays bound.
- **The restart before that probe found slot A out of tries.** `fastboot set_active a` (already current) restored seven. Slot B stayed unbootable. The success bit is still clear.

## 2026-10-19: mission mode crashes the same way

- **Mode 0, with ini and config, still times out.** The firmware enters RDDM about 160 ms after the rejected aux download. Host feature `0x58` does not change `fw_caps` (`0xf`). HW_XPA in the board response is 1, matching stock. ath12k stays bound.

## 2026-10-19: the firmware asserts in the aux MAC wakeup

- **The BDF response says `host bdf data 0x1`, HW_XPA set.** That matches stock's `HW_XPA: 1`.
- **The reset is RDDM.** The crash dump asserts in `cmnos_assert_patched.c:604`, recorded as `Asserted in:0x1a9046c:0x1a90c80, line#192`. The strings beside it are `whal_aux_mac_trigger_wakeup` and the aux PLL ready bits.
- **Host feature bit 6 does not change `fw_caps`.** It stays `0xf`. Sending `aux_ucode20.elf` anyway is still QMI error 90. The QDSS config is error 90 too. ath12k stays bound. The dump is in `~/android/reference/dodge-cph2653/stock-session-2026-10-19/devcd1.bin`.

## 2026-10-19: the QDSS config is rejected too

- **`qdss_trace_config_v2.cfg` (6241 bytes) is answered with QMI error 90.** Regdb, `bdwlan.b0e`, and `phy_ucode20.elf` were sent first. The firmware still resets about 195 ms after the board file, the same interval as the probe that did not send this file. Mode 7 times out. ath12k stays bound.

## 2026-10-19: aux is not advertised, and the reset remains

- **Target cap `fw_caps` is `0xf`.** Bit 6, the aux feature, is clear, so aux was not sent. Regdb (24278 bytes), `bdwlan.b0e`, and `phy_ucode20.elf` were sent. The firmware still resets about 160 ms later and mode 7 times out. ath12k stays bound.

## 2026-10-19: peach PHY ucode is accepted, aux is not

- **`phy_ucode20.elf` downloads with no M3 error.** `aux_ucode20.elf` is rejected with QMI error 90, incompatible state. The firmware still resets and mode 7 times out. The board file in that probe was stock `bdwlan.b0e`. ath12k stays bound. The phone clock was set to 2026-10-19 16:54 CEST; NTP is off.

## 2026-10-17: skipping TME-Lite does not stop the reset

- **With `skip_tme=1`, ini and config are accepted and the firmware still resets** about 190 ms after the board file. Mode 0 then times out. The same reset happens when TME-Lite is sent and rejected. ath12k stays bound.
- **The boot try count hit zero** during these restarts. `fastboot set_active a` put seven tries back. Slot B was left unbootable. The success bit is still clear.

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
