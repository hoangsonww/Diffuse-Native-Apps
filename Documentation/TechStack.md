# Technology stack

Every technology this repository actually uses, why it is here, and where it appears. The badge row at the top of the [README](../README.md) is generated from this list, so the two stay in step.

Two rules shape almost every entry below:

- **No third-party Swift packages** ([ADR 0004](adr/0004-no-third-party-deps.md)). Everything the Apple apps link is either first-party or an Apple SDK framework.
- **No cloud, no account, no telemetry** ([ADR 0001](adr/0001-local-first.md), [ADR 0008](adr/0008-no-cloud-sync.md)). Nothing in this list is a hosted runtime service. GitHub hosts source and CI artifacts; it is not a backend.

Android is the one place with an external dependency graph, and it is limited to Google's own AndroidX and JetBrains' Kotlin libraries ([ADR 0009](adr/0009-native-android.md)).

## At a glance

| Layer | Apple family | Android family |
| --- | --- | --- |
| Language | Swift 6, language mode `.v6`, complete concurrency | Kotlin 2.0.21, JVM target 17 |
| UI | SwiftUI (+ AppKit / UIKit / WatchKit hosts) | Jetpack Compose, Material 3 |
| Build | Swift Package Manager + XcodeGen + `xcodebuild` | Gradle 8.13, Android Gradle Plugin 8.10.1 |
| Serialization | `Codable` / `JSONEncoder` (first-party `SnapshotCoding`) | `kotlinx.serialization` JSON |
| Concurrency | Swift structured concurrency, actors, `TaskGroup` | Kotlin coroutines, `Flow`, `StateFlow` |
| Scheduling | `Timer`, `BGAppRefreshTask`, `WKApplicationRefreshBackgroundTask` | `WorkManager` periodic work |
| Tests | Swift Testing (`@Test`, `#expect`, `@Suite`) | JUnit 4 + coroutines-test; Compose/Espresso instrumentation |
| Coverage | `llvm-cov` via `Scripts/coverage.sh`, 90% package floor (92.4%) | JaCoCo 0.8.12, 90% domain floor (97.7%) |
| Shrinking | `DEAD_CODE_STRIPPING`, whole-module release builds | R8 + ProGuard rules |

## Languages

| Technology | Version | Where | Why |
| --- | --- | --- | --- |
| **Swift** | 6.0, `swiftLanguageModes: [.v6]` | `Packages/`, `Apps/`, `Tools/`, `Tests/` | The domain engine and four Apple apps. Complete concurrency checking is on; `ExistentialAny` is an enabled upcoming feature. |
| **Kotlin** | 2.0.21 | `Android/app/src/` | The Android app and its independent domain engine. |
| **Java** | 17 (source, target, and `jvmTarget`) | `Android/app/build.gradle.kts` | The JVM level Android compiles Kotlin against and the level CI installs (Temurin 17). |
| **Python** | 3 + Pillow | `Scripts/generate-icons.py` | Renders the app-icon masters under `Design/Icons/`. Not a build dependency of any app. |
| **Bash** | POSIX-ish, `set -euo pipefail` | `Scripts/*.sh`, `Scripts/hooks/`, `.claude/hooks/` | Bootstrap, format, verify, coverage, cross-check, fixtures. Linted by ShellCheck in CI. |
| **JavaScript** | ES2020, no framework, no bundler | `web/site.js` | ~90 lines driving the marketing site's nav, lightbox, and reveal-on-scroll. |

## Apple platform

### Frameworks the apps link

