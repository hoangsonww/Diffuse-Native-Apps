---
name: write-tests
description: Add Swift Testing coverage in Tests/Domain, Tests/Invariants, Tests/Integration, or package-local suites. Use when adding behaviour, reproducing a bug, or the user asks for more tests.
---

# Write tests

Swift Testing only (`@Test`, `#expect`, `@Suite`). No new XCTest modules.

## Where it goes

| Kind | Path |
|---|---|
| Example-based public API | `Tests/Domain/` |
| Seeded invariant ("for any input") | `Tests/Invariants/` |
| Golden fixtures, live capture, pipelines | `Tests/Integration/` |
| Package-private details | `Packages/<Name>/Tests/` |

`DiffuseTestSupport` (`Tests/Support`) has `SnapshotBuilder`, `TestSchema`, `FakeCapabilityFactory`, `SeededGenerator`, `SnapshotSummary.stub`, `TemporaryLibrary`.

## Rules

- Prefer fakes over live hardware. Integration live-capture tests are the exception.
- Deterministic clocks (`FixedTimeSource`) and ids. No `Date()` or `UUID()` in assertions unless the test is specifically about allocation.
- If you change collector schema, run skill `fixtures` and explain the diff.
- After writing tests: `swift test --parallel` then `./Scripts/coverage.sh`.

## Shape

One behaviour per `@Test` with a sentence name ("Pinned snapshots survive the age window"). Invariants take `arguments:` of seeds and mention the seed in the failure message.
