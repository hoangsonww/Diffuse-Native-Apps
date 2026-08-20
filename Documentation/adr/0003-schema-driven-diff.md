# ADR 0003: Schema-driven diff

## Status

Accepted.

## Date

2026-08.

## Context

Snapshots outlive app versions. A newer Diffuse must diff a snapshot taken by an older one, and an older Diffuse should still *display* a section it cannot capture.

Hard-coding “OS versions compare as semver” in the engine couples the engine to today’s collectors.

## Decision

Each section serializes its `SectionSchema`. The diff engine matches entities by identity and compares properties using the descriptors’ comparison rules and severities.

## Alternatives considered

- **Engine knowledge of each capability.** Rejected: every new collector becomes a diff-engine change.
- **Schema registry in the app, not in the snapshot.** Rejected: an old snapshot opened in a new app would use new rules and silently rewrite history.
- **Opaque JSON blobs + textual diff.** Rejected: no identity matching, no severity, no privacy.

## Consequences

- Schema changes are compatibility events. Prefer additive descriptors.
- Unknown capabilities still diff and render.
- The engine stays small. New comparison kinds are new `ComparisonRule` cases, not collector-specific branches.
- Golden fixtures are viable because change ids are content-derived and diffs are deterministic.

## Related

[0002](0002-capability-driven.md), [DiffEngine.md](../DiffEngine.md), [SnapshotSchema.md](../SnapshotSchema.md).
