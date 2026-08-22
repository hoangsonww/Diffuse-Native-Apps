# Troubleshooting

Problems you hit while *building, testing, or running* Diffuse. Questions about what the product does belong in [SUPPORT.md](../SUPPORT.md); a collector that hangs or lies belongs in [CollectorGuide.md](CollectorGuide.md) and skill `debug-collector`.

## Setup

### `./Scripts/bootstrap.sh` cannot find a tool

`bootstrap.sh` installs `xcodegen` and `swiftformat` through Homebrew when it is available, and otherwise exits with the missing name. Without Homebrew, install them yourself and rerun:

```bash
brew install xcodegen swiftformat   # or install by hand
./Scripts/bootstrap.sh
```

`xcodebuild` is checked but never installed — that needs Xcode from the App Store or the developer portal.

### `xcodebuild` picks the wrong Xcode

CI pins `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Locally:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version    # expect 16.x
```

### There is no `Diffuse.xcodeproj`

That is correct. The project file is generated from `project.yml` and gitignored ([ADR 0005](adr/0005-generated-unsigned.md)).

```bash
xcodegen generate      # or ./Scripts/bootstrap.sh
open Diffuse.xcodeproj
```

If the project looks stale after you add a file, regenerate — `project.yml` uses directory-based `sources`, so new files appear only after `xcodegen generate`.

### App icons are missing in a fresh checkout

`bootstrap.sh` runs `Scripts/generate-icons.py` only when Pillow is importable **and** the iOS icon is absent.

```bash
python3 -m pip install pillow
python3 Scripts/generate-icons.py
```

Missing icons never break a build. They only make the simulator look unfinished.

## Building and testing (Apple)

### `swift test` succeeds but the app target fails

The Swift Package Manager graph and the Xcode app targets are different builds. `swift test` never compiles AppKit/UIKit code. Run the real gate:

```bash
./Scripts/verify.sh
```

It lints formatting, runs `swift test`, cross-checks iOS and watchOS, and builds all four Apple apps unsigned. Success prints `Diffuse is healthy.`

### A core package suddenly imports UIKit

`Scripts/crosscheck.sh` exists precisely for this. It compiles each shared module with `swiftc` against a non-host SDK in dependency order:

```bash
./Scripts/crosscheck.sh ios
./Scripts/crosscheck.sh watchos
./Scripts/crosscheck.sh tvos 17.0     # also supported
```

A failure here means platform-specific code leaked below `DiffuseUI`. Guard it with `#if os(...)`, or move it into `Apps/` or `DiffuseCollectors` where it belongs.

### Formatting fails in CI but the code looks fine

CI runs `swiftformat --lint` with the repository `.swiftformat`. Your editor's formatter is not that configuration.

```bash
./Scripts/format.sh          # fixes in place
npm install                  # Husky + lint-staged so this happens on commit
```

### `swift test` is slow or flaky under parallelism

```bash
swift test --parallel
swift test --filter DiffuseDomainTests
swift test --filter MacGitCollector
```

Integration tests that touch live collectors are macOS-gated and deliberately limited to cheap, stable capabilities. If one is flaky, it is a bug in the test's determinism — do not add a sleep. See [Testing.md](Testing.md).

### Coverage output is empty or stale

```bash
./Scripts/coverage.sh          # test + llvm-cov → coverage/
SKIP_TEST=1 ./Scripts/coverage.sh   # rebuild reports from an existing profile
```

`coverage/` is gitignored at the repository root only, so a skill or directory named `coverage` elsewhere is still versioned.

### A golden fixture test fails

Read the diff before touching anything. A fixture failure means the serialized shape or the diff result changed.

```bash
swift test --filter Fixture
./Scripts/generate-fixtures.sh    # only after you understand the change
git diff Fixtures/
```

Never weaken a fixture to make a test pass — that is an explicit rule in [AGENTS.md](../AGENTS.md). Skill: `fixtures`.

## Building and testing (Android)

