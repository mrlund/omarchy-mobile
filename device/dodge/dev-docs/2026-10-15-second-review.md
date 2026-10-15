<!-- SPDX-License-Identifier: MIT -->
# 2026-10-15 — second review of the plan

**Goal.** Weigh an outside review (another AI assistant, six points) of
[../PLAN.md](../PLAN.md) after the rooted-capture change, and apply what
holds up.
**Phone.** Not attached. CPH2653, as in the plan.
**Kernel.** None of ours.
**Result.** Five points applied, one mostly covered already. The
strategy is unchanged.

## What we did

Checked each point against the plan and against what we know of
Qualcomm ABL, Magisk and fastboot. Where the review was right but
narrow, or slightly wrong on a detail, the plan says the corrected
version.

## What happened

1. **Copy stock's image geometry.** Applied, corrected: a v4 `boot.img`
   carries no load addresses, so base and offsets come from the OTA's
   `vendor_boot` header. ABL may ignore them on arm64 [I], but the first
   image uses them so that a wrong offset is not one of the suspects.
   Plan §5.3, phase 0b.
2. **A self-contained header v2 image after Magisk.** Applied, broader:
   a v4 `fastboot boot` mixes in the flashed `init_boot` and
   `vendor_boot` before Magisk too, so the loop image is always
   self-contained. Added the decision point the list lacked: if ABL
   refuses v2 under `fastboot boot`, the next step is a `vendor_boot`
   flash, with its own entry. Plan §5.1, §5.3.
3. **The Magisk bootloop fallback.** The rollback, the slot naming and
   the inactive-slot hazard were already in the plan. Added: if the
   patched image loops and stock boots, phase 2 starts without the live
   capture, and a `vbmeta` change is not the recovery. "Unsuffixed
   flashes often write both slots" is overstated (fastboot writes the
   current slot unless told `--slot=all`); the plan now forbids
   `--slot=all` by name. Plan §6 phase 1.
4. **The full OTA for the exact build.** Applied. The SOTA package holds
   no boot images, an incremental OTA gives no restorable `init_boot`,
   and the region package must match. Plan §3.2. (The review's mention
   of "EX01" tags matched nothing we know of, and was left out.)
5. **Watchdog and timeouts.** Applied, extended. A watchdog node is
   necessary but not enough: the hardware watchdog bites only once
   armed, so the init feeds `/dev/watchdog`, and a hang before init
   still needs `panic=10` or a human. The SM8750 hypervisor may own the
   watchdog [I]; phase 0c checks. `tools/dodge-try` gets a second,
   long deadline for an OxygenOS boot, timed in phase 1. ramoops only in
   stock's region or a hole two sources agree on. Plan §5.1, phases 0c,
   0d and 1.
6. **Stale notes and AGENTS.md.** Applied. The assessment review's and
   the OSS survey's closing instructions are marked superseded, left as
   written. A dodge [AGENTS.md](../AGENTS.md) points at the plan's §3,
   and one line in the root `AGENTS.md` §1 points at it. That line is a
   change to a file shared with upstream and may conflict on a merge.

## Learning

Two of the six points (2 and 5) were "this works only if something else
is also true": the image is only a test of our kernel if nothing flashed
is mixed in, and the watchdog only helps if it is armed. When a plan row
says a mechanism makes the loop safe, write down what has to hold for
the mechanism to work, and which phase checks it.
