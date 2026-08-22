# Swift Architecture

Diffuse is a **capability-driven, local-first** snapshot product. This document describes the first-party Swift engine used by Mac, iPhone, iPad, Watch, and `diffuse-dev`. The native Kotlin Android architecture and fixture boundary are documented in the repository-wide [ARCHITECTURE.md](../ARCHITECTURE.md).

The Swift domain engine does not know about Mac, iPhone, iPad, Watch, or Android. Apple apps and Apple collectors do. Android neither links this engine nor changes its target graph; both engines agree through schema-v1 JSON and golden fixtures ([ADR 0009](adr/0009-native-android.md)).

This document is the map. Decisions that led here are in [adr/](adr/). Words used below are in [Glossary.md](Glossary.md). How to add an observation is in [CapabilityGuide.md](CapabilityGuide.md). How tests prove the map still holds is in [Testing.md](Testing.md). Scripts and CI are in [Repository.md](Repository.md).

## The question

> What changed on this device between these two points in time?

Everything else — scheduling, widgets, export, the CLI, retention, search — exists to ask that question more often, more clearly, or more privately.

If a change does not help answer it, it does not belong in Diffuse.

## Non-goals

These are product decisions, not missing features. Several have their own ADR.

- No account, no cloud, no telemetry ([0001](adr/0001-local-first.md), [0008](adr/0008-no-cloud-sync.md))
- No “see my Mac snapshots on my iPhone”
- No third-party Swift packages ([0004](adr/0004-no-third-party-deps.md))
- No signing identities in the tree ([0005](adr/0005-generated-unsigned.md))
- No single multi-platform SwiftUI target ([0006](adr/0006-four-native-apps.md))
- No per-capability screens; the UI is generic on travelling schema ([0002](adr/0002-capability-driven.md))
- No CodeQL / Super-Linter / Scorecard / Semgrep / Trivy / Sonar in CI

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│  DiffuseMac  DiffuseiOS  DiffuseiPadOS  DiffuseWatch  CLI   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                         DiffuseUI
                               │
              ┌────────────────┴────────────────┐
              │                                 │
     DiffuseCollectors                 DiffuseCore
     DiffuseDeveloperTools                    │
              │                    ┌──────────┼──────────┐
              │                    │          │          │
     DiffuseCapabilities    DiffuseDiff  DiffuseStorage  DiffuseModels
```

**Strict direction.** Arrows point toward dependencies:

```
Apps → DiffuseUI → DiffuseCapabilities / DiffuseCore → DiffuseModels
                                                     → DiffuseDiff
                                                     → DiffuseStorage
