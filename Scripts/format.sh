#!/usr/bin/env bash
#
# Format every first-party Swift file in place.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "swiftformat is not installed. Run ./Scripts/bootstrap.sh" >&2
    exit 1
fi

swiftformat \
    Packages \
    Apps \
    Tools \
    Tests \
    --config "$ROOT/.swiftformat"
