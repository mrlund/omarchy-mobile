<!-- SPDX-License-Identifier: MIT -->
# msm first-commit trace and splash stop (Round 13, 2026-10-22)

DIAG only, 6.16 (`omamobile-dodge`). Not for upstream. Built as `msm.ko`, tested one boot at a time.

- `0001-DIAG-drm-msm-...patch`: the local kernel commit. It adds `dodge_trace.c`/`.h` plus hooks in msm_mdss, msm_kms, dpu_kms, dpu_hw_ctl, dpu_hw_intf and dsi_host, then `dodge_stop_splash()` before `msm_mdss_reset`, then a 1:1 read-only map of the splash reserved region in the display domain.
- `91-dodge-oneshot.conf`: drop-in for `omamobile-display-msm.service`. Put a module at `/root/msm.oneshot.ko` and it is used for **one** boot only, then moved to /run. A module that hangs the phone is gone after the reboot.
- `rbo.sh TAG KO [N]`: stages the one-shot, does a gated warm reboot (`/tmp/rbt.sh`) and prints the summary. `loop.sh KO FIRST LAST`: consecutive one-shot boots plus `dp.sh`, stopping at the first bad boot.
- `dp.sh` (runs on the phone): 3 screen off/on cycles with `omarchy-brightness-display`, then a 165 s wait for the idle-off, then a wake. Prints dpms and the tx-failed delta. Note that `hyprctl dispatch dpms` is Lua syntax on this Hyprland.
- `rescue-initramfs.sh`: boot-loop rescue. Pipe it into the stage-2 initramfs dropbear during its short window (about 4-6 s after the USB gadget appears). It mounts userdata and copies `msm.ko.pre-trace` over `msm.ko`.

Rule learned the hard way: any MDP/DSI MMIO read must check the GDSC **and** the branch CBCR CLK_OFF bits (dispcc 0xaf00000: ahb 0x80b0, mdp 0x8010, byte0 0x8034, esc0 0x8044). Right after the BCR, ahb/mdp read 0x88000001 (off), and a read then hangs the bus (boot loop).
- `rbt.sh TAG`: battery gate (full-battery rule), warm reboot, saves logs/m-TAG.txt and the kernel journal. It replaces the lost /tmp/rbt.sh.
- `../panel-rail/`: the Round 15 panel rail-cycle diag patch, the one-boot panel drop-in `92-dodge-panel-oneshot.conf`, and `rbp.sh TAG KO` to stage it.
- `0007-tpg-fifo-resend-and-vbif-halt-dump.patch`: Round 17. On the first -110, sw reset and resend through the TPG DMA FIFO (no memory fetch). Later commands of 64 bytes or less use the FIFO after a success. VBIF XIN/AXI halt dump at the BCR, first command and -110. Applies on top of the revert of 0006.
- `0008-r18-first-dma-dumps-iova-fifo-depth.patch`: Round 18. VBIF+STATUS0 at first-trig/first-done, dma_base iova vs iommu_iova_to_phys, and a no-trigger TPG FIFO depth probe. On top of 0007.
- `0009-r18b-dma-count-shift.patch`: Round 18b. Resends the first panel command twice (DMA count-shift test). On top of 0008.
