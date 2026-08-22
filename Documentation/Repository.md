# Repository

How this checkout is laid out, how you build it, and what CI actually runs. Product behaviour lives in the other guides; this page is the map of the tree.

If you are new, start at [README.md](README.md) (public face) and [Architecture.md](Architecture.md) (engine). This page is for “where is the script / workflow / hook?”

## Layout

```
Packages/          Domain engine (Swift PM). No AppKit/UIKit in core.
Apps/              Four native Apple apps + widgets / complications
Android/           Native Kotlin app, domain engine, collectors, tests, screenshots
Tools/             diffuse-dev CLI
Tests/             Domain, Invariants, Integration, Support
Fixtures/          Golden snapshots and expected diffs
Documentation/     Product and engineering record (this folder)
Scripts/           Bootstrap, format, verify, coverage, fixtures, icons, cross-check
Design/Icons/      1024px masters and Icon Composer source
docs/screenshots/  README marketing shots from the live apps
.agents/           Canonical agent skills (copied to .claude/skills/)
.github/           CI, issue/PR templates, CODEOWNERS, Dependabot
```

`Diffuse.xcodeproj` is **generated** (`./Scripts/bootstrap.sh` / XcodeGen from `project.yml`) and gitignored. Do not check it in. [ADR 0005](adr/0005-generated-unsigned.md).

Swift package graph is first-party only. [ADR 0004](adr/0004-no-third-party-deps.md). Node exists solely so Husky can run git hooks (`package.json`). Docker / Dev Container cover docs, scripts, hooks, and the **Android** build — but not `swift test` or the Apple apps, which need Xcode on macOS. Verify the image with `make verify-devcontainer`.

## Scripts

Run from the repository root. All need macOS + Xcode except where noted.

| Script | What it does |
| --- | --- |
| `./Scripts/bootstrap.sh` | Install/check tools, `xcodegen generate`, resolve packages. Optional `npm install` for hooks. |
| `./Scripts/format.sh` | SwiftFormat in place (`Packages Apps Tools Tests`). |
| `./Scripts/verify.sh` | Format lint, `swift test`, iOS/watchOS cross-check, unsigned builds of all four Apple apps. Prints `Diffuse is healthy.` |
| `./Scripts/coverage.sh` | `swift test --enable-code-coverage` then `llvm-cov` → gitignored `coverage/` (HTML, lcov, summaries). `SKIP_TEST=1` rebuilds from an existing profile. |
| `./Scripts/crosscheck.sh ios` / `watchos` | Type-check shared packages against that SDK. |
| `./Scripts/generate-fixtures.sh` | Writes `Fixtures/` from `FixtureGenerator`. Review the git diff. |
| `./Scripts/generate-icons.py` | Regenerates `Design/Icons/` masters (Pillow). |
| `./Scripts/doctor.sh` | Reports which parts of Diffuse this machine can build. Runs anywhere. |
| `./Scripts/apple.sh <build\|run\|boot\|devices> <ios\|ipados\|watch\|mac>` | Builds, installs, and launches an Apple app on a resolved simulator. No Xcode UI, no UDID. |
| `./Scripts/android.sh <task…\|run\|devices>` | Gradle for the Android app with a guaranteed JDK and a resolved `adb`. Runs anywhere. |
| `./Scripts/verify-devcontainer.sh [--build]` | Builds the toolbox image and asserts its toolchain works. Runs anywhere with Docker. |
| `./Scripts/lib.sh` | Shared helpers (JDK, `adb`, and simulator resolution). Sourced, not executed. |

Run `make help` for the full command list. `make doctor` is the right first command on a new machine — it reports whether the Apple apps, the Android app, or only the docs surface are available before a suite fails halfway through.

### No JDK setup for Android

`Android/gradle/gradle-daemon-jvm.properties` pins daemon JVM criteria, so Gradle 8.13 downloads and runs on its own Adoptium JDK 17 matching the host OS and architecture. `./gradlew` therefore works on a clean checkout whatever `java` happens to be on `PATH` — including no JDK at all. The first build pays a one-time ~180 MB download into `~/.gradle/jdks/`.

`Scripts/android.sh` additionally prefers a local JDK 17 when one exists, and resolves `adb` from `ANDROID_HOME` because `platform-tools` is not on `PATH` after a default Android Studio install.

## Local loop

```bash
make doctor                    # what can this machine build?
./Scripts/bootstrap.sh
./Scripts/format.sh
swift test --parallel
./Scripts/coverage.sh          # if you touched Packages/ or Tests/
./Scripts/verify.sh            # before you call a change done
swift run diffuse-dev --help
open Diffuse.xcodeproj         # generated; gitignored
```

