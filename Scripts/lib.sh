#!/usr/bin/env bash
#
# Shared helpers for the developer-experience scripts.
#
# The goal of everything in here is that a fresh checkout builds and runs
# without the contributor first configuring a JDK, locating adb, or looking up
# a simulator UDID. Source it; do not execute it.

# shellcheck disable=SC2034
DIFFUSE_LIB_SOURCED=1

step() {
    printf '\n\033[1m→ %s\033[0m\n' "$1"
}

ok() {
    printf '  \033[32m✓\033[0m %s\n' "$1"
}

warn() {
    printf '  \033[33m!\033[0m %s\n' "$1"
}

fail() {
    printf '  \033[31m✗\033[0m %s\n' "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$1" >&2
        return 1
    fi
}

require_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        printf 'This workflow requires macOS and Xcode.\n' >&2
        return 2
    fi
}

java_major_version() {
    java -version 2>&1 | awk -F '"' '/version/ { split($2, parts, "."); print (parts[1] == "1" ? parts[2] : parts[1]); exit }'
}

# Points JAVA_HOME at a JDK 17 or newer when one can be found. Android builds
# still work without this because Gradle provisions its own JDK from
# Android/gradle/gradle-daemon-jvm.properties, so a failure here is a warning,
# never a hard stop.
use_java_17() {
    local candidate=""

    if command -v java >/dev/null 2>&1 && [ "$(java_major_version)" -ge 17 ] 2>/dev/null; then
        return 0
    fi

    if [ -n "${JAVA_17_HOME:-}" ] && [ -x "${JAVA_17_HOME}/bin/java" ]; then
        candidate="${JAVA_17_HOME}"
    elif [ "$(uname -s)" = "Darwin" ] && [ -x /usr/libexec/java_home ]; then
        candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    elif [ -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ]; then
        candidate="/usr/lib/jvm/java-17-openjdk-amd64"
    fi

    if [ -n "${candidate}" ]; then
        export JAVA_HOME="${candidate}"
        export PATH="${JAVA_HOME}/bin:${PATH}"
    fi

    if ! command -v java >/dev/null 2>&1 || ! [ "$(java_major_version)" -ge 17 ] 2>/dev/null; then
        return 1
    fi
}

# Echoes a usable adb path. platform-tools is not on PATH after a default
# Android Studio install, so fall back to the SDK location.
resolve_adb() {
    if command -v adb >/dev/null 2>&1; then
        command -v adb
        return 0
    fi

    local sdk_root candidate
    for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "${HOME}/Library/Android/sdk" "${HOME}/Android/Sdk"; do
        [ -n "${sdk_root}" ] || continue
        candidate="${sdk_root}/platform-tools/adb"
        if [ -x "${candidate}" ]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done

    printf 'adb was not found. Install Android platform-tools or set ANDROID_HOME.\n' >&2
    return 1
}

# Echoes the UDID of an available simulator for the given platform family.
# Honours DIFFUSE_SIMULATOR_ID so a caller can pin a specific device.
#   resolve_simulator iphone | ipad | watch
resolve_simulator() {
    local family="${1:-iphone}"
    local device_id="${DIFFUSE_SIMULATOR_ID:-}"

    if [ -n "${device_id}" ]; then
        printf '%s' "${device_id}"
        return 0
    fi

    device_id="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
family = sys.argv[1].lower()
prefixes = {"iphone": ("iPhone",), "ipad": ("iPad",), "watch": ("Apple Watch",)}[family]
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group]
for device in devices:
    if device["name"].startswith(prefixes):
        sys.stdout.write(device["udid"])
        break
' "${family}")"

    if [ -z "${device_id}" ]; then
        printf 'No available %s simulator was found.\n' "${family}" >&2
        return 1
    fi

    printf '%s' "${device_id}"
}

simulator_name() {
    xcrun simctl list devices -j | python3 -c '
import json, sys
target = sys.argv[1]
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group]
for device in devices:
    if device["udid"] == target:
        sys.stdout.write(device["name"])
        break
else:
    sys.stdout.write(target)
' "$1"
}

boot_simulator() {
    xcrun simctl boot "$1" 2>/dev/null || true
    xcrun simctl bootstatus "$1" -b
}
