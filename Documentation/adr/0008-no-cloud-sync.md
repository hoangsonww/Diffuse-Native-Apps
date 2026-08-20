# ADR 0008: No cloud sync

## Status

Accepted.

## Date

2026-08.

## Context

Users will ask to see their Mac snapshots on their iPhone. iCloud, a custom backend, or AirDrop-as-a-service would answer that. They would also make Diffuse a distributed system with identity, conflict resolution, and a new privacy surface.

## Decision

There is no sync. Each device is a closed history. If you want a snapshot off the device, export it yourself (Files, AirDrop, `diffuse-dev`, paste a redacted Markdown report).

This is the continuation of [0001](0001-local-first.md), recorded separately so it cannot be quietly reversed as a “small feature.”

## Alternatives considered

- **iCloud Drive folder of JSON snapshots.** Looks simple until two devices capture at once, ids collide, and redaction policy differs.
- **Custom backend with E2E encryption.** Still an account, still a sync protocol, still a company that could be compelled. Out of scope for this product.

## Consequences

- Cross-device compare is out of scope.
- AirDrop / Files / the CLI are the interchange story, all user-initiated.
- Import assigns a new `SnapshotID` and origin `.imported`.
- A future sync product would be a different app, or a new ADR that supersedes this one with a threat model attached.

## Related

[0001](0001-local-first.md), [0007](0007-privacy-classification.md).