| Framework | Used for |
| --- | --- |
| **SwiftUI** | Every screen on all four Apple apps. `DiffuseUI` holds the generic rows, timeline, search, privacy, and preference surfaces. |
| **Foundation** | Dates, `Codable`, `FileManager`, `URL`, `Measurement`, `Locale`. The only import in the pure domain packages. |
| **Observation** | `@Observable` view models. No Combine, no `ObservableObject`. |
| **AppKit** | The macOS window, menu-bar extra, and `NSWorkspace` application inventory. |
| **UIKit** | iOS/iPadOS device metrics and screen properties behind the SwiftUI layer. |
| **WatchKit** | watchOS device identity, battery, and the standalone-app lifecycle. |
| **WidgetKit** | Home Screen / Lock Screen widgets and `Δ N` watch complications. |
| **BackgroundTasks** | `BGAppRefreshTask` on iOS/iPadOS; the watch uses `WKApplicationRefreshBackgroundTask`. |
| **Network** | `NWPathMonitor` for the network-path capability (interface type, constrained, expensive). |
| **Core Location** | macOS only, solely to unlock the Wi-Fi network name. Coordinates are never read. |
| **Core WLAN** | The Wi-Fi SSID, channel, and band on macOS. |
| **IOKit** (`IOKit.ps`) | macOS power source: charge, charging state, and time remaining. |
| **Core Graphics** | Display enumeration, resolution, and scale on macOS. |
| **UniformTypeIdentifiers** | Type identifiers for snapshot import/export in the file exporter. |

Core packages import **no** UIKit or AppKit. `Scripts/crosscheck.sh` type-checks them against the iOS and watchOS SDKs so a Mac-only API cannot leak into shared code.

### Apple tooling

| Tool | Version | Role |
| --- | --- | --- |
| **Xcode** | 16+ | Builds the app targets. `xcodeVersion: "1600"` in `project.yml`. |
| **Swift Package Manager** | Swift tools 6.0 | Declares 8 libraries, 1 executable, 12 test targets, and **zero** external dependencies. |
| **XcodeGen** | latest via Homebrew | `project.yml` → `Diffuse.xcodeproj`. The project file is generated and gitignored ([ADR 0005](adr/0005-generated-unsigned.md)). |
| **Swift Testing** | bundled | `@Test`, `#expect`, `@Suite`, parameterized cases. No new XCTest modules. |
| **SwiftFormat** | via Homebrew, `.swiftformat` | `./Scripts/format.sh` in place; `--lint` in CI and in the pre-commit hook. |
| **llvm-cov** | bundled with the toolchain | `./Scripts/coverage.sh` emits HTML, lcov, and a Markdown summary into the gitignored `coverage/`, and fails below a 90% package line floor (currently 92.4%, `DIFFUSE_MINIMUM_COVERAGE` to raise). First-party coverage; no Codecov. |
| **Homebrew** | — | Installs `xcodegen` and `swiftformat` in `Scripts/bootstrap.sh` and in CI. |

Deployment targets: macOS 14, iOS 17, iPadOS 17, watchOS 10. `Package.swift` additionally declares tvOS 17 and visionOS 1 so the shared packages keep compiling for them, but no app target ships on those platforms.

## Android

| Technology | Version | Role |
| --- | --- | --- |
| **Android Gradle Plugin** | 8.10.1 | `compileSdk` / `targetSdk` 36, `minSdk` 26. |
| **Gradle** | 8.13 wrapper, Kotlin DSL | `Android/build.gradle.kts`, `Android/app/build.gradle.kts`. `FAIL_ON_PROJECT_REPOS` keeps repository declarations centralized. |
| **Jetpack Compose** | BOM `2024.12.01` | The whole UI. Adaptive: bottom bar under 720dp, navigation rail at and above it. |
| **Material 3** | via the Compose BOM | `material3` plus `material-icons-extended`. Dynamic-capable theme in `ui/Theme.kt`. |
| **AndroidX Activity Compose** | 1.13.0 | `ComponentActivity`, `setContent`, edge-to-edge, and the file-picker activity results. |
| **AndroidX Lifecycle** | 2.10.0 | `AndroidViewModel`, `viewmodel-compose`, `lifecycle-runtime-compose` for `collectAsStateWithLifecycle`. |
| **WorkManager** | 2.11.2 | `SnapshotWorker` periodic capture. The app-open path independently checks whether a capture is due. |
| **Kotlin coroutines** | 1.9.0 | `CoroutineWorker`, `supervisorScope` collector fan-out with deadlines, `Mutex`-guarded store writes, `StateFlow` UI state. |
| **kotlinx.serialization** | 1.7.3 | Schema-v1 JSON encode/decode, including custom serializers for the property-value union. |
| **Android Studio** | current stable | The supported IDE. Not required — the Gradle CLI is the source of truth. |
| **Android Lint** | via AGP | `./gradlew lintDebug`, enforced in the Android workflow. |
| **R8 + ProGuard** | via AGP | `isMinifyEnabled = true` on release, rules in `app/proguard-rules.pro`. |

