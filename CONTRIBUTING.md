# Contributing to Diffuse

Thank you for wanting to make Diffuse better. The product is small on purpose: every change should still answer *“what changed on this device between these two points in time?”*

If it does not help ask that question more clearly, more often, or more privately, it probably does not belong here.

## Before you write code

1. Read [Documentation/README.md](Documentation/README.md), then [Architecture](Documentation/Architecture.md), the [Glossary](Documentation/Glossary.md), and [adr/](Documentation/adr/).
2. If you are adding something Diffuse can observe, read the [capability](Documentation/CapabilityGuide.md) and [collector](Documentation/CollectorGuide.md) guides. Adding a capability should **not** require edits to the diff engine, storage, search, export, or app screens.
3. Scripts, CI, Docker, and hooks: [Documentation/Repository.md](Documentation/Repository.md). Tests: [Documentation/Testing.md](Documentation/Testing.md).
4. If you are using an agent, start at [AGENTS.md](AGENTS.md) and the skills in `.agents/skills/`.

## Development setup

```bash
./Scripts/bootstrap.sh
./Scripts/verify.sh
```

`bootstrap.sh` generates `Diffuse.xcodeproj` from `project.yml` and resolves Swift packages. The project file is not checked in.

Requirements:

- macOS 14+
- Xcode 16+ / Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
- Node 20+ if you want Husky git hooks (`npm install`)

Docker and the Dev Container (`.devcontainer/`) are optional. They give Linux and Codespaces a shell for docs and scripts. They **cannot** run `swift test` or build the apps — that needs macOS and Xcode.

```bash
docker compose up -d          # toolbox container
docker compose exec dev bash
# or open the folder in VS Code / Cursor with Dev Containers
```

## Layout

```
Packages/     domain engine (no app, no Apple-platform coupling in core)
Apps/         four native apps + widgets/complications
Tools/        diffuse-dev CLI
Tests/        Domain, Invariants, Integration, Support
Fixtures/     golden snapshots and expected diffs
Documentation/
Scripts/
.agents/      canonical agent skills (mirrored to .claude/skills/)
```

Dependency direction is strict:

```
Apps → DiffuseUI → DiffuseCapabilities / DiffuseCore → DiffuseModels
                                                     → DiffuseDiff
                                                     → DiffuseStorage
```

Collectors live in `DiffuseCollectors` and register with a platform registry. Core packages must compile for iOS and watchOS (`Scripts/crosscheck.sh`).

## Scripts (short list)

Full table: [Documentation/Repository.md](Documentation/Repository.md).

| Command | Purpose |
| --- | --- |
| `./Scripts/bootstrap.sh` | XcodeGen + tools |
| `./Scripts/format.sh` | SwiftFormat in place |
| `swift test --parallel` | Swift Testing (~445 tests) |
| `./Scripts/coverage.sh` | llvm-cov HTML/lcov in `coverage/` |
| `./Scripts/verify.sh` | Format, tests, SDK cross-check, unsigned app builds |
| `./Scripts/generate-fixtures.sh` | Rewrite golden `Fixtures/` (review the diff) |
| `make test` / `make coverage` / `make verify` | Same commands via Makefile |

## Tests

Full guide: [Documentation/Testing.md](Documentation/Testing.md).

```bash
swift test --parallel
./Scripts/coverage.sh            # llvm-cov HTML + lcov in coverage/ (gitignored)
./Scripts/generate-fixtures.sh   # after schema or fixture-generator changes
```

| Suite | Path |
| --- | --- |
| Example-based public API | `Tests/Domain` |
| Seeded invariants | `Tests/Invariants` |
| Golden fixtures, live capture, extensibility | `Tests/Integration` |
| Package-local | `Packages/*/Tests` |

Prefer fakes (`FakeCapabilityFactory`, `FakeProcessRunner`, `FixedTimeSource`) over live hardware. Do not weaken a golden fixture to make a test pass. If the expected diff changed, say why in the commit. Coverage reports are first-party (`llvm-cov`); do not add Codecov or other coverage SaaS.

## Style

Run `./Scripts/format.sh` before opening a PR. Swift 6, complete concurrency checking, no third-party Swift dependencies. One concern per change.

Git hooks, once `npm install` has been run:

- **pre-commit** — SwiftFormat on staged `.swift` files; refuse key material
- **commit-msg** — non-empty subject, ≤ 120 characters
- **pre-push** — SwiftFormat `--lint`

Alternatively: `pre-commit install` if you use the Python [pre-commit](https://pre-commit.com) framework (`.pre-commit-config.yaml`).

## Pull requests

- One concern per PR.
- Include tests for new collectors (a fake is enough; do not require live hardware).
- Do not add signing identities, team IDs, or provisioning profiles.
- CI must stay able to produce unsigned build artifacts.
- Do not add CodeQL, Super-Linter, Scorecard, Semgrep, Trivy, Sonar, or other noisy static scanners.
- Link the ADR or guide you followed when the change is architectural.

Suggested check:

```bash
./Scripts/format.sh
swift test --parallel
# if you touched Packages/ or Tests/:
./Scripts/coverage.sh
```

## Agents

Claude Code, Codex, Cursor, Copilot, and Gemini: start at [AGENTS.md](AGENTS.md). Canonical skills: `.agents/skills/` (copied to `.claude/skills/` for Claude Code). Nested `AGENTS.md` files in `Packages/`, `Apps/`, `Tests/`, and `Tools/` win when you are in that tree.
