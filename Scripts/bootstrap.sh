#!/usr/bin/env bash
#
# Prepare a working Diffuse checkout.
#
# Installs missing developer tools when Homebrew is available, generates the
# Xcode project from project.yml, and resolves Swift packages. Signing is
# never configured here: see Documentation/Architecture.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            echo "Installing $1 via Homebrew…"
            brew install "$1"
        else
            echo "Missing required tool: $1" >&2
            echo "Install it, or install Homebrew so this script can." >&2
            exit 1
        fi
    fi
}

need xcodegen
need swiftformat

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Xcode command-line tools are required (xcodebuild)." >&2
    exit 1
fi

echo "Generating Xcode project from project.yml…"
xcodegen generate

if python3 -c "import PIL" >/dev/null 2>&1; then
    if [ ! -f "$ROOT/Apps/DiffuseiOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" ]; then
        echo "Generating app icons…"
        python3 "$ROOT/Scripts/generate-icons.py"
    fi
fi

echo "Resolving Swift packages…"
swift package resolve

if command -v npm >/dev/null 2>&1; then
    echo "Installing git hooks (Husky)…"
    npm install
fi

echo
echo "Diffuse is ready."
echo "  swift test"
echo "  ./Scripts/verify.sh"
echo "  open Diffuse.xcodeproj"
