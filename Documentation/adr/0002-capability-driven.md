# ADR 0002: Capability-driven architecture

## Status

Accepted.

## Date

2026-08.

## Context

A snapshot product grows by observing more of the system. If each observation is a special case, the diff engine, store, search, export, and four apps all change together. That does not scale, and it makes “just add Wi-Fi” a cross-cutting rewrite.

## Decision

Observations are **capabilities**. A capability is a stable id, a travelling schema, and a collector. Registries list capabilities per platform. Core and UI are generic over `SnapshotSection` / `Change`.

Adding a capability is: typed model + collector + register + tests. Not a new screen. Not a new diff algorithm.

## Alternatives considered

- **Hard-coded sections in the UI and engine** (`if capability == .wifi`). Fast for the first three observations; fatal at the tenth.
- **Plugin bundles loaded at runtime.** Rejected for a local-first app with no third-party packages and a need for deterministic fixtures.
- **One mega-snapshot struct** with optional fields for every observation. Rejected: every collector would compile into every platform.

## Consequences

- `switch` on capability IDs is forbidden in Core, Diff, Storage, and UI renderers.
- The schema must be expressive enough for comparison, severity, privacy, and display.
- Platform differences live in collectors and registries, not in `if macOS { … }` inside the Mac overview.
- Extensibility is tested: `Tests/Integration` adds a capability nothing else has heard of.

## Related

[0003](0003-schema-driven-diff.md), [CapabilityGuide.md](../CapabilityGuide.md), [Architecture.md](../Architecture.md).