### Gradle cannot find an SDK

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
# or create Android/local.properties (gitignored):
echo "sdk.dir=$HOME/Library/Android/sdk" > Android/local.properties
```

`compileSdk` and `targetSdk` are 36; CI installs `platforms;android-36` and `build-tools;35.0.0`.

### Wrong JDK

```bash
java -version    # expect 17
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
```

The build sets `sourceCompatibility`, `targetCompatibility`, and `jvmTarget` to 17. A newer JDK on `PATH` will fail the Kotlin compile with a jvm-target mismatch.

### `FixtureCompatibilityTest` cannot find fixtures

The JVM suite reads the repository's root `Fixtures/` through the `diffuse.fixtures` system property, wired in `Android/app/build.gradle.kts`. It resolves `rootProject.file("../Fixtures")`, so it only works when `Android/` sits inside this repository. Running the Gradle project in isolation breaks it by design — the cross-language contract is the point.

### JaCoCo verification fails

```bash
cd Android
./gradlew jacocoDebugUnitTestReport            # see what is uncovered
open app/build/reports/jacoco/jacocoDebugUnitTestReport/html/index.html
```

The rule applies to `com.diffuse.android.domain` only, at 90% line coverage. If the uncovered lines are Android-framework code, they are in the wrong package — pure domain logic belongs in `domain/`, platform observation in `collectors/`.

### `connectedDebugAndroidTest` finds no device

```bash
adb devices                       # must list one device in `device` state
adb shell getprop sys.boot_completed   # must print 1
```

CI creates a Pixel 6 API 34 image with `google_apis;x86_64` and waits for `sys.boot_completed`. Locally, start the emulator and let it finish booting before invoking Gradle.

### Release build behaves differently from debug

`isMinifyEnabled = true` on release, so R8 and `app/proguard-rules.pro` apply. Serialization is the usual casualty. Reproduce with:

```bash
./gradlew assembleRelease
```

and add a keep rule rather than disabling minification.

## Running the apps

### Widgets and complications are empty

Expected in unsigned builds. Widgets read a shared app-group container (`group.com.diffuse.ios`, `.ipados`, `.watch`), and app groups require a signed identity. The extension still compiles, which is what CI verifies.

### The Mac app cannot see developer tools

The macOS app is intentionally **not sandboxed** so it can run `git`, `node --version`, and similar probes. If tools are missing, check that they resolve on the app's `PATH`, not just in your shell. See [Privacy.md](Privacy.md).

### The Wi-Fi name is blank on macOS

Grant Location permission. Core WLAN returns the SSID only to a process with location authorization. Diffuse never reads coordinates, BSSID, or nearby networks.

### A scheduled capture did not save

Two guards, both deliberate ([Apps.md](Apps.md)):

- the 15-minute floor applies to automatic captures
- skip-if-unchanged drops an automatic capture identical to the previous one

Manual captures always persist. Both defaults are visible and adjustable in Settings.

### The process list is empty

It is opt-in (`isEnabledByDefault: false`) and macOS-only. Enable it under Capabilities.

### The library looks empty after seeding fixtures for screenshots

Snapshots carry device identity and timestamps. If the seeded snapshot claims a different platform or a date the UI filters out, nothing renders. Rewrite timestamps and device identity when seeding, and disable auto-capture on open so scheduling does not insert a live snapshot on top. Skill: `screenshots`.

## Repository hygiene

### Git wants to commit build output

Check why before adding a new rule — the ignore file is already thorough:

```bash
git check-ignore -v <path>
git status --porcelain --untracked-files=all | grep '^??'
```

`Android/screenshots/` (raw emulator QA), root `landing-*.png` (Playwright QA of the marketing site), `coverage/`, `.build/`, `_site/`, and `Diffuse.xcodeproj/` are all ignored on purpose. Only the curated `docs/screenshots/` gallery is versioned.

### A commit is blocked

The `.claude/hooks/` and `Scripts/hooks/` hooks refuse signing material and reformat Swift. If a commit is rejected for a certificate, profile, or keystore, that is the hook doing its job — configure signing outside this repository ([ADR 0005](adr/0005-generated-unsigned.md)).

### ShellCheck fails in CI but not locally

CI runs it with `-x` so sourced files are followed:

```bash
shellcheck -x Scripts/*.sh Scripts/hooks/*.sh .claude/hooks/*.sh
```

## Docker and Dev Containers

The image is a `node:22-bookworm-slim` toolbox for docs, scripts, and hooks. It **cannot** run `swift test` or build any app — that needs macOS and Xcode, and Android additionally needs the Android SDK.

```bash
docker compose up -d
docker compose exec dev bash
```

If `git` complains about a dubious ownership inside the container, the Dev Container `postCreateCommand` already handles it; for plain Compose run `git config --global --add safe.directory /workspace`.

## Still stuck

- [Testing.md](Testing.md) — where a test belongs and why it might be failing
- [Repository.md](Repository.md) — every script, workflow, and hook
- [CollectorGuide.md](CollectorGuide.md) and skill `debug-collector` — a capability that hangs, throws, or flakes
- [SUPPORT.md](../SUPPORT.md) — product behaviour rather than build behaviour
- [SECURITY.md](../SECURITY.md) — do not open a public issue for a vulnerability
