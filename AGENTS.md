Diffuse is a **local-first device-history product**. Five native apps (macOS, iOS, iPadOS, watchOS, Android) answer one question on the device that observed it. The four Apple apps share a capability-driven Swift engine. Android is a fully native Kotlin implementation. Snapshots never leave the device. There is no account, no cloud, and no telemetry. GitHub is the only backend.

## Read this first

1. `Documentation/README.md` then `Documentation/Architecture.md`
2. `Documentation/adr/`
3. Nested `AGENTS.md` in `Packages/`, `Apps/`, `Tests/`, `Tools/` (closest file wins)

Adding a capability: `Documentation/CapabilityGuide.md` and `.agents/skills/add-capability/SKILL.md`.
Writing tests: `Documentation/Testing.md`. CLI: `Documentation/CLI.md`. Scripts/CI: `Documentation/Repository.md`.
Stack inventory: `Documentation/TechStack.md`. Build failures: `Documentation/Troubleshooting.md`. Tagging: `Documentation/Releasing.md`.

## Layout

```
Packages/     domain engine (Swift)
Apps/         four native Apple apps + widgets/complications
Android/      native Kotlin app + domain engine
Tools/        diffuse-dev CLI
Tests/        Domain, Invariants, Integration, Support
Fixtures/     golden snapshots and expected diffs
.agents/      canonical skills (copied to .claude/skills/)
ARCHITECTURE.md  repository-wide Swift + Kotlin map
```

```
Apps → DiffuseUI → DiffuseCapabilities / DiffuseCore → DiffuseModels
                                                     → DiffuseDiff
                                                     → DiffuseStorage
```

Core packages have no UIKit/AppKit imports. They type-check against iOS and watchOS via `./Scripts/crosscheck.sh`.

## Hard rules

- No third-party Swift packages.
- No signing identities, team IDs, or provisioning profiles in this repo.
- CI must stay able to produce **unsigned** artifacts.
- Do not add CodeQL, Super-Linter, Scorecard, Semgrep, Trivy, Sonar, or other noisy static scanners.
- Do not weaken a golden fixture to make a test pass.
- Swift 6, complete concurrency checking.
- One concern per change.
- Procedural workflows live in **skills**, not in this file.

## Commands

```bash
make doctor                # what can this machine build?
make help                  # every supported command
./Scripts/bootstrap.sh     # XcodeGen + tools
./Scripts/format.sh        # SwiftFormat in place
./Scripts/verify.sh        # format lint, tests, cross-check, unsigned builds
./Scripts/coverage.sh      # tests + llvm-cov HTML/lcov under coverage/
swift test --parallel
swift test --filter DiffuseDomainTests
swift run diffuse-dev --help
```

Running an app:

```bash
make ios-run / ipados-run / watch-run / mac-run   # Apple, on a resolved simulator
make android-run                                  # Android, on a device or emulator
make android-test / android-lint / android-build
make gradle ARGS="<task>"                         # any other Gradle task
```

Never call `adb`, `xcrun`, or `./gradlew` bare from a script or Make target. Use `Scripts/android.sh` and `Scripts/apple.sh`, which resolve a JDK 17, an `adb` binary, and a simulator UDID. Bare `adb` is not on `PATH` after a default Android Studio install, and Android builds must not assume a JDK — Gradle provisions its own from `Android/gradle/gradle-daemon-jvm.properties`.

On macOS, `npm install` installs Husky git hooks. Docker and the Dev Container cover docs, scripts, hooks, and the Android build — they cannot build the Apple apps, which need Xcode on macOS.

## Skills

Canonical tree: `.agents/skills/<name>/SKILL.md`. Claude Code also loads `.claude/skills/` (keep them identical). Descriptions are third-person; load a skill when its description matches the task.

| Skill | Use when |
|---|---|
| `verify` | Claiming a change is done |
| `coverage` | Measuring or publishing test coverage |
| `write-tests` | Adding or extending tests under `Tests/` or `Packages/*/Tests` |
| `review-change` | Reviewing a diff against architecture and privacy |
| `format` | Formatting Swift |
| `add-capability` | Adding something Diffuse can observe |
| `fixtures` | Regenerating golden fixtures |
| `privacy` | Classification, redaction, export, ledger |
| `diff-engine` | Comparison rules, severity, correlation |
| `storage` | Snapshot store, query, retention |
| `search` | SearchIndex / library search |
| `scheduler` | Capture cadence and system-event floor |
| `retention` | RetentionPolicy / RetentionPlanner |
| `export` | Reports, redacted export, CLI output |
| `capture-cli` | `diffuse-dev` capture/inspect/diff |
| `native-apps` | Mac / iOS / iPad / Watch UI |
| `screenshots` | Regenerating `docs/screenshots/` (Apple + Android) |
| `crosscheck` | iOS/watchOS SDK type-check |
| `debug-collector` | A collector hangs, throws, or flakes |
| `commit` | Splitting and describing a change |

## Subagents

`.claude/agents/`: `reviewer`, `test-writer`, `privacy-reviewer`, `fixture-keeper`.

## Done when

- `./Scripts/format.sh` is clean
- `swift test --parallel` is green (or `./Scripts/coverage.sh` if you touched Packages or Tests)
- Golden fixtures are unchanged, or the diff is explained
- No new third-party Swift package, signing material, or static scanner
