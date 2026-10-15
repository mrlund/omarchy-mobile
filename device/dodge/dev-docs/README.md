<!-- SPDX-License-Identifier: MIT -->
# dodge lab notes

Running log for the OnePlus 13 port. The plan is
[../PLAN.md](../PLAN.md). This directory is for attempts: what we tried,
what the phone did, and what we learned, including the tries that failed.

A fact that later boots will trip over gets promoted into
`device/dodge/NOTES.md` (newest first, same as cheetah) or into a
subsystem plan. A safety rule does not live only here.

## How to add an entry

One file per attempt or session:

```
YYYY-MM-DD-short-slug.md
```

Use the day the attempt happened. If a day has two, add a suffix
(`-2`, or a more specific slug). Start the file with:

```markdown
<!-- SPDX-License-Identifier: MIT -->
# YYYY-MM-DD — title

**Goal.** One or two sentences.
**Phone.** Model and build id if we already know them. No serial, IMEI or MAC.
**Kernel.** `uname -r`, or "no kernel of ours" if we had not booted one.
**Result.** Pass, fail, or stopped. One sentence.
```

Then three sections:

- **What we did.** The commands and the order. Quote the lines that
  matter. Leave out `getprop` dumps, partition images and anything that
  identifies the phone.
- **What happened.** Include the failure mode. "It hung" is less useful
  than the last kmsg line that made it to the laptop.
- **Learning.** What the next attempt will do differently. Name the plan
  section this confirms or contradicts.

Add a row to the index below in the same change. Keep the newest row at
the top.

Do not put captures here. They go in `~/android/reference/dodge-cph2653/`
and stay out of git.

## Index

| Date | Entry | Result |
| --- | --- | --- |
| 2026-10-15 | [second-review](2026-10-15-second-review.md) | Outside review: self-contained v2 image, full OTA, an armed watchdog, Magisk fallback, stale notes marked. |
| 2026-10-15 | [rooted-capture](2026-10-15-rooted-capture.md) | No downstream-kernel track. Phase 1 roots OxygenOS with Magisk for a live capture. |
| 2026-10-15 | [plan-review](2026-10-15-plan-review.md) | Way back after a kernel hang, OTA as stock-image source, slot rules, host setup. Plan revised. |
| 2026-10-15 | [cable-not-stick](2026-10-15-cable-not-stick.md) | Loop is one USB cable: `fastboot boot`, then SSH. No stick. |
| 2026-10-15 | [oss-landscape](2026-10-15-oss-landscape.md) | Survey of other dodge firmware. Stick path superseded the same day. |
| 2026-10-15 | [assessment-review](2026-10-15-assessment-review.md) | First plan. Goal superseded the same day. |
