#!/usr/bin/env bash

# Recaptures the Android screenshots in docs/screenshots/ from a running app.
#
# The Apple apps take a DIFFUSE_SCREENSHOT environment variable and put
# themselves on the right screen. Android has no such hook, so this drives the
# real UI through adb: it dumps the view hierarchy, finds a node by its text or
# content description, and taps the middle of it. That is slower than an env
# var but it fails loudly when a label moves, which is what you want from
# something that is meant to prove the docs match the app.
#
# Usage:
#   Scripts/capture-android-screenshots.sh            # every screen
#   Scripts/capture-android-screenshots.sh search     # one screen by name
#
# Requires a booted emulator or device. Installs the debug build first.

set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

readonly APP_ID="com.diffuse.android"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUT="${ROOT}/docs/screenshots"
TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "${TMP}"' EXIT

adb_bin() {
    if command -v adb >/dev/null 2>&1; then
        command -v adb
    else
        printf '%s/platform-tools/adb' "${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
    fi
}
ADB="$(adb_bin)"
readonly ADB

dump_ui() {
    "${ADB}" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
    "${ADB}" shell cat /sdcard/ui.xml > "${TMP}/ui.xml" 2>/dev/null || true
}

# Prints "x y" for the centre of the first node whose text or content-desc
# matches exactly, or nothing when there is no such node.
find_node() {
    local needle="$1"
    python3 - "$needle" "${TMP}/ui.xml" <<'PY'
import re, sys
needle, path = sys.argv[1], sys.argv[2]
try:
    xml = open(path, encoding="utf-8").read()
except OSError:
    sys.exit(0)
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    label = None
    for attr in ("text", "content-desc"):
        found = re.search(rf'{attr}="([^"]*)"', tag)
        if found and found.group(1) == needle:
            label = found.group(1)
            break
    if label is None:
        continue
    bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
    if bounds:
        x1, y1, x2, y2 = map(int, bounds.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
}

tap() {
    local needle="$1" tries="${2:-12}" coords
    for _ in $(seq 1 "${tries}"); do
        dump_ui
        coords="$(find_node "${needle}")"
        if [[ -n "${coords}" ]]; then
            # shellcheck disable=SC2086
            "${ADB}" shell input tap ${coords}
            sleep 1.2
            return 0
        fi
        sleep 1
    done
    printf 'Could not find a node labelled "%s" — the UI changed, or the screen never arrived.\n' "${needle}" >&2
    return 1
}

# Fails rather than photographing whatever is in front. A capture that quietly
# grabbed the launcher is how a phone home screen ended up committed as
# android-search.png.
assert_foreground() {
    local front
    front="$("${ADB}" shell dumpsys window 2>/dev/null | grep -m1 -oE 'mCurrentFocus=[^}]*' || true)"
    if [[ "${front}" != *"${APP_ID}"* ]]; then
        printf 'The app is not in the foreground (%s) — refusing to capture.\n' "${front}" >&2
        exit 1
    fi
}

# Scrolls until the given text is on screen, or gives up loudly.
scroll_to_text() {
    local needle="$1"
    local _attempt
    for _attempt in $(seq 1 8); do
        dump_ui
        if [[ -n "$(find_node "${needle}")" ]]; then
            sleep 0.5
            return 0
        fi
        "${ADB}" shell input swipe 540 1800 540 800 400
        sleep 1
    done
    printf 'Never found "%s" while scrolling.\n' "${needle}" >&2
    return 1
}

# Empties the search field so the timeline is not still filtered when the next
# screen looks for a row to tap.
clear_search() {
    dump_ui
    local coords
    coords="$(find_node "storage")"
    if [[ -n "${coords}" ]]; then
        # shellcheck disable=SC2086
        "${ADB}" shell input tap ${coords}
        sleep 0.5
        local _i
        for _i in $(seq 1 12); do
            "${ADB}" shell input keyevent 67
        done
        "${ADB}" shell input keyevent 4
        sleep 1
    fi
}

shot() {
    local name="$1"
    sleep 1.5
    "${ADB}" exec-out screencap -p > "${OUT}/android-${name}.png"
    ok "android-${name}.png ($(du -h "${OUT}/android-${name}.png" | cut -f1))"
}

relaunch() {
    "${ADB}" shell am force-stop "${APP_ID}"
    "${ADB}" shell monkey -p "${APP_ID}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 3
}

rotate() {
    "${ADB}" shell settings put system user_rotation "$1"
    "${ADB}" shell settings put system accelerometer_rotation 0
    sleep 2
}

# Seeds the library from Fixtures/ so the screenshots show a comparison with
# something in it.
#
# Capturing live on an idle emulator produces two snapshots taken seconds apart
# with nothing between them, and a "Nothing changed" comparison is a useless
# picture of a diff tool. The fixtures are the same golden data the tests use,
# with the platform, device, and timestamps rewritten so an Android screenshot
# does not claim to be a Mac. Seeding also makes the images deterministic:
# rerunning this produces the same screens rather than whatever the emulator
# happened to be doing.
seed_library() {
    local dir="/data/data/${APP_ID}/files/diffuse/snapshots"

    python3 "${ROOT}/Scripts/seed-android-fixtures.py" "${ROOT}" "${TMP}"

    "${ADB}" shell "run-as ${APP_ID} mkdir -p files/diffuse/snapshots" >/dev/null 2>&1 || true
    local file base
    for file in "${TMP}"/seed-*.json; do
        base="$(basename "${file}")"
        "${ADB}" push "${file}" "/data/local/tmp/${base}" >/dev/null
        if ! "${ADB}" shell "run-as ${APP_ID} cp /data/local/tmp/${base} ${dir}/${base}" >/dev/null 2>&1; then
            warn "Could not seed ${base}; the screenshots will use whatever the app already had."
        fi
        "${ADB}" shell "rm -f /data/local/tmp/${base}" >/dev/null 2>&1 || true
    done
    ok "Seeded the library from Fixtures/"
}

# Removes anything the app captured itself, leaving only the seeded pair.
prune_live_snapshots() {
    local dir="files/diffuse/snapshots"
    local names
    names="$("${ADB}" shell "run-as ${APP_ID} ls ${dir}" 2>/dev/null | tr -d '\r' || true)"
    local name
    for name in ${names}; do
        case "${name}" in
            seed-*) ;;
            "") ;;
            *) "${ADB}" shell "run-as ${APP_ID} rm -f ${dir}/${name}" >/dev/null 2>&1 || true ;;
        esac
    done
    ok "Pruned live captures; only the seeded pair remains"
}

