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
- **New server-driven node type: add it to `SurfaceSDUITests` and `SurfaceRenderingTests`.** A payload is untrusted input; the cases that matter are the wrong ones. Never weaken the fallback rule to make a test pass — a surface that can blank a screen is the one thing this design exists to prevent.
- **New public SwiftUI view: add it to `Tests/Domain/ViewRenderingTests.swift`.** It renders every view in `DiffuseUI` through `ImageRenderer`, which evaluates the whole body — that is the only thing standing between a view that traps on a nil optional or an empty collection and all four Apple clients crashing at once. Render the degenerate cases too, not just the happy one.
- Coverage: `./Scripts/coverage.sh`. Reports land in gitignored `coverage/`. **It fails below 90%** (currently 92.4%); `DIFFUSE_MINIMUM_COVERAGE` raises the floor, never lower it to make a run pass.
