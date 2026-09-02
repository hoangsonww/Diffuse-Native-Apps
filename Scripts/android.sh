#!/usr/bin/env bash
#
# Gradle for the Android app, without the JDK and adb scavenger hunt.
#
# Gradle honours JAVA_HOME, and most machines carry several JDKs with JAVA_HOME
# pointing at whichever was configured last. The Android Gradle plugin refuses
# to run on anything older than JDK 17, so a raw ./gradlew fails on a machine
# whose default JDK is older. Two things fix that:
#
#   1. Android/gradle/gradle-daemon-jvm.properties, which lets Gradle download
#      and run on its own JDK 17 when none is present.
#   2. This script, which resolves a local JDK 17 first when one exists.
#
# Usage:
#   Scripts/android.sh assembleDebug
#   Scripts/android.sh testDebugUnitTest lintDebug
#   Scripts/android.sh run       # install and launch on a device or emulator
#   Scripts/android.sh devices   # list connected devices and emulators

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$ROOT/Scripts/lib.sh"

ANDROID_DIR="$ROOT/Android"
APP_ID="com.diffuse.android"

usage() {
    cat >&2 <<'USAGE'
Usage: Scripts/android.sh <gradle-task> [gradle-task...]
       Scripts/android.sh run       Install and launch on a device or emulator
       Scripts/android.sh devices   List connected devices and emulators

Common Gradle tasks:
  assembleDebug              Build the debug APK
  assembleRelease            Build the unsigned release APK
  installDebug               Build and install on a connected device
  testDebugUnitTest          Run unit tests
  jacocoDebugUnitTestReport  Unit tests with a coverage report
  lintDebug                  Run Android lint
  connectedDebugAndroidTest  Run instrumented tests on a device
  tasks                      List every available Gradle task
USAGE
    exit 2
}

[ $# -ge 1 ] || usage

if [ "$1" = "devices" ]; then
    adb="$(resolve_adb)"
    step "Connected Android devices"
    "$adb" devices -l
    exit 0
fi

gradle() {
    if ! use_java_17; then
        warn "No local JDK 17; Gradle will provision one."
    fi
    (cd "$ANDROID_DIR" && ./gradlew "$@")
}

if [ "$1" = "run" ]; then
    adb="$(resolve_adb)"
    if [ -z "$("$adb" devices | awk 'NR>1 && $2 == "device"')" ]; then
        fail "No connected device or emulator."
        printf '  Start one from Android Studio, or:\n' >&2
        printf '    %s/emulator/emulator -list-avds\n' "${ANDROID_HOME:-\$ANDROID_HOME}" >&2
        printf '    %s/emulator/emulator -avd <name> &\n' "${ANDROID_HOME:-\$ANDROID_HOME}" >&2
        exit 1
    fi

    # A device can report "device" while Android is still starting, and
    # installDebug then fails for a reason that looks like a build problem. Wait
    # for the boot to finish first — a cold build can easily outrun an emulator
    # that was started alongside it.
    if [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; then
        step "Waiting for the device to finish booting"
        waited=0
        while [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
            if [ "$waited" -ge 180 ]; then
                fail "Device did not finish booting within 180s."
                exit 1
            fi
            sleep 3
            waited=$((waited + 3))
        done
        ok "device ready"
    fi

    step "Installing the debug build"
    gradle installDebug

    step "Launching $APP_ID"
    "$adb" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
    ok "Launched $APP_ID"
    exit 0
fi

gradle "$@"
