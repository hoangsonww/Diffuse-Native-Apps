#!/usr/bin/env bash

# One version, five places that have to agree.
#
# The release tag, the Android manifest, the Apple project, and the landing
# page's structured data all carry the version independently. They drifted:
# v1.1.0 shipped on GitHub while every file in the tree still said 1.0.0, so
# the Play/Store metadata, the About screens, and the schema.org card were all
# describing a release that no longer existed.
#
# `VERSION` at the repository root is now the only place a human edits. This
# script propagates it and, more importantly, `check` fails CI when something
# has drifted again.
#
# Usage:
#   Scripts/version.sh              # print the current version
#   Scripts/version.sh check        # verify every file agrees (CI)
#   Scripts/version.sh sync         # rewrite the derived files from VERSION
#   Scripts/version.sh set 1.2.0    # write VERSION, then sync
#   Scripts/version.sh bump patch   # patch | minor | major, then sync

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly VERSION_FILE="${ROOT}/VERSION"
readonly GRADLE="${ROOT}/Android/app/build.gradle.kts"
readonly PROJECT="${ROOT}/project.yml"
readonly LANDING="${ROOT}/index.html"
readonly CITATION="${ROOT}/CITATION.cff"

current() {
    tr -d '[:space:]' < "${VERSION_FILE}"
}

valid() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Android wants a monotonic integer as well as the human string. Deriving it
# from the semantic version keeps them in step without a second thing to edit:
# 1.2.3 -> 10203, which stays ordered as long as minor and patch stay under 100.
version_code() {
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    printf '%d' $((major * 10000 + minor * 100 + patch))
}

sync_files() {
    local version="$1"
    local code
    code="$(version_code "${version}")"

    python3 - "${version}" "${code}" "${GRADLE}" "${PROJECT}" "${LANDING}" "${CITATION}" <<'PY'
import pathlib
import re
import sys

version, code, gradle, project, landing, citation = sys.argv[1:7]

def rewrite(path: str, pattern: str, replacement: str) -> bool:
    file = pathlib.Path(path)
    text = file.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match for {pattern!r}, found {count}")
    if updated != text:
        file.write_text(updated, encoding="utf-8")
        return True
    return False

changed = []
if rewrite(gradle, r'versionName = "[^"]*"', f'versionName = "{version}"'):
    changed.append("Android versionName")
if rewrite(gradle, r"versionCode = \d+", f"versionCode = {code}"):
    changed.append("Android versionCode")
if rewrite(project, r'MARKETING_VERSION: "[^"]*"', f'MARKETING_VERSION: "{version}"'):
    changed.append("MARKETING_VERSION")
if rewrite(landing, r'"softwareVersion": "[^"]*"', f'"softwareVersion": "{version}"'):
    changed.append("landing page structured data")
# CITATION.cff also carries a release date; a version with last release's date
# is its own kind of wrong, so both move together.
if rewrite(citation, r"^version: .*$", f"version: {version}"):
    changed.append("CITATION version")
if rewrite(citation, r'^date-released: ".*"$', f'date-released: "{__import__("datetime").date.today().isoformat()}"'):
    changed.append("CITATION date")

print("  " + ("updated: " + ", ".join(changed) if changed else "already in step"))
PY
}

# Prints "file expected actual" for anything that disagrees.
mismatches() {
    local version="$1"
    local code
    code="$(version_code "${version}")"

    python3 - "${version}" "${code}" "${GRADLE}" "${PROJECT}" "${LANDING}" "${CITATION}" <<'PY'
import pathlib
import re
import sys

version, code, gradle, project, landing, citation = sys.argv[1:7]
checks = [
    ("Android versionName", gradle, r'versionName = "([^"]*)"', version),
    ("Android versionCode", gradle, r"versionCode = (\d+)", code),
    ("MARKETING_VERSION", project, r'MARKETING_VERSION: "([^"]*)"', version),
    ("landing softwareVersion", landing, r'"softwareVersion": "([^"]*)"', version),
    ("CITATION version", citation, r"^version: (.*)$", version),
]

bad = 0
for label, path, pattern, expected in checks:
    text = pathlib.Path(path).read_text(encoding="utf-8")
    found = re.search(pattern, text, flags=re.MULTILINE)
    actual = found.group(1) if found else "<missing>"
    if actual != expected:
        print(f"  {label}: expected {expected}, found {actual}")
        bad += 1
sys.exit(1 if bad else 0)
PY
}

main() {
    local command="${1:-print}"

    if [[ ! -f "${VERSION_FILE}" ]]; then
        warn "No VERSION file at ${VERSION_FILE}"
        return 1
    fi

    local version
    version="$(current)"
    if ! valid "${version}"; then
        warn "VERSION contains '${version}', which is not MAJOR.MINOR.PATCH"
        return 1
    fi

    case "${command}" in
        print)
            printf '%s\n' "${version}"
            ;;
        check)
            step "Version consistency"
            if mismatches "${version}"; then
                ok "Everything agrees on ${version}"
            else
                warn "Files disagree with VERSION (${version}). Run: Scripts/version.sh sync"
                return 1
            fi
            ;;
        sync)
            step "Propagating ${version}"
            sync_files "${version}"
            ok "In step with VERSION"
            ;;
        set)
            local target="${2:-}"
            valid "${target}" || { warn "Usage: $0 set MAJOR.MINOR.PATCH"; return 2; }
            printf '%s\n' "${target}" > "${VERSION_FILE}"
            step "Set ${target}"
            sync_files "${target}"
            ok "VERSION is now ${target}"
            ;;
        bump)
            local kind="${2:-patch}"
            local major minor patch
            IFS=. read -r major minor patch <<< "${version}"
            case "${kind}" in
                major) major=$((major + 1)); minor=0; patch=0 ;;
                minor) minor=$((minor + 1)); patch=0 ;;
                patch) patch=$((patch + 1)) ;;
                *) warn "Usage: $0 bump major|minor|patch"; return 2 ;;
            esac
            main set "${major}.${minor}.${patch}"
            ;;
        *)
            warn "Usage: $0 [print|check|sync|set X.Y.Z|bump major|minor|patch]"
            return 2
            ;;
    esac
}

main "$@"
