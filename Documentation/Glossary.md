# Glossary

Short definitions for words Diffuse uses as product vocabulary. Prefer these over inventing a synonym in UI copy, ADRs, or commit messages.

| Term | Meaning |
| --- | --- |
| **Capability** | Something Diffuse knows how to observe (`storage.volumes`, `network.wifi`). Stable id + travelling schema + collector. See [CapabilityGuide.md](CapabilityGuide.md). |
| **Collector** | The code that reads live system state and returns a `CollectedSection`. The only place Apple-platform APIs belong for that observation. |
| **Catalog** | `CapabilityCatalog`. The live answer to “what can we observe *right now*?” after enablement, availability, cost, and platform filters. |
| **Registry** | Compile-time list of capabilities for one platform (`MacCapabilityRegistry`, `IOSCapabilityRegistry`, `WatchCapabilityRegistry`). Append here; do not `switch` on ids in UI. |
| **Snapshot** | A point-in-time record of selected capabilities on one device. JSON on disk. Immutable after persist (annotate is metadata only). |
| **Section** | One capability’s contribution to a snapshot, including entities, diagnostics, status, and the **schema that travelled with it**. |
| **Entity** | One observed thing inside a section (a volume, an app, a tool). Matched across snapshots by `EntityIdentity`, not by display name. |
| **Property** | A typed field on an entity (`PropertyValue`) with a descriptor: comparison rule, severity, privacy, unit. |
| **Travelling schema** | `SectionSchema` serialized inside the snapshot so a future (or older) app can still diff and render it. [ADR 0003](adr/0003-schema-driven-diff.md). |
| **Diff / Change** | `DiffEngine` output. A `Change` is content-identified (no `UUID()`). `diff(A, A)` is empty. |
| **Severity** | Informational → notable → significant → critical. Peak severity is what widgets show next to `Δ N`. |
| **Origin** | Why the snapshot exists: `manual`, `scheduled`, `triggered`, `imported`, `synthetic`. Manual is never skipped by skip-if-unchanged. |
| **Skip-if-unchanged** | Automatic captures may skip persist when the latest stored snapshot diffs empty. Manual captures always persist. |
| **Retention** | `RetentionPlanner`: age, count, and size caps. Newest snapshot is never deleted. Default 90 days / 1 GiB, protecting pinned and labelled. |
| **Redaction** | Copy of a snapshot (or report) with fields stripped by `RedactionPolicy`. Does not mutate the library. `restricted` always goes. |
| **Privacy classification** | `public` / `local` / `sensitive` / `restricted` on every section and property. [ADR 0007](adr/0007-privacy-classification.md). |
| **Privacy ledger** | Generated inventory of what is collected, from live catalog metadata. `diffuse-dev privacy` and the in-app Privacy screen. |
| **neverCollected** | Design commitment (tested): passwords, Keychain, private keys, `.env` values, file contents, message/mail/photo/browsing history, location, anything sent off-device. |
| **App group summary** | Two-integer widget payload (`changeCount`, `peakSeverity`, `capturedAt`). Never a snapshot. |
| **Floor** | 15-minute minimum between captures, including wake/unlock, so a laptop that sleeps repeatedly does not flood the timeline. |
| **Cross-check** | `./Scripts/crosscheck.sh ios` / `watchos` — type-check core packages against non-host SDKs. |
| **Fixture** | Deterministic golden snapshot or expected diff under `Fixtures/`. Regenerated only with `./Scripts/generate-fixtures.sh`. |
| **Unsigned CI** | Builds with `CODE_SIGNING_ALLOWED=NO`. Widgets compile but show empty without an app-group container. [ADR 0005](adr/0005-generated-unsigned.md). |

Related product language that is **deliberately unused**: account, cloud, sync, telemetry, anomaly detection, “AI diff.”
