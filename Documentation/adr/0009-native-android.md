# ADR 0009: Native Android implementation

## Status

Accepted.

## Date

2026-08.

## Context

Diffuse’s local-first capture and comparison model also fits Android. Reusing the Swift apps through a wrapper, embedding a cross-platform UI runtime, or moving the Apple targets to a shared framework would compromise native behavior and create risk for four working Swift apps.

At the same time, two engines must not silently diverge on snapshot JSON, comparison behavior, privacy redaction, or retention guarantees.

## Decision

Add Android as a fully native Kotlin and Jetpack Compose application under `Android/`. It has its own platform-free Kotlin domain engine, Android collectors, storage/service layer, adaptive Compose UI, and WorkManager scheduling.

The Android project does not depend on or alter Apple app targets. Cross-language compatibility is a data contract: schema-v1 JSON snapshots, stable identifiers, privacy semantics, and the existing golden snapshots and expected diffs under `Fixtures/`.

Android remains local-first: no account, cloud, telemetry, analytics, or `INTERNET` permission. Snapshot and preference data are excluded from Android backup and device transfer. Signing material stays outside the repository.

## Alternatives considered

- **Kotlin Multiplatform shared engine.** Rejected because it would replace proven Swift packages and broaden the change into all Apple apps.
- **React Native or Flutter.** Rejected because the product calls for a native Kotlin app and platform-specific UI behavior matters.
- **JNI/Swift runtime bridge.** Rejected as a fragile packaging boundary that would make Android builds depend on Apple-oriented implementation details.
- **Independent format with import conversion.** Rejected because golden fixture compatibility is simpler and prevents ecosystem drift.

## Consequences

- Product semantics are implemented twice and therefore require cross-language fixture tests.
- Android can evolve its UI, collectors, and scheduling without touching Swift targets.
- A new shared comparison rule or schema version must be implemented and tested in both engines before shared fixtures use it.
- Apple’s no-third-party-Swift-package rule remains unchanged; Android uses the AndroidX and Kotlin libraries expected by a native Compose app.
- Repository and release documentation must distinguish five native apps from four shared-engine Apple apps.

## Related

[0001](0001-local-first.md), [0002](0002-capability-driven.md), [0003](0003-schema-driven-diff.md), [0005](0005-generated-unsigned.md), [0006](0006-four-native-apps.md), [0007](0007-privacy-classification.md), [0008](0008-no-cloud-sync.md), [Root architecture](../../ARCHITECTURE.md).
