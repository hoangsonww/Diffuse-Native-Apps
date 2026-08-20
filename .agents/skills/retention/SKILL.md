---
name: retention
description: Change how old snapshots are pruned (age, count, size, pinned/labelled protection). Use when the library grows without bound or a named snapshot disappeared.
---

# Retention

`RetentionPlanner.plan` is pure over `[SnapshotSummary]`. Preview in UI must use the same function the store executes.

- Newest snapshot is **never** deleted. Without it there is nothing to compare against.
- Default policy: 90 days, 1 GiB, protects pinned and labelled snapshots.
- Empty labels are not protection. `protectsLabelled` / `protectsPinned` can be turned off.
- Protected snapshots do not consume the count/size quota.
- Age is applied before count/size so the reason stays `tooOld` when both apply.
- `SnapshotService.capture` runs retention **after** save so the new snapshot always survives a tight limit.

Tests: `Tests/Domain/RetentionPlannerTests.swift` and retention invariants.
