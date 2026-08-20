# Capability guide

A **capability** is something Diffuse knows how to observe: storage, Wi-Fi, developer tools, battery. It is the unit of extension.

Read this together with [CollectorGuide.md](CollectorGuide.md) and [adr/0002-capability-driven.md](adr/0002-capability-driven.md). The repo skill `.agents/skills/add-capability/SKILL.md` is the short procedural version.

## Why capabilities exist

Without them, every new observation becomes a special case in the diff engine, the store, search, export, and four apps. With them, those layers stay generic and the new work is:

1. A typed model of the observation
2. A collector that produces it
3. A registry line on each platform that can actually see it
4. Tests with a fake (and a fixture only if golden diffs genuinely change)

If you are editing `DiffuseDiff`, `FileSnapshotStore`, `SearchIndex`, `ReportRenderer`, or a SwiftUI screen in order to “support” the new thing, you have broken the architecture. Stop and put the knowledge on the schema instead.

`Tests/Integration/ExtensibilityTests` adds a fake “Rust toolchain” capability that nothing in the apps has heard of, then asserts coordinator, validator, storage, diff, search, export, privacy ledger, and timeline all handle it.

## Anatomy

A capability is three things bound together:

| Piece | Role |
| --- | --- |
| `CapabilityID` | Stable string, e.g. `storage.volumes`. **Never rename it.** Old snapshots on disk still carry the old id. |
| `SectionSchema` | Travels inside every snapshot. Tells the diff engine how to match entities, how to compare properties, how severe a change is, and how sensitive a field is. |
| `SnapshotCollector` | Reads the live system and returns a `CollectedSection`. |

`AnyCapability` type-erases a concrete collector so a registry can hold a heterogeneous list. `CapabilityCatalog` applies enablement, availability, cost, and platform filters, and is the source for the privacy ledger.

`CapabilityMetadata` is what settings, the ledger, and `diffuse-dev capabilities` show: display name, summary, collection description, category, symbol, privacy, platforms, default enablement, cost.

## Availability

Collectors declare what they need (Location for Wi-Fi names, a process runner for developer tools). The catalog surfaces this in the UI so a missing permission is a first-class state, not a silent empty section.

Typical states:

| Availability | Section status | What the user sees |
| --- | --- | --- |
| Available | `.collected` / `.partial` | Data |
| Permission required | `.permissionRequired` | Why, and that it is fixable |
| Unavailable (not installed) | `.unavailable` | Honest empty, not a crash |
| Unsupported on this OS | hidden from discoverable UI | Watch does not list Docker |
| Timed out / failed | `.timedOut` / `.failed` | Diagnostic with a stable id |

See the `mac-permission-loss` golden fixture: losing a permission is a **status change**, not data loss.

## Enablement

Most capabilities are on by default. A few are not:

- **Processes** (`MacProcessCollector`) — opt-in. Listing every process is useful and also noisy and identifying.

Disabled capabilities stay **discoverable** so Settings can show a toggle. They do not run. The snapshot records them in `metadata.skippedCapabilities`.

Background captures skip expensive collectors (`CollectionCost.high`) so a wake snapshot does not shell out a fleet of `--version` processes.

## Identity

Entities inside a section have an `EntityIdentity`: kind + normalized value + optional scope. The diff engine matches on that, **not** on display name.

If a volume’s name changes but its UUID does not, that is a property change, not a remove+add. If you used the name as the id, every rename looks like a deletion.

Choose identifiers that survive the thing being renamed:

| Thing | Prefer | Avoid |
| --- | --- | --- |
| App | Bundle identifier | Localized name |
| Volume | Volume UUID | Mount path |
| Network interface | BSD name | Display name |
| Git repo | Normalized path (`EntityIdentity.path`) | Whatever `pwd` printed today |
| Tool | Adapter id (`node`) | Whatever the binary’s `--version` banner said |

`EntityIdentity` collapses case, whitespace, and (for paths) home directory + trailing slashes. Collectors should still pass the raw path through `EntityIdentity.path` rather than inventing a second normalization.

## Schema is travelling

The schema is serialized **into** the snapshot. A newer app can still diff an older snapshot because the comparison rules travelled with the data. An older app can still *render* a section it cannot capture.

Changing a schema is therefore a compatibility event — see [SnapshotSchema.md](SnapshotSchema.md). Prefer additive property descriptors. Never reuse a property key with a new meaning.

## Privacy on the capability

Every section and every property descriptor has a `PrivacyClassification`. Defaults are not a license to be vague. Restricted fields should not be collected; if they exist on the schema for completeness, export still strips them even under `RedactionPolicy.none`.

See [Privacy.md](Privacy.md) and [adr/0007-privacy-classification.md](adr/0007-privacy-classification.md).

## Platform registries

```
MacCapabilityRegistry     // MacCapabilityRegistry.swift — the Mac app’s only compile-time list
IOSCapabilityRegistry     // shared by iPhone and iPad apps
WatchCapabilityRegistry   // Watch app
```

The Mac app’s only compile-time list of “what we observe” is the array in `MacCapabilityRegistry`. **Append there.** Do not `switch` on capability IDs in UI or Core.

Do not register a Watch collector that enumerates Mac apps. Platform honesty is part of the product.

What each registry actually ships today:

| Registry | Observations |
| --- | --- |
| `MacCapabilityRegistry` | system, hardware, displays, power, network interfaces & path, Wi-Fi, all volumes, applications, processes (opt-in), developer tools, git watch list |
| `IOSCapabilityRegistry` | device, system, battery, screen, app-container volume, network interfaces & path |
| `WatchCapabilityRegistry` | watch device, battery, system, container volume, network path |

A *tool version* (Deno, Zig, Elixir) is a `ToolAdapter` in `BuiltInToolAdapters`, not a new capability. A *new kind of observation* (Bluetooth peripherals, launch agents) is a capability.

## Cost and background captures

`CollectionCost` (low / high) lets the coordinator skip expensive work when `isBackground: true`. Developer-tool probes and process listings are the usual high-cost work. System info and battery are low.

## Checklist

- [ ] Stable `CapabilityID` (dot-separated, lowercase, never renamed)
- [ ] `SectionSchema` with entity kinds, property descriptors, comparison rules, privacy, severity, addition/removal severity
- [ ] Collector isolated: a throw becomes a diagnostic; identities are stable; no `UUID()` in diagnostics
- [ ] Registered only on platforms that can observe it
- [ ] Fake-based unit tests (no live hardware in CI)
- [ ] Domain or invariant coverage if you introduced a new public type
- [ ] Fixture update **only** if golden diffs genuinely change, with an explanation
- [ ] Privacy ledger description is a fact (“runs `rustc --version`”), not a slogan
