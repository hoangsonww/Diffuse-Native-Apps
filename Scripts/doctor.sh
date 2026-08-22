#!/usr/bin/env bash
#
# Reports which parts of Diffuse this machine can build.
#
# Nothing here installs or changes anything. Run it first to find out whether
# the Apple apps, the Android app, or only the docs and web surface are
# available before a suite fails halfway through and leaves you guessing.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$ROOT/Scripts/lib.sh"

row() {
    printf '%-9s %-14s %s\n' "$1" "$2" "$3"
}

check_required() {
    if command -v "$1" >/dev/null 2>&1; then
        row "ok" "$1" "$2"
    else
        row "MISSING" "$1" "$2"
        STATUS=1
    fi
}

check_optional() {
    if command -v "$1" >/dev/null 2>&1; then
        row "ok" "$1" "$2"
    else
        row "optional" "$1" "$2"
    fi
}

STATUS=0

printf 'Diffuse development environment\n\n'

printf 'Core\n'
check_required git "source control"
check_optional node "git hooks and landing-page tooling"
check_optional npm "git hooks"
check_optional shellcheck "shell linting (required by CI)"
check_optional docker "containerised toolbox"
check_optional python3 "icon generation and simulator queries"

printf '\nApple\n'
if [ "$(uname -s)" = "Darwin" ]; then
    check_required xcodebuild "building the four Apple apps"
    check_required xcrun "simulator control"
    check_required swift "Swift package tests"
    check_optional xcodegen "generating Diffuse.xcodeproj from project.yml"
    check_optional swiftformat "format linting"

    if [ -d "$ROOT/Diffuse.xcodeproj" ]; then
        row "ok" "xcodeproj" "generated"
    else
        row "notice" "xcodeproj" "not generated; run make bootstrap"
    fi

    if simulator_id="$(resolve_simulator iphone 2>/dev/null)"; then
        row "ok" "simulator" "$(simulator_name "$simulator_id")"
    else
        row "notice" "simulator" "no iPhone simulator available"
    fi
else
    row "n/a" "Xcode" "the Apple apps require macOS"
fi

printf '\nAndroid\n'
# A local JDK is a convenience, not a requirement: Gradle provisions its own
# from Android/gradle/gradle-daemon-jvm.properties.
if use_java_17 2>/dev/null; then
    row "ok" "java" "JDK $(java_major_version) at ${JAVA_HOME:-$(command -v java)}"
else
    row "optional" "java" "no local JDK 17; Gradle will download one"
fi

if [ -f "$ROOT/Android/gradle/gradle-daemon-jvm.properties" ]; then
    row "ok" "daemon JVM" "Gradle provisions its own JDK 17"
else
    row "MISSING" "daemon JVM" "Android/gradle/gradle-daemon-jvm.properties absent"
    STATUS=1
fi

if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}" ]; then
    row "ok" "ANDROID_HOME" "${ANDROID_HOME}"
else
    row "notice" "ANDROID_HOME" "not set; Android Studio may still provide the SDK"
fi

if adb_path="$(resolve_adb 2>/dev/null)"; then
    row "ok" "adb" "$adb_path"
else
    row "notice" "adb" "not found; needed only to install on a device"
fi

printf '\nRepository: %s\n' "$ROOT"

if [ "$STATUS" -ne 0 ]; then
    printf '\n\033[31mSome required tools are missing.\033[0m\n'
    exit 1
fi

printf '\n\033[32mReady.\033[0m Run make help for available commands.\n'
