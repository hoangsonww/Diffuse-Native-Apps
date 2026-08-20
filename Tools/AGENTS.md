# Tools

`diffuse-dev` is the CLI over the same domain engine the apps use. Guide: `Documentation/CLI.md`. No parallel implementation of diff, storage, or export.

```
swift run diffuse-dev --help
swift run diffuse-dev snapshot /tmp/now.json
```

- Capture, inspect, diff, validate, fixtures, and privacy commands must call `SnapshotCoding` / `DiffEngine` / `ReportRenderer` / `PrivacyLedger` / `SnapshotValidator`, not reimplement them.
- The CLI writes files you name; it does not open the app’s Application Support library by default.
- Skill `capture-cli`.
