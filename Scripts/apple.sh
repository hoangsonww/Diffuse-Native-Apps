#!/usr/bin/env bash
#
# Build, install, and launch any of the four Apple apps without opening Xcode
# or looking up a simulator UDID.
#
# Usage:
#   Scripts/apple.sh build   <ios|ipados|watch|mac>
#   Scripts/apple.sh run     <ios|ipados|watch|mac>
#   Scripts/apple.sh boot    <ios|ipados|watch>
#   Scripts/apple.sh devices [ios|ipados|watch]
#
# Pin a specific simulator with DIFFUSE_SIMULATOR_ID=<udid>.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$ROOT/Scripts/lib.sh"

DERIVED="${DERIVED_DATA_PATH:-$ROOT/.build/dd}"
CONFIG="${CONFIGURATION:-Debug}"

usage() {
    cat >&2 <<'USAGE'
Usage: Scripts/apple.sh <command> <platform>

Commands:
  build    Build the app
  run      Build, install, and launch
  boot     Boot the simulator and open Simulator.app
  devices  List available simulators

Platforms:
  ios      DiffuseiOS      (iPhone simulator)
  ipados   DiffuseiPadOS   (iPad simulator)
  watch    DiffuseWatch    (Apple Watch simulator)
  mac      DiffuseMac      (this machine)
USAGE
    exit 2
}

[ $# -ge 1 ] || usage
require_macos
require_command xcodebuild
require_command xcrun

COMMAND="$1"
PLATFORM="${2:-ios}"

case "$PLATFORM" in
    ios)    SCHEME=DiffuseiOS;    FAMILY=iphone ;;
    ipados) SCHEME=DiffuseiPadOS; FAMILY=ipad ;;
    watch)  SCHEME=DiffuseWatch;  FAMILY=watch ;;
    mac)    SCHEME=DiffuseMac;    FAMILY=mac ;;
    *)      usage ;;
esac

if [ "$COMMAND" = "devices" ]; then
    if [ "$FAMILY" = "mac" ]; then
        step "macOS builds run on this machine; there is no simulator to list."
        exit 0
    fi
    step "Available simulators"
    xcrun simctl list devices available
    exit 0
fi

# The Xcode project is generated from project.yml and is not versioned.
if [ ! -d "$ROOT/Diffuse.xcodeproj" ]; then
    step "Generating the Xcode project"
    require_command xcodegen
    xcodegen generate
fi

if [ "$FAMILY" = "mac" ]; then
    DEVICE_LABEL="this Mac"
    DESTINATION="platform=macOS"
else
    # Simulator lookup parses `simctl list -j`.
    require_command python3
    DEVICE_ID="$(resolve_simulator "$FAMILY")"
    DEVICE_LABEL="$(simulator_name "$DEVICE_ID") ($DEVICE_ID)"
    DESTINATION="id=$DEVICE_ID"
fi

if [ "$COMMAND" = "boot" ]; then
    [ "$FAMILY" != "mac" ] || usage
    step "Booting $DEVICE_LABEL"
    boot_simulator "$DEVICE_ID"
    open -a Simulator
    exit 0
fi

case "$COMMAND" in
    build|run) ;;
    *) usage ;;
esac

step "Building $SCHEME for $DEVICE_LABEL"
xcodebuild \
    -project "$ROOT/Diffuse.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=- \
    build

ok "$SCHEME built"
[ "$COMMAND" = "run" ] || exit 0

# Ask xcodebuild where it put the bundle rather than guessing. The product name
# is not the scheme name — DiffuseMac builds Diffuse.app and DiffuseiPadOS
# builds "Diffuse for iPad.app" — and the products directory depends on whether
# the destination was a simulator or a device.
BUILD_SETTINGS="$(xcodebuild \
    -project "$ROOT/Diffuse.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" \
    -showBuildSettings 2>/dev/null)"

products_dir="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ TARGET_BUILD_DIR = /{print $2; exit}')"
wrapper_name="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/ WRAPPER_NAME = /{print $2; exit}')"
APP_PATH="${products_dir}/${wrapper_name}"

if [ ! -d "$APP_PATH" ]; then
    fail "Built app not found at ${APP_PATH:-<unresolved>}"
    printf '  Products present under %s:\n' "$DERIVED/Build/Products" >&2
    find "$DERIVED/Build/Products" -maxdepth 2 -name '*.app' 2>/dev/null | sed 's/^/    /' >&2
    exit 1
fi

if [ "$FAMILY" = "mac" ]; then
    step "Launching $SCHEME"
    open "$APP_PATH"
    ok "Launched $SCHEME"
    exit 0
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist")"

step "Installing and launching $BUNDLE_ID"
boot_simulator "$DEVICE_ID"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
open -a Simulator

ok "Launched $BUNDLE_ID on $DEVICE_LABEL"
