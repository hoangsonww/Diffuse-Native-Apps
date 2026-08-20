#!/usr/bin/env bash
#
# One command that answers "is this checkout healthy?"
#
# Format (lint), package tests, SDK cross-checks, and unsigned builds of all
# four apps. Prints "Diffuse is healthy." on success. Intended for local use
# and for CI.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED="${DERIVED_DATA_PATH:-$ROOT/.build/dd}"
CONFIG="${CONFIGURATION:-Debug}"
FAILED=0

step() {
    printf '\n\033[1m→ %s\033[0m\n' "$1"
}

ok() {
    printf '  \033[32m✓\033[0m %s\n' "$1"
}

fail() {
    printf '  \033[31m✗\033[0m %s\n' "$1"
    FAILED=1
}

if [ ! -d "$ROOT/Diffuse.xcodeproj" ]; then
    step "Generate Xcode project"
    xcodegen generate
fi

step "SwiftFormat (lint)"
if command -v swiftformat >/dev/null 2>&1; then
    if swiftformat Packages Apps Tools Tests --config "$ROOT/.swiftformat" --lint; then
        ok "format"
    else
        echo "  Run ./Scripts/format.sh to apply formatting."
        fail "format"
    fi
else
    echo "  swiftformat not installed; skipping."
fi

step "Swift package tests"
if swift test --package-path "$ROOT"; then
    ok "swift test"
else
    fail "swift test"
fi

step "SDK cross-check (iOS)"
if "$ROOT/Scripts/crosscheck.sh" ios; then
    ok "crosscheck ios"
else
    fail "crosscheck ios"
fi

step "SDK cross-check (watchOS)"
if "$ROOT/Scripts/crosscheck.sh" watchos; then
    ok "crosscheck watchos"
else
    fail "crosscheck watchos"
fi

build_app() {
    local scheme="$1"
    local destination="$2"
    step "xcodebuild $scheme ($destination)"
    if xcodebuild \
        -project "$ROOT/Diffuse.xcodeproj" \
        -scheme "$scheme" \
        -configuration "$CONFIG" \
        -destination "$destination" \
        -derivedDataPath "$DERIVED" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY=- \
        build; then
        ok "$scheme"
    else
        fail "$scheme"
    fi
}

build_app DiffuseMac    "generic/platform=macOS"
build_app DiffuseiOS    "generic/platform=iOS"
build_app DiffuseiPadOS "generic/platform=iOS"
build_app DiffuseWatch  "generic/platform=watchOS"

echo
if [ "$FAILED" -ne 0 ]; then
    printf '\033[31mDiffuse is not healthy.\033[0m\n'
    exit 1
fi

printf '\033[32mDiffuse is healthy.\033[0m\n'