Running an app, one command each — no Xcode UI, no simulator UDID, no JDK setup:

```bash
make ios-run        # DiffuseiOS on an iPhone simulator
make ipados-run     # DiffuseiPadOS on an iPad simulator
make watch-run      # DiffuseWatch on a watch simulator
make mac-run        # DiffuseMac on this machine
make android-run    # the Android app on a device or emulator
```

Git hooks (optional, Node 20+):

```bash
npm install    # Husky + lint-staged; also offered by bootstrap
```

- **pre-commit** — SwiftFormat on staged `.swift`; refuse key material
- **commit-msg** — non-empty subject, ≤ 120 characters
- **pre-push** — SwiftFormat `--lint`

`.pre-commit-config.yaml` is the Python [pre-commit](https://pre-commit.com) equivalent if you prefer that framework.

## CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) on `pull_request` and `push` to `main`/`master`. Hermetic and **unsigned**. Least-privilege `contents: read`. Concurrency cancels in-progress runs on the same PR.

| Job | Runner | Does |
| --- | --- | --- |
| Format | macos-15 | SwiftFormat `--lint` |
| Package tests | macos-15 | `./Scripts/coverage.sh`; appends `coverage/summary.md` to the job summary; uploads `coverage-report` artifact (14 days) |
| SDK cross-check | macos-15 matrix | `ios`, `watchos` |
| Build | macos-15 matrix | Unsigned Release of DiffuseMac / DiffuseiOS / DiffuseiPadOS / DiffuseWatch |
| Scripts | ubuntu-latest | ShellCheck on `Scripts/*.sh`, hook scripts |
| **All green** | ubuntu-latest | Required check: every job above succeeded |

Android runs in [`.github/workflows/android.yml`](../.github/workflows/android.yml): JVM tests, JaCoCo domain coverage verification, Android Lint, Compose/device instrumentation, and unsigned debug/release builds. It is intentionally separate from the Xcode matrix.

**Do not add** CodeQL, Super-Linter, Scorecard, Semgrep, Trivy, Sonar, Codecov, or other noisy scanners. Coverage is first-party `llvm-cov`. Dependabot watches GitHub Actions and the Husky npm tree — not Swift packages.

Full release procedure, version bumping, and what is deliberately not automated: [Releasing.md](Releasing.md).

Release workflows (tag `v*`):

- `release-macos.yml` — unsigned Mac app zip
- `release-apple.yml` — unsigned iOS / iPadOS / watchOS `.app` zips

These are build artifacts, not App Store packages. Signing and notarization happen **outside** this repository.

The marketing site (`index.html`, `web/`, `robots.txt`, `sitemap.xml`, `llms.txt`) deploys via `.github/workflows/pages.yml` to GitHub Pages. In the repository settings, set Pages source to **GitHub Actions**. Public URL: `https://hoangsonww.github.io/Diffuse/`.

## Docker and Dev Container

```bash
docker compose up -d
docker compose exec dev bash
```

Or open the folder with the Dev Container (`.devcontainer/`). It covers docs, ShellCheck, hooks, and the full Android build — the image carries a Temurin JDK 17 and Android SDK 36. It cannot compile Swift tests or the Apple apps, because Xcode is macOS-only and its licence forbids redistribution.

The image is pinned to `linux/amd64`: Google ships the Android command-line tools and build-tools for Linux as x86_64 binaries only, so an arm64 image cannot run `aapt2` or `d8`. On Apple silicon it runs under emulation and is noticeably slower.

```bash
make verify-devcontainer                    # build the image and assert its toolchain works
./Scripts/verify-devcontainer.sh --build    # also build the Android app inside it
```

The `--build` form works on an isolated `git archive` copy rather than the working tree, because a container build and a host build sharing `Android/app/build/` produce confusing failures that look like real defects.

## Agents

Human and agent contributors share [AGENTS.md](../AGENTS.md). Canonical skills: [`.agents/skills/`](../.agents/skills/). Keep `.claude/skills/` identical (`cp -R`). Nested `AGENTS.md` in `Packages/`, `Apps/`, `Tests/`, `Tools/` wins in that tree.

Cursor glob rules live in `.cursor/rules/`. Copilot, Gemini, and Codex each have a thin pointer at the root.

## Related

- [CONTRIBUTING.md](../CONTRIBUTING.md) — setup and PR rules
- [Testing.md](Testing.md) — where a test belongs
- [Apps.md](Apps.md) — signing and widgets
- [CLI.md](CLI.md) — `diffuse-dev`
