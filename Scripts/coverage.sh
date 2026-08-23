#!/usr/bin/env bash
#
# Run package tests with LLVM coverage and write a first-party report.
#
# Outputs (gitignored):
#   coverage/summary.txt   llvm-cov text report
#   coverage/summary.md    same, wrapped for GitHub step summaries
#   coverage/coverage.lcov lcov for local tools
#   coverage/html/         browsable HTML
#
# Usage:
#   ./Scripts/coverage.sh           # test + report
#   SKIP_TEST=1 ./Scripts/coverage.sh   # report only, using an existing build
#
# No Codecov, Coveralls, or other third-party coverage products.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/coverage"
mkdir -p "$OUT/html"

SKIP_TEST="${SKIP_TEST:-0}"

if [ "$SKIP_TEST" != "1" ]; then
    echo "→ swift test --enable-code-coverage --parallel"
    swift test --package-path "$ROOT" --enable-code-coverage --parallel
fi

BIN_DIR="$(swift build --package-path "$ROOT" --show-bin-path)"
PROFDATA="$BIN_DIR/codecov/default.profdata"

first_match() {
    find "$@" -print 2>/dev/null | awk 'NR==1 { print; exit }'
}

if [ ! -f "$PROFDATA" ]; then
    PROFDATA="$(first_match "$ROOT/.build" -name 'default.profdata')"
fi

if [ -z "${PROFDATA:-}" ] || [ ! -f "$PROFDATA" ]; then
    echo "No coverage profile found. Run without SKIP_TEST=1." >&2
    exit 1
fi

BIN=""
if [ -x "$BIN_DIR/DiffusePackageTests.xctest/Contents/MacOS/DiffusePackageTests" ]; then
    BIN="$BIN_DIR/DiffusePackageTests.xctest/Contents/MacOS/DiffusePackageTests"
elif [ -x "$BIN_DIR/DiffusePackageTests.xctest" ]; then
    BIN="$BIN_DIR/DiffusePackageTests.xctest"
else
    BIN="$(first_match "$BIN_DIR" -name 'DiffusePackageTests' -type f)"
fi

if [ -z "$BIN" ] || [ ! -e "$BIN" ]; then
    echo "Could not find DiffusePackageTests binary under $BIN_DIR" >&2
    exit 1
fi

# Package sources only — generated SPM trees and the suites themselves inflate
# the denominator without telling us whether the product is covered.
IGNORE='(\.build|Tests/|/Tests|Package\.swift)'

echo "→ llvm-cov report"
echo "  binary:    $BIN"
echo "  profile:   $PROFDATA"

xcrun llvm-cov report "$BIN" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex="$IGNORE" \
    | tee "$OUT/summary.txt"

xcrun llvm-cov export "$BIN" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex="$IGNORE" \
    -format=lcov \
    > "$OUT/coverage.lcov"

xcrun llvm-cov show "$BIN" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex="$IGNORE" \
    -format=html \
    -output-dir="$OUT/html"

{
    echo "## Package coverage"
    echo
    echo "First-party \`llvm-cov\` report. HTML is attached as a CI artifact."
    echo
    echo '```'
    cat "$OUT/summary.txt"
    echo '```'
} > "$OUT/summary.md"

echo
echo "Wrote $OUT/summary.txt"
echo "Wrote $OUT/coverage.lcov"
echo "Wrote $OUT/html/index.html"

# Hold the package to a floor so a regression fails the run instead of being
# noticed weeks later in a report nobody opened.
MINIMUM="${DIFFUSE_MINIMUM_COVERAGE:-90}"
PERCENT="$(awk '$1 == "TOTAL" { gsub(/%/, "", $(NF-3)); print $(NF-3); exit }' "$OUT/summary.txt")"

if [[ -z "$PERCENT" ]]; then
    echo "Could not read a total line-coverage percentage from $OUT/summary.txt" >&2
    exit 1
fi

echo
if awk -v value="$PERCENT" -v floor="$MINIMUM" 'BEGIN { exit !(value < floor) }'; then
    echo "Line coverage ${PERCENT}% is below the required ${MINIMUM}%." >&2
    exit 1
fi

echo "Line coverage ${PERCENT}% meets the ${MINIMUM}% floor."
