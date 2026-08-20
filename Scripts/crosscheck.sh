#!/usr/bin/env bash
#
# Type-checks every shared package against a non-host Apple SDK.
#
# `swift build` only ever targets the host, and building the apps requires the
# full platform runtimes to be installed. This script sits in between: it
# compiles each module in dependency order directly with swiftc against the
# iOS, watchOS, tvOS or visionOS SDK, which catches the mistakes that actually
# happen when code is shared across platforms — a UIKit import that should be
# guarded, an API with a different availability window, a `#if os(...)` that
# excludes something still referenced elsewhere.
#
# Usage: Scripts/crosscheck.sh <ios|watchos|tvos|visionos|macos> [deployment-target]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLATFORM="${1:-ios}"
case "$PLATFORM" in
    ios)      SDK=iphoneos;      TRIPLE_OS="ios${2:-17.0}" ;;
    watchos)  SDK=watchos;       TRIPLE_OS="watchos${2:-10.0}" ;;
    tvos)     SDK=appletvos;     TRIPLE_OS="tvos${2:-17.0}" ;;
    visionos) SDK=xros;          TRIPLE_OS="xros${2:-1.0}" ;;
    macos)    SDK=macosx;        TRIPLE_OS="macos${2:-14.0}" ;;
    *) echo "Unknown platform '$PLATFORM'" >&2; exit 2 ;;
esac

SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
TARGET="arm64-apple-${TRIPLE_OS}"
OUT="$ROOT/.build/crosscheck/$PLATFORM"

rm -rf "$OUT"
mkdir -p "$OUT"

# Dependency order matters: each module needs its dependencies' .swiftmodule.
MODULES=(
    DiffuseModels
    DiffuseDiff
    DiffuseStorage
    DiffuseCapabilities
    DiffuseCore
    DiffuseDeveloperTools
    DiffuseCollectors
    DiffuseUI
)

printf '\033[1mCross-checking for %s (%s)\033[0m\n' "$PLATFORM" "$TARGET"

for MODULE in "${MODULES[@]}"; do
    SOURCES=$(find "Packages/$MODULE/Sources/$MODULE" -name '*.swift' | sort)
    if [ -z "$SOURCES" ]; then
        printf '  \033[33m~\033[0m %s (no sources)\n' "$MODULE"
        continue
    fi

    # shellcheck disable=SC2086
    if xcrun swiftc \
        -target "$TARGET" \
        -sdk "$SDK_PATH" \
        -swift-version 6 \
        -module-name "$MODULE" \
        -emit-module \
        -emit-module-path "$OUT/$MODULE.swiftmodule" \
        -I "$OUT" \
        -enable-upcoming-feature ExistentialAny \
        -suppress-warnings \
        $SOURCES 2> "$OUT/$MODULE.log"; then
        printf '  \033[32m✓\033[0m %s\n' "$MODULE"
    else
        printf '  \033[31m✗\033[0m %s\n' "$MODULE"
        cat "$OUT/$MODULE.log"
        exit 1
    fi
done

printf '\033[32mAll modules type-check for %s.\033[0m\n' "$PLATFORM"
