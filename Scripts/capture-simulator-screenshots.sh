#!/usr/bin/env bash

# Recaptures the iPhone, iPad and Watch screenshots in docs/screenshots/.
#
# The screen is chosen with SIMCTL_CHILD_DIFFUSE_SCREENSHOT rather than
# DIFFUSE_SCREENSHOT: `simctl launch` forwards SIMCTL_CHILD_-prefixed variables
# into the app's environment, while anything else passed on the command line
# arrives as argv and is ignored.
#
# Like the macOS script, each shot lands in a temporary file and is checked for
# colour variance before it replaces a committed screenshot — a simulator that
# has not finished launching produces a plausible-looking blank frame.
#
# Usage:
#   Scripts/capture-simulator-screenshots.sh              # every platform
#   Scripts/capture-simulator-screenshots.sh ios          # one platform
#   Scripts/capture-simulator-screenshots.sh ios compare  # one screen

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/docs/screenshots"
TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "${TMP}"' EXIT

readonly IOS_SCREENS=(overview timeline compare settings capabilities privacy search snapshot-detail entity-detail)
readonly IPAD_SCREENS=(workspace privacy capabilities settings search snapshot-detail entity-detail change-detail)
readonly WATCH_SCREENS=(glance settings snapshot-detail change-detail)

# platform → bundle id, device name substring, output prefix
bundle_for() {
    case "$1" in
        ios) printf 'com.diffuse.ios' ;;
        ipados) printf 'com.diffuse.ipados' ;;
        watchos) printf 'com.diffuse.watch' ;;
    esac
}

device_for() {
    case "$1" in
        ios) printf 'iPhone 17 Pro' ;;
        ipados) printf 'iPad Pro 13-inch (M5)' ;;
        watchos) printf 'Apple Watch Series 11 (46mm)' ;;
    esac
}

prefix_for() {
    case "$1" in
        ios) printf 'ios' ;;
        ipados) printf 'ipados' ;;
        watchos) printf 'watchos' ;;
    esac
}

udid_for() {
    xcrun simctl list devices available -j \
        | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for device in devices:
        if device['name'] == name:
            print(device['udid'])
            raise SystemExit
" "$1"
}

looks_drawn() {
    python3 - "$1" <<'PY'
import collections
import sys

from PIL import Image

try:
    image = Image.open(sys.argv[1]).convert("RGB").resize((240, 400))
except Exception:
    sys.exit(1)
distinct = len(collections.Counter(image.getdata()))
print(distinct)
# Watch faces are small and flat, so the bar is lower than on desktop.
sys.exit(0 if distinct > 150 else 1)
PY
}

capture_platform() {
    local platform="$1"
    shift
    local bundle device prefix udid
    bundle="$(bundle_for "${platform}")"
    device="$(device_for "${platform}")"
    prefix="$(prefix_for "${platform}")"

    udid="$(udid_for "${device}")"
    if [[ -z "${udid}" ]]; then
        warn "${platform}: no simulator named '${device}'"
        return 1
    fi

    step "${platform} — ${device}"
    xcrun simctl bootstatus "${udid}" -b >/dev/null 2>&1 || xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "${udid}" >/dev/null 2>&1 || true

    local failures=0 screen target distinct
    for screen in "$@"; do
        target="${TMP}/${prefix}-${screen}.png"
        xcrun simctl terminate "${udid}" "${bundle}" >/dev/null 2>&1 || true
        sleep 1
        SIMCTL_CHILD_DIFFUSE_SCREENSHOT="${screen}" \
            xcrun simctl launch "${udid}" "${bundle}" >/dev/null 2>&1 || true
        sleep 9
        xcrun simctl io "${udid}" screenshot "${target}" >/dev/null 2>&1 || true

        if [[ ! -f "${target}" ]] || ! distinct="$(looks_drawn "${target}")"; then
            warn "${prefix}-${screen}: blank or missing; keeping the existing file"
            failures=$((failures + 1))
            continue
        fi
        mv "${target}" "${OUT}/${prefix}-${screen}.png"
        ok "${prefix}-${screen}.png (${distinct} colours)"
    done

    xcrun simctl terminate "${udid}" "${bundle}" >/dev/null 2>&1 || true
    return "$((failures > 0))"
}

main() {
    local platform="${1:-}"
    shift || true

    case "${platform}" in
        ios) capture_platform ios "${@:-${IOS_SCREENS[@]}}" ;;
        ipados) capture_platform ipados "${@:-${IPAD_SCREENS[@]}}" ;;
        watchos) capture_platform watchos "${@:-${WATCH_SCREENS[@]}}" ;;
        "")
            local failures=0
            capture_platform ios "${IOS_SCREENS[@]}" || failures=$((failures + 1))
            capture_platform ipados "${IPAD_SCREENS[@]}" || failures=$((failures + 1))
            capture_platform watchos "${WATCH_SCREENS[@]}" || failures=$((failures + 1))
            [[ "${failures}" -eq 0 ]] || return 1
            ;;
        *)
            warn "Unknown platform '${platform}'. Use ios, ipados, or watchos."
            return 2
            ;;
    esac

    ok "Review ${OUT} before committing."
}

main "$@"
