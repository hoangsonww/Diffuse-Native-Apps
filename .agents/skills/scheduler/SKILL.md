---
name: scheduler
description: Change automatic capture cadence, the 15-minute floor, or system-event triggers. Use when snapshots fire too often, not at all, or nextCaptureDate is wrong.
---

# Scheduler

`SnapshotScheduler.decide` is a pure function. Platforms supply Timer / BGAppRefresh / WKApplicationRefresh; they must not fork the decision.

- Disabled = cadence `.off` **and** `capturesOnSystemEvents == false`.
- Cadence off with system events still enabled is a valid schedule.
- `minimumInterval` (default 900s) applies to **every** trigger, including wake/unlock.
- First run with no `lastCapture` captures immediately when enabled.
- `skipsWhenUnchanged` is applied later by `SnapshotService.capture(skipIfUnchanged:)`, not by `decide`.

Tests: `Tests/Domain/SchedulerTests.swift` and scheduler invariants.
