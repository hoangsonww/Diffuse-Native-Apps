# Fixtures

Golden snapshots and expected diffs. They are the integration contract for the travelling schema and the diff engine: two runs of the same pair must produce byte-identical `DiffResult`s.

Generated from `FixtureGenerator` / `SampleData` — no `Date()`, no `UUID()`, no environment lookups. Do not hand-edit JSON to hide a behavioural change.

```bash
./Scripts/generate-fixtures.sh
swift test --parallel --filter DiffuseIntegrationTests
```

Review the git diff. If an expected diff moved, say **why** in the commit. Never weaken a golden file to make a test pass. If the engine is wrong, fix the engine.

| File | Role |
| --- | --- |
| `snapshots/mac-baseline.json` | Quiet Mac morning |
| `snapshots/mac-after-workday.json` | Same machine after a day of tool/network/repo drift |
| `snapshots/mac-permission-problem.json` | A collector in `.permissionRequired` (status change, not data loss) |
| `snapshots/ios-baseline.json` / `ios-afternoon.json` | Phone pair |
| `diffs/*.expected.json` | `DiffEngine` output for those pairs |

Full rules: [Documentation/Testing.md](../Documentation/Testing.md) and [Documentation/SnapshotSchema.md](../Documentation/SnapshotSchema.md). Skill: `fixtures`.
