# Tests

Guide: `Documentation/Testing.md`. Fixtures: `Fixtures/README.md`.

```
Tests/Support       DiffuseTestSupport (builders, fakes, SeededGenerator)
Tests/Domain        example-based coverage of public APIs
Tests/Invariants    seeded properties that must hold for generated input
Tests/Integration   golden fixtures, live capture, extensibility, pipelines
Packages/*/Tests    package-local suites (keep them; do not move them here)
```

- Swift Testing (`@Test`, `#expect`). No XCTest unless an Apple API requires it.
- Prefer fakes (`FakeCapabilityFactory`) over live hardware. The live-capture tests in Integration are the exception and are macOS-gated.
- Never weaken `Fixtures/` to make a test pass. Skill `fixtures`.
- New behaviour: add an example in `Tests/Domain` and, if it is an invariant, a seeded case in `Tests/Invariants`.
- Coverage: `./Scripts/coverage.sh`. Reports land in gitignored `coverage/`.
