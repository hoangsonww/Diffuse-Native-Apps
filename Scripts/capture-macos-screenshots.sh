#!/usr/bin/env bash

# Recaptures the macOS screenshots in docs/screenshots/.
#
# Two things about this that are easy to get wrong, and both cost an afternoon
# the first time:
#
# The app's own ScreenshotWriter shells out to `screencapture`, which needs
# Screen Recording permission. Granting it to a debug build does not stick:
# debug builds are ad-hoc signed and get a fresh identity on every rebuild, so
# TCC's record stops matching and the capture silently returns a black image.
# This script captures from the terminal instead, which already holds the
# permission, and only asks the app to put itself on the right screen.
#
# A failed capture is not an error, it is a black PNG. Writing that straight
# over a good screenshot loses it with no warning, so every shot lands in a
# temporary file and is checked for colour variance before it replaces
# anything.
#
# Usage:
#   Scripts/capture-macos-screenshots.sh          # every screen
#   Scripts/capture-macos-screenshots.sh compare  # one screen

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/docs/screenshots"
readonly APP="${ROOT}/.build/dd/Build/Products/Debug/Diffuse.app"
TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "${TMP}"; pkill -f "Diffuse.app/Contents/MacOS/Diffuse" 2>/dev/null || true' EXIT

# Every screen RootView understands, in the order the gallery lists them.
readonly SCREENS=(
    overview snapshots compare capabilities privacy
    search snapshot-detail entity-detail named-snapshot
)

window_id() {
    python3 - <<'PY'
import Quartz
options = (
    Quartz.kCGWindowListOptionOnScreenOnly
    | Quartz.kCGWindowListExcludeDesktopElements
)
for window in Quartz.CGWindowListCopyWindowInfo(options, Quartz.kCGNullWindowID):
    if window.get("kCGWindowOwnerName") != "Diffuse":
        continue
    # The main window, not a panel or a menu bar extra.
    if window.get("kCGWindowBounds", {}).get("Width", 0) > 600:
        print(window["kCGWindowNumber"])
        break
PY
}

# A black or empty capture has almost no colour variance; a drawn UI has plenty.
looks_drawn() {
    python3 - "$1" <<'PY'
import collections
import sys

from PIL import Image

try:
    image = Image.open(sys.argv[1]).convert("RGB").resize((320, 210))
except Exception:
    sys.exit(1)
distinct = len(collections.Counter(image.getdata()))
print(distinct)
sys.exit(0 if distinct > 400 else 1)
PY
}

capture() {
    local screen="$1"
    local target="${TMP}/${screen}.png"
    local id distinct

    pkill -f "Diffuse.app/Contents/MacOS/Diffuse" 2>/dev/null || true
    sleep 2
    open -n --env "DIFFUSE_SCREENSHOT=${screen}" "${APP}"
    sleep 16

    id="$(window_id)"
    if [[ -z "${id}" ]]; then
        warn "${screen}: no window appeared; leaving the existing screenshot alone"
        return 1
    fi

    screencapture -o -x -l "${id}" "${target}"
    pkill -f "Diffuse.app/Contents/MacOS/Diffuse" 2>/dev/null || true

    if ! distinct="$(looks_drawn "${target}")"; then
        warn "${screen}: capture looks blank (${distinct:-0} colours) — Screen Recording is probably denied. Keeping the old file."
        return 1
    fi

    mv "${target}" "${OUT}/macos-${screen}.png"
    ok "macos-${screen}.png (${distinct} colours, $(du -h "${OUT}/macos-${screen}.png" | cut -f1))"
}

main() {
    step "Capturing macOS screenshots"
    if [[ ! -d "${APP}" ]]; then
        warn "Build the app first: make mac-build"
        return 1
    fi

    local failures=0 screen
    for screen in "${@:-${SCREENS[@]}}"; do
        capture "${screen}" || failures=$((failures + 1))
    done

    if [[ "${failures}" -gt 0 ]]; then
        warn "${failures} screen(s) were not replaced."
        return 1
    fi
    ok "Review ${OUT} before committing."
}

main "$@"
