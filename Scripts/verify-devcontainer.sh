#!/usr/bin/env bash
#
# Builds the toolbox image and proves the toolchain inside it actually works,
# rather than only proving the Dockerfile parses.
#
# The container covers the docs, hooks, landing page, and the full Android
# build. The Apple apps and `swift test` cannot be containerised: Xcode is
# macOS-only and its licence forbids redistribution.
#
# Usage:
#   Scripts/verify-devcontainer.sh            # toolchain checks only (fast)
#   Scripts/verify-devcontainer.sh --build    # also build the Android app

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$ROOT/Scripts/lib.sh"

RUN_BUILD=0
case "${1:-}" in
    "") ;;
    --build) RUN_BUILD=1 ;;
    *) printf 'Usage: %s [--build]\n' "$0" >&2; exit 2 ;;
esac

require_command docker

IMAGE_TAG="diffuse-dev:verify"

step "Building the toolbox image"
docker build --platform=linux/amd64 -f "$ROOT/Dockerfile" -t "$IMAGE_TAG" "$ROOT"

step "Verifying the toolchain inside the container"
# Deliberately a login shell (-l): /etc/profile resets PATH and discards the
# Dockerfile's ENV PATH, so a non-login shell would pass while
# `docker compose exec dev bash` — what contributors actually get — fails.
docker run --rm --platform=linux/amd64 "$IMAGE_TAG" bash -lc '
set -e
fail=0
check() {
    if eval "$2" >/dev/null 2>&1; then
        printf "  ok       %-14s %s\n" "$1" "$3"
    else
        printf "  MISSING  %-14s %s\n" "$1" "$3"
        fail=1
    fi
}
check node         "node --version"        "landing page and hooks"
check npm          "npm --version"         "git hooks"
check git          "git --version"         "source control"
check make         "make --version"        "project command surface"
check shellcheck   "shellcheck --version"  "shell linting (required by CI)"
check jq           "jq --version"          "JSON tooling"
check python3      "python3 --version"     "icon generation"
check java         "java -version"         "Gradle and AGP"
check javac        "javac -version"        "Java compiler"
check adb          "adb --version"         "device control"
check sdk-platform "test -d $ANDROID_HOME/platforms/android-36"  "Android SDK 36"
check build-tools  "test -d $ANDROID_HOME/build-tools/35.0.0"    "build-tools 35.0.0"
printf "\n  java:         %s\n" "$(java -version 2>&1 | head -1)"
printf "  JAVA_HOME=%s\n" "$JAVA_HOME"
printf "  ANDROID_HOME=%s\n" "$ANDROID_HOME"
exit $fail
'
ok "toolchain"

if [ "$RUN_BUILD" -eq 1 ]; then
    step "Building the Android app inside the container"
    printf '  Using an isolated copy so the host build directory is not shared.\n'

    WORKDIR="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$WORKDIR'" EXIT
    git -C "$ROOT" archive --format=tar HEAD | tar -x -C "$WORKDIR"

    # Carry over the uncommitted Gradle toolchain files when present, so the
    # container exercises the configuration under test rather than HEAD's.
    for path in \
        Android/gradle/wrapper/gradle-wrapper.properties \
        Android/gradle/gradle-daemon-jvm.properties \
        Android/settings.gradle.kts
    do
        [ -f "$ROOT/$path" ] && cp "$ROOT/$path" "$WORKDIR/$path"
    done

    docker run --rm --platform=linux/amd64 -v "$WORKDIR:/work" -w /work "$IMAGE_TAG" bash -lc '
        cd Android && ./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug
        ls -lh app/build/outputs/apk/debug/*.apk
    '
    ok "Android build"
fi

step "Toolbox verified"
printf '  Covered: docs, hooks, landing page, and the Android build.\n'
printf '  Not covered: the Apple apps, which require Xcode on a macOS host.\n'
