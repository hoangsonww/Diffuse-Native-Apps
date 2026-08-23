# Testing

The Apple engine uses [Swift Testing](https://developer.apple.com/xcode/swift-testing/) (`@Test`, `#expect`, `@Suite`). No new XCTest modules. Android uses JUnit for Kotlin domain tests and AndroidX/Compose instrumentation for device behavior. Physical hardware is not required; simulator/emulator coverage is supplemented by a small macOS-gated pair of stable live-collector tests.

## Android suites

| Layer | Path | Covers |
| --- | --- | --- |
| Kotlin/JVM | `Android/app/src/test/` | Models, JSON, diff, privacy, storage, retention, search, reports, scheduling, coordinator |
| Fixture contract | `FixtureCompatibilityTest` | Decoding Swift snapshots and matching expected structural diffs |
| Android instrumentation | `Android/app/src/androidTest/` | Collectors, preferences, service/storage, Compose navigation/dialogs/rotation/layout |

```bash
cd Android
./gradlew testDebugUnitTest
./gradlew jacocoDebugUnitTestReport jacocoDebugUnitTestCoverageVerification
./gradlew connectedDebugAndroidTest
./gradlew lintDebug assembleDebug bundleRelease
```

JaCoCo enforces at least 90% line coverage for the pure `com.diffuse.android.domain` package. Android framework and Compose behavior are measured by instrumentation rather than inflating the JVM number with mocks.

See `Tests/AGENTS.md` and skill `write-tests`. Coverage: skill `coverage`. Layout of the tree: [Repository.md](Repository.md).

## Where a test goes

| Kind | Path | SPM target |
| --- | --- | --- |
| Example-based public API | `Tests/Domain/` | `DiffuseDomainTests` |
| Seeded invariant (“for any generated input”) | `Tests/Invariants/` | `DiffuseInvariantTests` |
| Golden fixtures, live capture, extensibility, pipelines | `Tests/Integration/` | `DiffuseIntegrationTests` |
| Package-private details | `Packages/<Name>/Tests/` | `<Name>Tests` |
| Shared builders and fakes | `Tests/Support/` | `DiffuseTestSupport` |

Do not move package-local suites into `Tests/` “for consistency.” Package tests stay next to the code they pin. `Tests/` is for behaviour that spans packages or is the product-level contract.

A change that only touches `MacGitCollector` belongs in `Packages/DiffuseCollectors/Tests`. A change to “export redaction never leaks a restricted field” belongs in `Tests/Domain` **and** a seeded case in `Tests/Invariants` if it is supposed to hold for arbitrary snapshots.

## Suite map

### `Tests/Domain` (example-based)

| File | Pins |
| --- | --- |
| `ComparatorAndModelTests.swift` | `PropertyValue`, comparison rules, identifiers, semantic version |
| `SnapshotServiceAndStoreTests.swift` | capture, persist, skip-if-unchanged, import/export, annotate |
| `SnapshotQueryTests.swift` | filters, sort, paging stability |
| `RetentionPlannerTests.swift` | newest-kept, pins/labels, age vs size vs count |
| `SchedulerTests.swift` | cadence, floor, system events, disabled |
| `SearchIndexTests.swift` | library search vs change-index empty-query behaviour |
| `PrivacyAndRedactionTests.swift` | policies, `neverCollected`, restricted-on-local-section |
| `ReportRendererTests.swift` | Markdown / plain text, severity floor, footer |
| `ValidatorTests.swift` | `SnapshotValidator` structural rules |
| `ChangeTimelineTests.swift` | pairwise history, clusters |

### `Tests/Invariants` (seeded)

| File | Pins |
| --- | --- |
| `ValidatorSearchRedactionInvariants.swift` | round-trip, redaction monotonicity, search |
| `RetentionSchedulerQueryInvariants.swift` | newest never pruned, scheduler floor, query |

Print the seed on failure (`SeededGenerator`). A flake you cannot reproduce is a bug in the generator or the assertion, not a reason to skip.

### `Tests/Integration`

| File | Pins |
| --- | --- |
| `IntegrationTests.swift` | golden fixtures, live capture (macOS-gated), unknown-capability render |
| `PipelineTests.swift` | capture → store → diff → search → export → ledger as one path |
| `ExtensibilityTests` (in Integration) | a capability nothing else has heard of still works end-to-end |

### Package-local

`Packages/*/Tests` cover Models, Diff (including property-based shuffle/self-diff), Storage, Capabilities, Core, Collectors, DeveloperTools, UI primitives. Keep them.

## Support types

`DiffuseTestSupport` provides:

- `SnapshotBuilder` — deterministic snapshots; chain `.labelled`, `.pinned`, `.tagged`, `.on(platform)`, `.withWidgets`
- `TestSchema` — a minimal widgets schema with comparison/privacy knobs
- `FakeCollector` / `FakeCapabilityFactory` — succeed, fail, hang, delay
- `SeededGenerator` — xorshift64*; failures must print the seed
- `SnapshotSummary.stub` — retention and query rows without a full snapshot
- `TemporaryLibrary` — scratch directories
- `FixtureLocator` — `Fixtures/` via `#filePath`

Use `FixedTimeSource` and `StaticDeviceIdentityProvider.testDevice`. Do not call `Date()` or `UUID()` in assertions unless the test is specifically about allocation.

## Invariants worth knowing

These are encoded as tests, not slogans:

- `diff(A, A)` is empty; reverse diffs swap added/removed; shuffle of entities does not change the diff
- Newest snapshot is never in a retention deletion list
- Empty/whitespace search queries return nothing (library search)
- `ChangeSearchIndex` empty query returns **all** changes (filter field)
- Stricter redaction never reveals what a looser policy hid
- `Snapshot.redacted` always walks property descriptors, so a `restricted` field on a `local` section is still stripped under `RedactionPolicy.none`
- `SnapshotScheduler` disabled never captures; the 15-minute floor applies to system events
- Cadence `.off` means “wait for a system event”; `until` may be in the past — do not assert `until >= now` in that state
- A well-formed generated snapshot validates and JSON-round-trips
- Adding a capability nothing else knows still captures, stores, diffs, searches, exports, and appears on the privacy ledger
- Labelled snapshots are retention-protected by default (empty labels are not). Count-limit tests must set `protectsLabelled: false` or omit labels
- `skipIfUnchanged` applies to automatic captures only; origin `.manual` always persists

## Fixtures

`Fixtures/snapshots/` and `Fixtures/diffs/` are the integration contract. See [Fixtures/README.md](../Fixtures/README.md).

```bash
./Scripts/generate-fixtures.sh
swift test --parallel --filter DiffuseIntegrationTests
```

`FixtureGenerator` and `SampleData` must stay deterministic. Do not weaken an expected diff to hide a bug. If the engine is wrong, fix the engine.

## Commands

```bash
swift test --parallel
swift test --filter DiffuseDomainTests
swift test --filter DiffuseInvariantTests
swift test --filter DiffuseIntegrationTests
swift test --filter MacGitCollector
./Scripts/coverage.sh
```

`./Scripts/verify.sh` is the full Apple gate: format lint, tests, iOS/watchOS cross-check, unsigned builds of all four Apple apps. Run the Gradle commands above for the Android gate.

## Coverage

First-party LLVM coverage. **Do not** add Codecov, Coveralls, or Code Climate.

```bash
./Scripts/coverage.sh
```

Writes gitignored `coverage/`:

- `summary.txt` / `summary.md` — line coverage by file (CI appends this to the job summary)
- `coverage.lcov`
- `html/index.html`

CI uploads `coverage/` as an artifact (`coverage-report`, 14 days).

**The total is a hard gate.** `coverage.sh` fails below 90% package line coverage; it currently sits at 92.4%. Raise the floor with `DIFFUSE_MINIMUM_COVERAGE`, never lower it to make a run pass. Still read the per-file report as well — a healthy total can hide one file that fell off a cliff.

`DiffuseUI` view bodies are covered by `Tests/Domain/ViewRenderingTests.swift`, which renders every public view through `ImageRenderer` on macOS. That evaluates the whole body, so a view that traps on a nil optional, an empty collection, or an unexpected enum case fails the suite rather than shipping to four clients at once. Its fixtures are the real `SampleData` snapshots run through the real `DiffEngine`, so views are exercised on production-shaped data. When you add a public view, add it there and render its empty and degenerate cases too — those are the ones that crash.

`SKIP_TEST=1 ./Scripts/coverage.sh` rebuilds the report from an existing `--enable-code-coverage` profile. Use `swift build --show-bin-path` to locate the test binary; `swift test --show-bin-path` is not a flag on this toolchain.

## Live capture

`Tests/Integration` includes “a live capture on this machine is valid” and “two live captures of stable capabilities do not drift.” They are `#if os(macOS)` where needed and must not include battery or free space when asserting quiet diffs.

## Authoring pitfalls

- `#expect(condition, "\(name)")` — the comment parameter is `Comment`, not `String`. Interpolation keeps SwiftFormat from rewriting it into a comment literal you did not mean.
- `SemanticVersion("1.2")` prefers `ExpressibleByStringLiteral` (non-optional). Use a `parse(_ text: String) -> SemanticVersion?` helper when you need the failable initializer, or SwiftFormat will rewrite `SemanticVersion.init("…")` back to a string literal.
- `#expect(xs.allSatisfy(\.diff.isEmpty))` does not compile; use a closure.
- Do not assert on wall-clock `Date()` formatting in a way that depends on the developer’s locale unless the test injects a calendar/time zone (timeline daily buckets do this).

## What not to do

- Require Node, Docker, or a particular Wi-Fi network in unit tests
- Add a third-party test helper package
- Skip a failing golden fixture by editing `Fixtures/` until the diff is understood
- Put a `sleep` in a collector test to simulate a hang — `FakeCollector.Behaviour.hang` already exists
