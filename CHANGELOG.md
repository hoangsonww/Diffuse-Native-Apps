# Changelog

All notable changes to Diffuse are documented here.

## Unreleased

## 1.1.1 — 2026-09-03

### Developer experience

- Android no longer requires a preinstalled JDK. The Gradle wrapper moves from
  8.11.1 to 8.13, `Android/settings.gradle.kts` applies the foojay resolver, and
  `Android/gradle/gradle-daemon-jvm.properties` pins daemon JVM criteria, so
  Gradle downloads and runs on its own Adoptium JDK 17 for the host OS and
  architecture. `./gradlew` works on a clean checkout whatever `java` is on
  `PATH`.
- `Scripts/apple.sh` builds, installs, and launches any of the four Apple apps
  on an automatically resolved simulator — no Xcode UI and no device UDID.
- `Scripts/android.sh` runs Gradle with a guaranteed JDK and resolves `adb`
  from `ANDROID_HOME`, which is not on `PATH` after a default Android Studio
  install.
- `Scripts/doctor.sh` reports which parts of the repository this machine can
  build, grouped by Apple, Android, and shared tooling.
- `Scripts/lib.sh` holds the shared JDK, `adb`, and simulator resolution.
- The Makefile gains a `help` target and one-command entry points:
  `ios-run`, `ipados-run`, `watch-run`, `mac-run`, `android-run`, plus build,
  test, lint, device-listing, and `gradle ARGS="…"` passthrough.
- The Docker toolbox now carries a Temurin JDK 17 and the Android SDK, so
  Linux and Codespaces contributors can build and test the Android app.
  `Scripts/verify-devcontainer.sh` builds the image and asserts the toolchain
  inside it actually works; `--build` compiles the Android app from an isolated
  `git archive` copy so a container build never shares `app/build/` with a host
  build. The Apple apps still require Xcode on macOS.
- `.github/workflows/release-android.yml` attaches an unsigned release APK and
  its checksum to each tagged release, matching the unsigned stance of
  `release-apple.yml`.

### Apps

- Native Kotlin / Jetpack Compose Android app with an independent domain engine,
  WorkManager scheduling, and schema-v1 fixture compatibility ([ADR 0009](Documentation/adr/0009-native-android.md)).
- Full live-app screenshot gallery for Android, iPhone, iPad, Watch, and Mac in
  `docs/screenshots/`, wired into the README, architecture docs, and landing page.

### Engine

- Export redaction always walks properties, so a `restricted` field on a
  `local` section is stripped even under `RedactionPolicy.none`.

### Documentation

- `Documentation/TechStack.md` — every technology in the repository, the version
  it is pinned to, where it appears, and why it is there.
- `Documentation/Troubleshooting.md` — build, test, simulator, emulator, hook,
  and repository-hygiene failures with their fixes.
- `Documentation/Releasing.md` — versioning, the tag-triggered workflows, the
  pre-tag checklist, and what is deliberately not automated.
- README: a full technology badge row, an annotated schema-v1 snapshot showing
  how comparison rules travel with the data, `diffuse-dev` usage, a tech-stack
  summary, and citation metadata.
- `Android/README.md` expanded to cover the source layout, capture and storage
  design, the full dependency list, CI behaviour, and local SDK setup.

### Repository

- `CITATION.cff` so GitHub can render "Cite this repository".
- `.gitignore` hardened: signing material (`*.p12`, `*.jks`, `*.mobileprovision`,
  `keystore.properties`), coverage profiles, Gradle and Kotlin caches, editor
  state, and the raw `Android/screenshots/` QA gallery. Only the curated
  `docs/screenshots/` set is versioned.
- `.gitattributes`: per-language diff drivers, CRLF for `gradlew.bat`, binary
  markers for `.jar`/`.jpg`, and linguist hints so the language bar reflects
  Swift and Kotlin rather than fixtures and the marketing site.
- GitHub issue and pull-request templates, and CODEOWNERS.
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