```

Apps depend on UI and collectors. UI depends on Core. Core depends on Models, Diff, Storage, and Capabilities. Collectors depend on Capabilities and (on Mac) DeveloperTools. Core packages never import AppKit, UIKit, or WidgetKit. That is enforced by `./Scripts/crosscheck.sh ios` and `watchos`.

A new `import` that points the wrong way is an architecture bug, not a convenience.

| Package | Lives in | Owns |
| --- | --- | --- |
| DiffuseModels | `Packages/DiffuseModels` | Vocabulary: snapshot, entity, schema, change, privacy, version |
| DiffuseDiff | `Packages/DiffuseDiff` | Compare two snapshots; no I/O |
| DiffuseStorage | `Packages/DiffuseStorage` | Persist, query, retain, validate, migrate |
| DiffuseCapabilities | `Packages/DiffuseCapabilities` | Catalog, collector protocol, environment doubles |
| DiffuseCore | `Packages/DiffuseCore` | Coordinator, service, scheduler, search, reports, ledger, fixtures |
| DiffuseDeveloperTools | `Packages/DiffuseDeveloperTools` | Process runner + tool adapters (types compile everywhere) |
| DiffuseCollectors | `Packages/DiffuseCollectors` | Platform collectors and the three registries |
| DiffuseUI | `Packages/DiffuseUI` | Design system + generic renderers + `DiffuseModel` |
| diffuse-dev | `Tools/diffuse-dev` | CLI; no SwiftUI |

### DiffuseModels

The vocabulary every other package speaks: identifiers, snapshots, entities, `PropertyValue`, travelling `SectionSchema`, changes, privacy classification, semantic versions, platforms, origins.

If two packages need to agree on a word, it lives here. Models has no I/O and no Apple-framework imports.

### DiffuseDiff

Compares two snapshots using the schema that travelled with them. Identity matching, `ValueComparator` (exact, case-insensitive, path, semver, numeric/relative tolerance, unordered lists, ignored), severity evaluation, change correlation.

Adding a capability **must not** change this package. New comparison kinds are new `ComparisonRule` cases with tests, not `if capability == .docker`.

See [DiffEngine.md](DiffEngine.md).

### DiffuseStorage

`SnapshotStore` protocol, `InMemorySnapshotStore` for tests and the CLI, `FileSnapshotStore` (one JSON file per snapshot + rebuildable `index.json`, atomic writes), `SnapshotCoding`, `SnapshotMigrator`, `RetentionPlanner`, `SnapshotValidator`, `SnapshotQuery`.

Storage does not know how to diff. Diff does not know how to persist. See [Storage.md](Storage.md).

### DiffuseCapabilities

`DiffuseCapability`, `SnapshotCollector`, `CollectedSection`, `CapabilityCatalog`, availability, enablement, environment doubles (`TimeSource`, `FileSystemProviding`, `ProcessRunning`).

The catalog is the live answer to “what can we observe *right now*?” — enabled, available, permission-required, unsupported.

### DiffuseCore

The product façade:

- `SnapshotCoordinator` — concurrent collectors, per-collector deadline, isolation (one failure never fails the snapshot)
- `SnapshotService` — capture, persist, retain, diff, search, import/export, overview, timeline
- `SnapshotScheduler` — pure decide function; platforms supply timers
- `SearchIndex` / `ChangeSearchIndex`
- `ReportRenderer` — Markdown and plain text, shared by apps and CLI
- `PrivacyLedger` — generated from live metadata, including `neverCollected`
- `ChangeTimeline` — pairwise history and clusters
- `SampleData` / `FixtureGenerator` — deterministic fixtures and SwiftUI previews

### DiffuseDeveloperTools

Process runner and tool adapters (`node`, `python`, `git`, `docker`, `brew`, `rustc`, `go`, `terraform`, `swift`, …). Runtime is macOS; the types compile everywhere so Core and tests can stay platform-agnostic.

Adding support for a *tool version* is an adapter. Adding a *new kind of observation* is a capability.

### DiffuseCollectors

Platform collectors and three registries. This is the only place Apple-platform APIs belong for an observation.

| Registry | Capabilities |
| --- | --- |
| `MacCapabilityRegistry` | system, hardware, displays, power, network interfaces, network path, Wi-Fi, storage (all volumes), applications, processes (opt-in), developer tools, git (watched repos) |
| `IOSCapabilityRegistry` | device, system, battery, screen, storage (app-container volume), network interfaces, network path — iPhone and iPad share this type; snapshots report `.iOS` vs `.iPadOS` |
| `WatchCapabilityRegistry` | watch device, battery, system, storage (container volume), network path |

The two iOS apps expose different UI, not different invent-a-collector-for-iPad work.

Developer-tool *adapters* (node, python, git, docker, brew, rustc, go, terraform, swift, xcodebuild, …) are data in `BuiltInToolAdapters`. Adding Bun is an adapter row, not a new capability. Adding Bluetooth peripherals would be a capability.

### DiffuseUI

Design system and generic renderers: change rows, section views, capability list, privacy ledger, timeline, search, preference surfaces. `DiffuseModel` is the shared `@Observable` app state. Screens **do not** `switch` on capability IDs.

Four app targets own navigation, widgets, and platform scheduling. See [Apps.md](Apps.md).

### diffuse-dev

A CLI that imports **no** UI framework. Proof that capture, diff, validate, export, and the privacy ledger are domain operations. It writes files you name; it does not open the app’s Application Support library unless you point a store there. See [CLI.md](CLI.md).

## Adding a capability

1. Typed collected section + `SectionSchema` (usually next to the collector).
2. Register it on the platform registry that can actually observe it.
3. Fake-based tests in `Packages/…/Tests` and, for public API behaviour, `Tests/Domain`.
4. Fixture update only if a golden expected-diff genuinely changed — and explain why.

You do **not** edit the diff engine, the store, search, export, or app screens. If you find yourself adding a SwiftUI view for one capability, stop. That invariant is tested in `Tests/Integration` (`ExtensibilityTests`): a capability nothing else has heard of still captures, stores, diffs, searches, exports, and appears on the privacy ledger.

Details: [CapabilityGuide.md](CapabilityGuide.md), [CollectorGuide.md](CollectorGuide.md).

## Data flow

1. The app (or CLI) asks `SnapshotService` to capture, with an origin (manual, scheduled, triggered, imported, synthetic).
2. `SnapshotCoordinator` asks the catalog for the collection plan, then runs enabled collectors concurrently. Each has a deadline. A throw becomes `CollectionStatus.failed` plus a diagnostic. A hang is abandoned as `.timedOut`. Missing permission is `.permissionRequired`. Disabled is `.skipped`.
3. Each collector returns a `CollectedSection`, stored as a `SnapshotSection` **including its schema**.
4. `skipIfUnchanged` (automatic captures only) diffs against the latest stored snapshot and may skip persist.
5. The file store writes an envelope JSON atomically and updates `index.json`.
6. Retention runs **after** save so the new snapshot always survives a tight limit. The newest snapshot is never deleted.
7. A later capture diffs against a previous one. The UI renders `Change` values generically. Search indexes snapshots, sections, entities, and properties without knowing what Git or Docker is.
8. Widgets and complications receive a two-field summary (`Δ N` + peak severity) via an app group. They never decode a snapshot.

```
capture  →  coordinator  →  sections+schema  →  store  →  retain
                │
                └─ (later)  diff / timeline / search / export