### Android testing

| Technology | Version | Role |
| --- | --- | --- |
| **JUnit** | 4.13.2 | The JVM domain suite under `Android/app/src/test/`. |
| **kotlinx-coroutines-test** | 1.9.0 | Deterministic scheduling for coordinator and worker tests. |
| **AndroidX Test / JUnit ext** | 1.3.0 | Instrumented tests under `Android/app/src/androidTest/`. |
| **Espresso** | 3.7.0 | Device-level assertions alongside the Compose harness. |
| **Compose UI Test** | via the BOM | `ui-test-junit4` for navigation, dialogs, rotation, and adaptive-layout tests. |
| **JaCoCo** | 0.8.12 | `jacocoDebugUnitTestReport` + a `jacocoDebugUnitTestCoverageVerification` rule that fails under 90% line coverage for `com.diffuse.android.domain`. |

The JVM suite points `diffuse.fixtures` at the repository's root `Fixtures/` directory, so Kotlin decodes the exact JSON that Swift produced.

## Data formats

| Format | Where |
| --- | --- |
| **JSON** | Snapshot schema v1, `index.json`, golden fixtures, `--json` CLI output, JSON-LD on the landing page. |
| **XML** | Android manifest, resources, vector drawables, backup and data-extraction rules, JaCoCo reports, `sitemap.xml`. |
| **YAML** | `project.yml` (XcodeGen), GitHub Actions workflows, issue-form templates, Dependabot, pre-commit, `CITATION.cff`. |
| **Markdown** | All documentation, ADRs, agent skills, and the `ReportRenderer` export format. |
| **Mermaid** | Every diagram in this repository is Mermaid inside Markdown. There are no binary diagram assets to drift. |
| **SVG** | `Design/Icons/AppIcon.svg` is the icon master; Android vector drawables are SVG-derived. |

## Marketing site

Static, dependency-free, deployed from `main` by `.github/workflows/pages.yml`.

| Technology | Role |
| --- | --- |
| **HTML5** | `index.html` and `404.html`. Semantic sections, Open Graph and Twitter cards, and a `schema.org` JSON-LD block. |
| **CSS3** | `web/site.css`. Custom properties, `light-dark()`-style theming, container-aware layout, `prefers-reduced-motion` guards. |
| **JavaScript** | `web/site.js`. No framework, no bundler, no analytics. |
| **Web App Manifest** | `site.webmanifest` — installable, standalone, themed. |
| **Google Fonts** | Bricolage Grotesque, Fraunces, IBM Plex Mono, preconnected and `display=swap`. |
| **Playwright** | Local-only QA of the landing page. Its output (`.playwright-mcp/`, root `landing-*.png`) is gitignored. |

Machine-readable siblings: `robots.txt`, `sitemap.xml`, `llms.txt`, `humans.txt`, `.well-known/security.txt`.

## Repository, build, and CI

