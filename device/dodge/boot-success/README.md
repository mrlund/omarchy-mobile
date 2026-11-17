<!-- SPDX-License-Identifier: MIT -->
# dodge boot-success marker (local to this phone)

Qualcomm ABL keeps each slot's state in byte 6 (attribute bits 48-55) of
the slot's `boot_<slot>` GPT entry: priority 48-49, active 50, retry count
51-53, successful 54, unbootable 55. A slot that is not marked successful
loses one try per boot; at zero ABL marks it unbootable and falls back to
the other slot. Android's `boot_control` HAL sets bit 54; Linux has
nothing that does.

`dodge-boot-success` sets bit 54 on `boot_<running slot>` only, in the
primary and backup GPT of the one LUN that holds it, and rewrites the two
CRCs that cover it. Before writing it checks that only those bytes differ;
afterwards it reads both copies back with `O_DIRECT`. It lifts the
storage guard's read-only flag on that one whole disk for the two writes
and restores it in a `finally` block. `--status` and `--dry-run` write
nothing.

The timer runs it 90 s after boot, and only when sshd, the ADSP battery
service and audio are active, so a broken boot burns a try as ABL intends.

**Not part of `omamobile-device-dodge`, and not a procedure for other
phones.** The main repository's rule (AGENTS.md §1) is that a GPT
slot-flag write is a named, by-hand exception that never runs from a
service or at boot; this marker is the OnePlus 13 owner's local choice,
installed by hand:

```sh
install -Dm755 dodge-boot-success /usr/local/lib/omamobile/dodge-boot-success
install -Dm644 dodge-boot-success.service dodge-boot-success.timer -t /etc/systemd/system/
systemctl enable --now dodge-boot-success.timer
```

`fastboot set_active <slot>` resets that slot to 7 tries, not successful;
the first good boot afterwards marks it again.
