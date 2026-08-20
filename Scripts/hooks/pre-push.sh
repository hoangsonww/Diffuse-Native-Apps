#!/usr/bin/env bash
# Fast push gate. Full verify.sh is for CI and humans, not every push.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if command -v swiftformat >/dev/null 2>&1; then
    swiftformat Packages Apps Tools Tests --config "$ROOT/.swiftformat" --lint
else
    echo "pre-push: swiftformat not installed; skip" >&2
fi
