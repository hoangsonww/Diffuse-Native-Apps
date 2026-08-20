---
name: debug-collector
description: Diagnose a collector that hangs, throws, records a placeholder, or produces noisy diffs. Use when a section is failed, timed out, permission-required, or a live capture is unstable.
---

# Debug a collector

Coordinator rules (already tested in CoreTests):

- One failing collector never fails the snapshot; it becomes a section with `CollectionStatus.failed` and a reason.
- Hanging collectors are abandoned at the per-collector deadline (`FakeCollector.Behaviour.hang` in tests).
- Disabled / unavailable / permission-required become placeholders, not crashes.
- Background captures skip expensive collectors (`CollectionCost`).

Live capture tests in Integration only use cheap, stable capabilities. Do not assert quiet diffs on battery or free space.

Reproduce with a `FakeCollector` first. If it only fails on hardware, record the `CollectionOutcome` and the travelling schema — do not add a platform `#if` in the diff engine.
