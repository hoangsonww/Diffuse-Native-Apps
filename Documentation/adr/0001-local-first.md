# ADR 0001: Local-first

## Status

Accepted.

## Date

2026-08.

## Context

Diffuse observes a personal device. The data includes names, paths, network identifiers, and tool versions. Putting that in a cloud account would make the product a telemetry system that happens to have a UI.

## Decision

Snapshots are captured, stored, diffed, and rendered on the device. There is no Diffuse backend. GitHub hosts source code and CI artifacts only.

## Alternatives considered

- **Account + sync backend.** Would answer “see my Mac from my phone.” Rejected: identity, retention across devices, and a new privacy surface. See [0008](0008-no-cloud-sync.md).
- **iCloud-only sync with no account UI.** Still a distributed store of identifying data under Apple’s container, with conflict rules we do not want to own.

## Consequences

- No accounts, no sync, no “log in to see your Mac from your phone.”
- Each device has its own history. That is the product, not a limitation to paper over later.
- Export is a user action with a redaction policy.
- CI can never require a cloud key to run tests.

## Related

[0007](0007-privacy-classification.md), [0008](0008-no-cloud-sync.md), [Privacy.md](../Privacy.md).
