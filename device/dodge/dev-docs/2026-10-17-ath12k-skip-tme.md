<!-- SPDX-License-Identifier: MIT -->
# 2026-10-17 — TME-Lite skipped

**Goal.** See whether the firmware reset is the rejected
TME-Lite download, or the host stopping after it.
**Phone.** OnePlus 13 CPH2653. Restarts for the new modules.
The try count hit zero and the phone stopped in fastboot.
`fastboot set_active a` restored seven tries. Slot B was
not changed. Desktop came back.
**Kernel.** `6.16.0-gb3ee311dab85`
**Result.** Fail. Skipping TME-Lite does not stop the reset.
No `wlan`.

## What the phone did

`skip_tme=1`. Memory and target cap were as before. The log
says `qmi tme-lite skipped`, then the stock board file
(125420 bytes). About 190 ms later: `ignore reset dev flags`.
WLAN mode then timed out.

With the cold-boot shortcut also skipped, ini and config
produced no error, and the mode request was mode 0. It still
timed out at 10 s (`failed to send wlan fw mode:-110`).
Hyprland stayed active. oops count 0. ath12k is bound. Do
not load it again on this boot.

## Learning

Stock CNSS ignores a failed TME-Lite response and continues.
Doing that here, and also not sending TME-Lite at all, both
end in the same reset. The reset is not that one message.
Advertising a `ddr_range` still resets the firmware earlier,
before the memory acknowledgement, so that field stays unset.
