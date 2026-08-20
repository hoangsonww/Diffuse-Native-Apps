# Snapshot schema

A snapshot is a point-in-time record of selected capabilities on one device. The schema that describes each section **travels inside the snapshot**.

This is the compatibility contract. Breaking it without a migrator strand users’ libraries. See [adr/0003-schema-driven-diff.md](adr/0003-schema-driven-diff.md).

## Envelope

On disk and on the wire, a snapshot is pretty-printed JSON (`SnapshotCoding`) with a **stable outer envelope** so AirDrop / email / a GitHub gist still decode:

```json
{
  "format": "diffuse.snapshot",
  "schemaVersion": 1,
  "exportedAt": "2026-08-19T09:04:00.000Z",
  "snapshot": { }
}
```

Diff exports use `"format": "diffuse.diff"` around a `DiffResult`. File extension for a snapshot export is `.diffuse.json`. Keys are sorted so two encodes of the same value are byte-identical (golden fixtures depend on that).

Inside `snapshot`:

- Snapshot identity (`SnapshotID`), capture time (ISO-8601 **with milliseconds**), origin, optional label / note / pin / tags
- Device identity (per-install identifier — not a hardware serial — plus model, OS name/version, architecture)
- App version and `SchemaVersion`
- Sections, each with collector id + version, timing, status, entities, attributes, diagnostics, **and** the `SectionSchema` that produced them
- Snapshot metadata (collection duration, applied redaction, skipped capabilities)

Dates round-trip at millisecond precision (`Date.roundedForSnapshot()`). Foundation’s default ISO-8601 encoder drops milliseconds; that broke fixture round-trips, which is why coding is explicit. Whole-second timestamps are tolerated on decode for hand-written fixtures.

Diagnostic IDs are derived from content so the same problem produces the same id. Snapshot IDs for live captures are UUIDs; fixtures and tests use fixed strings.

## Origins

| Origin | Meaning |
| --- | --- |
| `manual` | The user pressed capture. Never skipped by `skipIfUnchanged`. |
| `scheduled` | Cadence fired |
| `triggered` | System event (wake, unlock) |
| `imported` | Read in from another device’s export. New id, tag `imported`. |
| `synthetic` | Tests and fixtures |

Import **rewrites** the id so two libraries can both hold a copy without colliding, and sets origin to `.imported` so it is never mistaken for a local capture.

## Schema version

`SchemaVersion` is currently **v1**. `SnapshotMigrator` has an empty v1 chain: there is nothing to migrate yet.

When a breaking change is required:

1. Add a stepped migrator that can read the previous version.
2. Bump `SchemaVersion.current`.
3. Keep `minimumSupported` honest.
4. `SnapshotValidator` already flags snapshots newer than this build.

Prefer additive property descriptors over renames. Reusing a key with a new meaning silently corrupts diffs.

## Section schema

Each `SectionSchema` declares:

- `capability` id and display metadata (name, summary, category, symbol)
- Privacy classification for the section as a whole (combined with per-property privacy via `max` on export)
- `entityKinds` with property descriptors, addition/removal severity
- Section-level `attributes` (counts, totals — not attached to an entity)
- Display order

Each `PropertyDescriptor` declares:

- Key, display name, optional unit (bytes, percent, version, path, …)
- `ComparisonRule` (see below)
- Severity if the value changes
- Privacy classification
- Whether it is a **primary** property (shown in summaries; if redacted, the entity display name is redacted too)

Unknown properties still *diff* using a permissive fallback descriptor so a future field is not silently dropped. They **fail validation** on a snapshot this build produced — that is how we keep collectors honest.

## Comparison rules

The diff engine does not hard-code “OS versions use semver.” The descriptor does. That is why an unknown future capability still diffs correctly: its snapshot carries the rules.

| Rule | Behaviour |
| --- | --- |
| `exact` | Byte-for-byte `PropertyValue` equality |
| `caseInsensitive` | Trim + case-insensitive strings |
| `pathNormalized` | Home directory and trailing slashes collapsed |
| `semanticVersion` | Semver precedence; `1.2` equals `1.2.0`; build metadata ignored |
| `numeric(tolerance:)` | Absolute window, in the property’s unit |
| `relative(tolerance:)` | Fractional window of the larger magnitude (free space, byte counts) |
| `unordered` | Lists compared as sorted bags |
| `ignored` | Recorded but never a change (timestamps, noisy counters) |

Defaults follow the unit: bytes → relative 1%, percent → numeric 0.05, path → pathNormalized, version → semanticVersion, timestamp → ignored.

Appearing or disappearing values are always a real difference unless the rule is `ignored`.

Semver: a pre-release is less than its release; `2.0.0` and `2.0.0+build.9` have the same precedence (rebuild, not an upgrade). Major jumps can escalate severity.

## Identity vs display name

Entities match on `EntityIdentity` (kind + normalized value + optional scope). Display-name changes are property changes, and are omitted when a more specific property already explains them (e.g. an SSID change).

## Unknown capabilities

A snapshot from a newer app may contain a section the current app has never heard of. Storage, diff, search, export, and UI still handle it: they read the travelling schema. The current app simply cannot *capture* that section until it ships the collector.

Covered by the integration test “A snapshot from an unknown capability still diffs and renders.”

## Validation

`SnapshotValidator` encodes invariants the type system cannot:

- Non-empty id, real capture date, schema version this build understands
- One section per capability
- Schema capability id matches the section
- Entity kinds and property keys are described
- Identities unique within a section
- Non-collecting statuses do not still carry entities
- JSON encode → decode → encode is byte-stable

Used by `diffuse-dev validate`, fixture generation, and the test suite.

## Fixtures

Golden snapshots live in `Fixtures/snapshots/`. Expected diffs live in `Fixtures/diffs/`. They are generated from `FixtureGenerator` / `SampleData` — no `Date()`, no `UUID()`, no environment lookups.

```bash
./Scripts/generate-fixtures.sh
swift test --parallel --filter DiffuseIntegrationTests
```

Review the git diff. Do not regenerate to hide a behavioural change. Do not weaken an expected diff to make a test pass.
