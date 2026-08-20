# Changelog

All notable changes to Diffuse are documented here.

## Unreleased

### Engine

- Export redaction always walks properties, so a `restricted` field on a
  `local` section is stripped even under `RedactionPolicy.none`.

### Repository

- GitHub issue and pull-request templates, CODEOWNERS, Dependabot for Actions
  and git-hook npm packages.
- CI: concurrency, least-privilege permissions, Swift PM cache, timeouts, a
  ShellCheck job, and a single "All green" required check. No CodeQL or other
  static scanners.
- Agent harness: lean root `AGENTS.md` plus nested files under Packages/Apps/Tests/Tools;
  twenty-one skills in `.agents/skills/` (mirrored to `.claude/skills/`); Cursor glob
  rules; reviewer / test-writer / privacy-reviewer / fixture-keeper subagents; Stop
  hook reminding agents to run tests.
- Tests: `Tests/Domain` and `Tests/Invariants` targets, expanded Integration pipelines,
  first-party `./Scripts/coverage.sh` (llvm-cov HTML/lcov) published as a CI artifact.
- Documentation: index at `Documentation/README.md`; expanded architecture, guides,
  privacy, storage, diff, schema, ADRs (with alternatives); new Apps, CLI, Testing,
  Glossary, and Repository pages; ADR template; Fixtures README.
- Marketing site at the repository root (`index.html`) with screenshots, motion,
  JSON-LD, sitemap, robots.txt, llms.txt, and GitHub Pages deploy.

## 1.0.0 — 2026-08-17

First release.

### Apps

- **macOS** — NavigationSplitView workspace, menu bar extra, scheduled capture
  on a timer and on wake, repository watch list, developer-tool collectors.
- **iOS** — Tab + NavigationStack phone app, background app refresh, home-screen
  and Lock Screen widgets.
- **iPadOS** — Three-column analytical workspace, widgets.
- **watchOS** — Standalone watch app and `Δ N` complications. No paired iPhone
  required.

### Engine

- Capability-driven snapshots: typed collectors, travelling schema, generic UI.
- Schema-driven diff with identity matching, severity, and change correlation.
- On-device JSON snapshot store with rebuildable index, retention, and
  validation.
- `diffuse-dev` CLI for capture, inspect, diff, validate, fixtures, and
  privacy.

### Privacy

- Local-first. No account, no cloud, no telemetry.
- Classification-driven redaction on export (`public` / `local` / `sensitive` /
  `restricted`).
- Process listing opt-in. Git metadata only. Wi-Fi names require Location on
  macOS and never include coordinates.
