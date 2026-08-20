---
name: export
description: Change Markdown/plain-text reports or redacted snapshot/diff export. Use when Copy as Markdown, CLI output, or GitHub-issue paste is wrong.
---

# Export

Apps and `diffuse-dev` must share `ReportRenderer` and `SnapshotService.export*`. Do not add a second template in an app target.

- Diff reports start with `# Diffuse Report` and end with a local-only footer.
- Snapshot inventories list sections and entities; empty sections print status, not a blank list.
- Markdown escaping covers `*`, `_`, `` ` ``.
- Export methods take `RedactionPolicy` (default `.standard`) and apply it to **copies**.
- Import assigns a new `SnapshotID`, sets origin `.imported`, and adds the `imported` tag.

Tests: `Tests/Domain/ReportRendererTests.swift`, export parity in `Tests/Integration/PipelineTests.swift`.
