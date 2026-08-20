---
name: capture-cli
description: Change or debug the diffuse-dev CLI (capture, inspect, diff, validate, fixtures, privacy). Use when adding a command or the CLI disagrees with the apps.
---

# capture-cli

```bash
swift run diffuse-dev --help
```

The CLI is a thin client of `SnapshotService`, `ReportRenderer`, `SnapshotValidator`, and `PrivacyLedger`. If a command needs new behaviour, add it to the domain package first, then expose it.

- Do not parse snapshot JSON by hand in a command.
- `--now` / injected `FixedTimeSource` keep fixtures reproducible.
- Validate uses `SnapshotValidator`; do not duplicate rules.
- Exit non-zero on validation problems.

Source: `Tools/diffuse-dev/Sources/diffuse-dev`. Nested `Tools/AGENTS.md`.
