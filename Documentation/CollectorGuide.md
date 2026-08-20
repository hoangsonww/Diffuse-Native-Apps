# Collector guide

A collector reads live system state and returns a `CollectedSection`. It is the only place Apple-platform APIs belong for a given observation.

Read [CapabilityGuide.md](CapabilityGuide.md) first. Debug hangs and throws with skill `debug-collector`.

## Contract

```swift
func collect(context: CollectionContext) async throws -> some CollectedSection
```

The section must:

- Match the capability’s `SectionSchema` (capability id, entity kinds, property keys)
- Emit entities with stable identities (see the capability guide)
- Emit only properties declared on that schema — `SnapshotValidator` rejects undeclared keys
- Finish within the coordinator’s per-collector deadline, or be cancelled cleanly (`Task.checkCancellation` / cooperative `Task.sleep`)
- Use `PropertyValue.timestamp(_:)` for dates so millisecond rounding matches JSON

The coordinator runs collectors concurrently and **isolates** failures. One collector throwing does not fail the snapshot; it records `CollectionStatus.failed` and a diagnostic. A hang is abandoned at the deadline as `.timedOut`. Tests cover this with `FakeCollector.Behaviour.hang` and `.fail` — never by waiting on real hardware.

## Shared vs platform

| Location | Examples |
| --- | --- |
| `DiffuseCollectors/Shared` | system info, storage, network interfaces, network path |
| `…/macOS` | hardware, displays, power, Wi-Fi, applications, processes, developer tools, git |
| `…/iOS` | device, battery, screen |
| `…/watchOS` | device, battery |

Guard Apple-only APIs with `#if os(macOS)` / `#if os(iOS)` / `#if os(watchOS)`. Shared collectors take a `platforms:` argument so the same type can register on Mac and iPhone with different footnotes (storage enumerates all volumes on Mac, the app container’s volume on iOS).

Core packages must still type-check for iOS and watchOS. If you need an AppKit type, it does not belong in `DiffuseCore`.

## Environment doubles

Do not call `FileManager.default`, `Date()`, or `Process` if a test needs to control them.

| Production | Test double |
| --- | --- |
| `SystemTimeSource` | `FixedTimeSource` |
| `FileManager` via `FileSystemProviding` | a fake filesystem |
| `SystemProcessRunner` | `FakeProcessRunner` |

Developer-tool collectors take `ProcessRunning` so CI never requires Node or Docker to be installed. `Tests/Support/FakeCapabilities.swift` builds a capability around `FakeCollector` for coordinator, service, and integration tests.

## Process tools (macOS)

`SystemProcessRunner` launches `git`, `node --version`, and friends. GUI apps inherit a tiny `PATH`; the runner adds `/opt/homebrew/bin`, `/usr/local/bin`, and similar. Do not parse `ls` output when a structured flag exists (`git status --porcelain=v2`, `brew info --json`). Timeouts belong in the runner / coordinator, not in an unbounded `readToEnd`.

Tool adapters live in `DiffuseDeveloperTools` (`BuiltInToolAdapters`: language runtimes, package managers, infrastructure including Docker/terraform, Apple tooling including git/Xcode). Adding `node` support was an adapter, not a new capability. Adding *a new kind of observation* is a capability.

## Privacy in collectors

- Classify every property. “I’ll fix privacy later” is how SSIDs leak in bug reports.
- Do not collect secrets (tokens, keychain, file contents, clipboard, `.env` values, SSH keys).
- **Git:** branch, dirty flag, ahead/behind, remote **host**. No paths inside the repo, no diffs, no file names, no commit messages.
- **Wi-Fi:** SSID only, and only when Location is granted on macOS. No BSSID, no coordinates, no scan lists.
- **Processes:** opt-in at the capability (`isEnabledByDefault: false`).
- Redaction happens on **export**, not on collection. The on-device snapshot keeps the real SSID so the next diff can see it change.

See [Privacy.md](Privacy.md).

## Diagnostics

If a permission is missing or a tool is absent, return a structured diagnostic with a **content-derived** identifier (not `UUID()`). Fixtures and JSON round-trips must be stable. The same problem on two captures should produce the same diagnostic id.

Empty sections with a non-collecting status (`.permissionRequired`, `.unavailable`, …) must **not** still carry entities. The validator rejects that contradiction.

## Collection context

Use `CollectionContext` for the clock, whether this is a background capture, and any per-run notes the coordinator passed in. Do not read `Date()` for `collectedAt`; the injected clock is what makes fixtures and `skipIfUnchanged` reproducible.

## Testing

Prefer a fake filesystem / fake process runner over live collection. Live capture belongs in integration tests that are macOS-gated and use **cheap, stable** capabilities (system info, hardware, displays — not battery or free space) when asserting that two back-to-back captures are quiet.

```bash
swift test --parallel --filter MacGitCollector
swift test --parallel --filter DiffuseCollectorsTests
swift run diffuse-dev snapshot --repos "$HOME/code/some-repo"
swift run diffuse-dev capabilities
```

If a collector only fails on hardware, record the `CollectionOutcome` and the travelling schema. Do not add a platform `#if` in the diff engine to paper over it.
