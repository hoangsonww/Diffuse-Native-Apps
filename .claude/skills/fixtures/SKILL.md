---
name: fixtures
description: Regenerate golden snapshot and expected-diff fixtures after a collector schema or fixture-generator change. Use when integration tests fail on Fixtures/ or after changing snapshot encoding.
---

# Golden fixtures

`Fixtures/` is the contract `Tests/Integration` asserts against.

```bash
./Scripts/generate-fixtures.sh
```

Then **read the resulting diff**. Do not commit a fixture change you cannot explain. Do not weaken an expected diff to make a test pass.

```bash
swift test --parallel --filter DiffuseIntegrationTests
```

`FixtureGenerator` and `SampleData` must stay deterministic: no `Date()`, no `UUID()`, no environment lookups.