main() {
    local only="${1:-}"

    step "Capturing Android screenshots"
    printf '  adb: %s\n' "${ADB}"
    "${ADB}" wait-for-device

    # A predictable status bar keeps the diffs about the app, not the clock.
    "${ADB}" shell settings put global sysui_demo_allowed 1 >/dev/null 2>&1 || true
    "${ADB}" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null 2>&1 || true
    "${ADB}" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null 2>&1 || true
    "${ADB}" shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null 2>&1 || true
    "${ADB}" shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 >/dev/null 2>&1 || true

    rotate 0
    seed_library
    relaunch
    # The app captures on open, and that live snapshot is newer than both seeds,
    # so "Latest two" would diff a real Android capture against a rewritten Mac
    # fixture and report every capability the fixture lacks as "no longer being
    # collected". Dropping it leaves the two curated snapshots to compare
    # against each other, which is the diff worth showing.
    prune_live_snapshots
    tap "Refresh" 6 || true

    if [[ -z "${only}" || "${only}" == overview ]]; then
        tap Overview && shot overview
    fi

    if [[ -z "${only}" || "${only}" == snapshots ]]; then
        tap Snapshots && shot snapshots
    fi

    if [[ -z "${only}" || "${only}" == compare ]]; then
        tap Compare
        tap "Latest two" 8 || true
        shot compare
    fi

    if [[ -z "${only}" || "${only}" == settings ]]; then
        tap Settings && shot settings
    fi

    # The search field lives on the snapshots screen. Typing through adb's
    # keyboard is what put a launcher home screen in this file last time: the
    # keystrokes went somewhere else entirely. Tapping the field first, then
    # asserting the app is still foreground, catches that.
    if [[ -z "${only}" || "${only}" == search ]]; then
        tap Snapshots
        tap "Search snapshots and observations" 8 || true
        "${ADB}" shell input text "storage"
        sleep 2
        assert_foreground
        shot search
        "${ADB}" shell input keyevent 4
        clear_search
    fi

    if [[ -z "${only}" || "${only}" == snapshot-detail ]]; then
        if tap Snapshots && tap "After the Node upgrade" 8; then
            assert_foreground
            shot snapshot-detail
            "${ADB}" shell input keyevent 4
        fi
    fi

    # The settings screen carries three sections that ship as their own images.
    # Each is reached by scrolling rather than by a tab, so scroll_to_text walks
    # down until the heading is on screen and fails loudly if it never is.
    if [[ -z "${only}" || "${only}" == capabilities ]]; then
        relaunch
        tap Settings
        scroll_to_text "CAPABILITIES"
        assert_foreground
        shot capabilities
    fi

    if [[ -z "${only}" || "${only}" == privacy ]]; then
        relaunch
        tap Settings
        scroll_to_text "PRIVACY AND EXPORT"
        assert_foreground
        shot privacy
    fi

    if [[ -z "${only}" || "${only}" == library ]]; then
        relaunch
        tap Settings
        scroll_to_text "LIBRARY"
        assert_foreground
        shot library
    fi

    if [[ -z "${only}" || "${only}" == privacy-never-collected ]]; then
        relaunch
        if tap Settings && scroll_to_text "PRIVACY AND EXPORT" && tap "Privacy ledger" 8; then
            sleep 2
            assert_foreground
            shot privacy-never-collected
            "${ADB}" shell input keyevent 4
        fi
    fi

    if [[ -z "${only}" || "${only}" == delete-all-confirmation ]]; then
        relaunch
        if tap Settings && scroll_to_text "LIBRARY" && tap "Delete all snapshots" 8; then
            sleep 2
            assert_foreground
            shot delete-all-confirmation
            "${ADB}" shell input keyevent 4
        fi
    fi

    # The remaining four live on a snapshot's own detail screen, behind the
    # Pin, Share and Delete actions in its top bar.
    if [[ -z "${only}" || "${only}" == snapshot-labelled-pinned ]]; then
        relaunch
        if tap Snapshots && tap "After the Node upgrade" 8 && tap Pin 8; then
            sleep 2
            assert_foreground
            shot snapshot-labelled-pinned
        fi
    fi

    # A system share sheet, so the foreground check is deliberately skipped:
    # the chooser belongs to Android, not to Diffuse, and that is the point of
    # the screenshot.
    if [[ -z "${only}" || "${only}" == share-chooser ]]; then
        relaunch
        if tap Snapshots && tap "After the Node upgrade" 8 && tap Share 8; then
            sleep 3
            shot share-chooser
            "${ADB}" shell input keyevent 4
        fi
    fi

    if [[ -z "${only}" || "${only}" == delete-snapshot-confirmation ]]; then
        relaunch
        if tap Snapshots && tap "After the Node upgrade" 8 && tap Delete 8; then
            sleep 2
            assert_foreground
            shot delete-snapshot-confirmation
            "${ADB}" shell input keyevent 4
        fi
    fi

    # Also a system surface: the document picker Import opens.
    if [[ -z "${only}" || "${only}" == import-picker ]]; then
        relaunch
        if tap Settings && tap "Import snapshot" 8; then
            sleep 3
            shot import-picker
            "${ADB}" shell input keyevent 4
        fi
    fi

    # Landscape variants. Rotating mid-run is cheaper than a second pass, and
    # the rotation is reset before the function returns either way.
    if [[ -z "${only}" || "${only}" == landscape ]]; then
        relaunch
        rotate 1
        tap Overview && shot overview-landscape
        tap Compare && shot compare-landscape
        tap Settings && shot settings-landscape
        rotate 0
    fi

    ok "Review ${OUT} before committing."
}

main "$@"