| Technology | Role |
| --- | --- |
| **Git** | `.gitattributes` normalizes line endings, marks binaries, and keeps GitHub's language bar honest. |
| **GitHub** | Source, issues, PRs, releases, and private security advisories. Also the only "backend" this product touches. |
| **GitHub Actions** | Five workflows: `ci.yml` (format, tests + coverage, iOS/watchOS cross-check, four unsigned app builds, ShellCheck, one required "All green" gate), `android.yml`, `pages.yml`, `release-apple.yml`, `release-macos.yml`. |
| **GitHub Pages** | Deploys `index.html`, `web/`, and the machine-readable files. The Swift tree is not published. |
| **Dependabot** | Watches GitHub Actions and the Husky npm tree only. There are no Swift packages to watch. |
| **GNU Make** | `Makefile` wraps the scripts: `bootstrap`, `format`, `test`, `coverage`, `verify`, `hooks`, `docker-*`. |
| **Docker + Compose** | `node:22-bookworm-slim` toolbox for docs, scripts, and hooks on Linux. It **cannot** build Apple targets. |
| **Dev Containers** | `.devcontainer/devcontainer.json` points at the same Compose service for Codespaces. |
| **Node.js** | 22 (`.nvmrc`), engines `>=20`. Present only so Husky can run. |
| **npm** | Installs two dev dependencies. `npm ci --ignore-scripts` in the image. |
| **Husky** | Git hooks in `.husky/`, installed by `npm install` and offered by `Scripts/bootstrap.sh`. |
| **lint-staged** | Runs `swiftformat` over staged `*.swift` files. |
| **pre-commit** | `.pre-commit-config.yaml` delegates to `Scripts/hooks/pre-commit.sh` for people who prefer that runner over Husky. |
| **ShellCheck** | `shellcheck -x` over `Scripts/*.sh`, `Scripts/hooks/*.sh`, `.claude/hooks/*.sh` in CI. |
| **EditorConfig** | `.editorconfig` — LF, UTF-8, final newline, 4 spaces (2 for YAML/JSON/Markdown, tabs in the Makefile). |

**Deliberately absent:** CodeQL, Super-Linter, Scorecard, Semgrep, Trivy, Sonar, Codecov, and any other scanner that reports on code it did not have to understand. This is a stated constraint in [AGENTS.md](../AGENTS.md), not an oversight.

## Agent harness

Coding agents are first-class contributors here, so their configuration is part of the stack.

| Technology | Role |
| --- | --- |
| **AGENTS.md** | The single contract every agent and human reads first. Nested files under `Packages/`, `Apps/`, `Tests/`, `Tools/`, `Android/`; closest file wins. |
| **Agent Skills** | 21 procedural workflows in `.agents/skills/`, mirrored byte-for-byte to `.claude/skills/`. |
| **Claude Code** | `CLAUDE.md`, `.claude/agents/` (reviewer, test-writer, privacy-reviewer, fixture-keeper), and `.claude/hooks/` that format Swift after edits and block signing material. |
| **GitHub Copilot** | `.github/copilot-instructions.md`. |
| **Cursor** | `.cursor/rules/` glob-scoped rules. |
| **Gemini** | `GEMINI.md`. |
| **Codex** | `.codex/`. |
| **Aider** | `.aider.conf.yml`. |
| **Model Context Protocol** | The interface agents use to reach repository tooling. |

## What this stack is not

- No third-party Swift package, at any layer, for any reason ([ADR 0004](adr/0004-no-third-party-deps.md)).
- No cross-platform UI toolkit. Android does not wrap, embed, or invoke the Apple apps ([ADR 0009](adr/0009-native-android.md)).
- No database engine. The store is one pretty-printed JSON file per snapshot plus a rebuildable `index.json` ([Storage](Storage.md)).
- No networking client, HTTP stack, or socket in any app. Android does not even declare `INTERNET`.
- No analytics, crash reporter, advertising identifier, or attribution SDK.
- No signing identity, provisioning profile, team ID, or keystore in this repository ([ADR 0005](adr/0005-generated-unsigned.md)).

## Keeping this page true

When you add a technology:

1. Add the row here, in the table it belongs to.
2. Add the badge to the README block. Use the [Simple Icons](https://simpleicons.org) slug for `logo=` and the brand hex for the background, `style=flat-square`, `logoColor=white`.
3. If it is a runtime dependency of the Android app, it also belongs in `Android/app/build.gradle.kts` and in [Android/README.md](../Android/README.md).
4. If it is a Swift dependency, stop — [ADR 0004](adr/0004-no-third-party-deps.md) says no. Write it first-party or write an ADR that supersedes 0004.