```

## Scheduling (product, not a daemon)

`SnapshotScheduler.decide` is a pure function of `(schedule, lastCapture, now, systemEvent)`. Platforms drive it:

| Platform | Mechanism |
| --- | --- |
| macOS | `Timer` + wake/unlock notifications |
| iOS / iPadOS | `BGAppRefreshTask` + capture on open |
| watchOS | `WKApplicationRefreshBackgroundTask` |

Rules that must not fork per platform:

- Disabled = cadence off **and** no system-event captures.
- Default cadence is every four hours with a **15-minute floor** on every trigger, including wake, so a laptop that sleeps repeatedly does not flood the timeline.
- First run with no history captures immediately when the schedule is enabled.
- `skipsWhenUnchanged` is applied by `SnapshotService`, not by `decide`.

## Platform notes

- **macOS** is not sandboxed. Developer-tool collection shells out. Documented in [Privacy.md](Privacy.md), not papered over with temporary-exception entitlements.
- **iOS / iPadOS** snapshot on open, on demand, and on background refresh. They do not pretend to be a daemon.
- **watchOS** is standalone (`WKRunsIndependentlyOfCompanionApp`). No paired iPhone required.
- **Android** is a separate Kotlin/Compose runtime. It follows the same local-first, schema, diff, privacy, and retention semantics without importing Swift artifacts. See [Android/README.md](../Android/README.md).
- Core modules type-check against non-host SDKs via `Scripts/crosscheck.sh`.
- iPad regular-width layout stays three columns (`IPadRootView.threeColumnWorkspace`) instead of collapsing `NavigationSplitView` in portrait.

## Tests as architecture

The extensibility claim is false unless tests add a capability nothing else knows and every downstream layer handles it. That suite lives in `Tests/Integration`. Seeded invariants (empty self-diff, newest snapshot never pruned, wait dates, redaction monotonicity) live in `Tests/Invariants`. Example-based public API coverage lives in `Tests/Domain`. See [Testing.md](Testing.md).

## What is not here

- Cloud sync ([0008](adr/0008-no-cloud-sync.md))
- Third-party Swift dependencies ([0004](adr/0004-no-third-party-deps.md))
- Signing identities, teams, or provisioning profiles ([0005](adr/0005-generated-unsigned.md))
- A single multi-platform SwiftUI target ([0006](adr/0006-four-native-apps.md))
- Inference, anomaly detection, or an LLM in the diff path — clustering is interval grouping, search is term matching
