# Diffuse

<img src="docs/app-icon.png" width="96" alt="Diffuse app icon — a seven-circle cluster on blueprint indigo" />

**See what changed.**

[![CI](https://github.com/hoangsonww/Diffuse/actions/workflows/ci.yml/badge.svg)](https://github.com/hoangsonww/Diffuse/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-2F4A8A.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg)](Package.swift)

Diffuse answers one question: *what changed on this device between these two points in time?*

It is a **local-first** Apple-platform product. Four genuinely native apps — macOS, iOS, iPadOS, watchOS — share one capability-driven domain engine. Snapshots never leave the device. There is no account, no cloud, and no telemetry. GitHub is the only backend this repository talks to.

**Site:** [hoangsonww.github.io/Diffuse](https://hoangsonww.github.io/Diffuse/)

## What it does

Take a snapshot. Use your machine. Take another. Diffuse diffs the two:

- OS version, hardware, displays, power
- Storage volumes and free space
- Network path, interfaces, and (on Mac, with Location) the Wi-Fi name
- Installed applications
- Developer tools (`node`, `python`, `git`, `docker`, `brew`, …)
- Git repositories you asked it to watch (metadata only)
- Processes, if you opt in

Every capability carries its own schema. The diff engine, the store, search, export, and the UI are generic: adding something new to observe is a typed model, a collector, a registry line, and a test. No new screens.

## What it will not do

These are product decisions, recorded as ADRs, not missing features:

- Sync Mac history to iPhone ([ADR 0008](Documentation/adr/0008-no-cloud-sync.md))
- Ship a cloud account, telemetry, or crash reporter that uploads snapshots
- Put signing identities in this repository ([ADR 0005](Documentation/adr/0005-generated-unsigned.md))
- Depend on third-party Swift packages ([ADR 0004](Documentation/adr/0004-no-third-party-deps.md))
- Infer “why” something changed — clustering is interval grouping, search is term matching

## Apps

| Platform | What it is |
| --- | --- |
| **macOS** | The full workspace. Split view, menu bar extra, scheduled capture, repository watch list, developer-tool collectors. |
| **iOS** | A phone app: overview, timeline, compare, settings. Background refresh. Home Screen and Lock Screen widgets. |
| **iPadOS** | A three-column analytical workspace (including portrait). Same collectors as iPhone, reported as iPadOS. |
| **watchOS** | Standalone. Glance UI and `Δ N` complications. No paired iPhone required. |

The four apps are not one target with size-class branches. Each is written for the device it runs on. Details: [Documentation/Apps.md](Documentation/Apps.md).

## Screenshots

![iPhone overview](docs/screenshots/ios-overview.png)

More from the running apps (18 Aug 2026): [docs/screenshots](docs/screenshots/).

## Privacy

- Snapshots live in Application Support on that device.
- Export redacts by classification: `public`, `local`, `sensitive`, `restricted`. Restricted values never leave, even on “full detail.”
- The process collector is off until you turn it on.
- Git never stores file names or contents; remotes are reduced to a host.
- Wi-Fi collection on macOS uses Location solely for the network name. Coordinates are not read.

See [Documentation/Privacy.md](Documentation/Privacy.md).

## Develop

Requires macOS, Xcode 16+ / Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat).

```bash
./Scripts/bootstrap.sh    # generates Diffuse.xcodeproj (gitignored)
./Scripts/verify.sh       # format, tests, SDK cross-check, unsigned app builds
```

A healthy checkout prints `Diffuse is healthy.`

```bash
swift test --parallel               # Swift Testing (~445 tests)
./Scripts/coverage.sh               # llvm-cov HTML + lcov in coverage/ (gitignored)
swift run diffuse-dev --help        # capture, inspect, diff, validate, fixtures, privacy
open Diffuse.xcodeproj              # generated; do not check it in
```

Git hooks (optional, Node 20+):

```bash
npm install    # Husky + lint-staged; also installed by ./Scripts/bootstrap.sh
```

Docker / Dev Container cover docs, scripts, and hooks — **not** Xcode builds:

```bash
docker compose up -d
docker compose exec dev bash
```

Signing is not part of this repository. CI produces unsigned artifacts. Whoever ships Diffuse configures identities outside source control.

## Agents

Human and agent contributors share one contract: [AGENTS.md](AGENTS.md). Skills live in [`.agents/skills/`](.agents/skills/). Claude Code, Codex, Cursor, Copilot, and Gemini each have a thin pointer (`CLAUDE.md`, `.codex/`, `.cursor/rules/`, `.github/copilot-instructions.md`, `GEMINI.md`).

## Community

- [Contributing](CONTRIBUTING.md)
- [Code of conduct](CODE_OF_CONDUCT.md)
- [Security](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)

## Architecture

```
Apps → DiffuseUI → DiffuseCapabilities / DiffuseCore → DiffuseModels
                                                     → DiffuseDiff
                                                     → DiffuseStorage
```

Collectors register per platform. Core packages have no UIKit/AppKit imports and type-check against the iOS and watchOS SDKs (`Scripts/crosscheck.sh`).

Start at **[Documentation/](Documentation/README.md)** — architecture, glossary, capability/collector guides, schema, diff, storage, privacy, apps, CLI, testing, repository layout, and ADRs.

| I want to… | Read |
| --- | --- |
| Understand the layers | [Architecture](Documentation/Architecture.md) |
| Add something Diffuse can observe | [Capability guide](Documentation/CapabilityGuide.md) |
| Debug a collector | [Collector guide](Documentation/CollectorGuide.md) |
| Change JSON shape or fixtures | [Snapshot schema](Documentation/SnapshotSchema.md) |
| Understand comparison | [Diff engine](Documentation/DiffEngine.md) |
| Find files on disk / retention | [Storage](Documentation/Storage.md) |
| Know what is collected | [Privacy](Documentation/Privacy.md) |
| Work on Mac / iPhone / iPad / Watch | [Apps](Documentation/Apps.md) |
| Use `diffuse-dev` | [CLI](Documentation/CLI.md) |
| Write tests or read coverage | [Testing](Documentation/Testing.md) |
| Find a script or CI job | [Repository](Documentation/Repository.md) |
| Decode a term | [Glossary](Documentation/Glossary.md) |

## License

MIT. See [LICENSE](LICENSE).
