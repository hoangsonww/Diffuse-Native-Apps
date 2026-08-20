#!/usr/bin/env bash
# Shared git hook body. Husky and pre-commit both call this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
    printf 'pre-commit: %s\n' "$1" >&2
    exit 1
}

# Staged files only (Added / Copied / Modified).
STAGED="$(git diff --cached --name-only --diff-filter=ACM || true)"
[ -n "$STAGED" ] || exit 0

# Never commit signing material or dotenv files.
while IFS= read -r file; do
    [ -n "$file" ] || continue
    base="$(basename "$file")"
    case "$file" in
        *.p12 | *.mobileprovision | *.cer | *.p8 | *.pem)
            fail "refusing $file (signing / key material)"
            ;;
    esac
    case "$base" in
        .env | .env.local | .env.production | id_rsa | id_ed25519 | AuthKey.p8)
            fail "refusing $file (secret file)"
            ;;
    esac
    if git diff --cached -- "$file" | grep -qE 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'; then
        fail "refusing $file (looks like a private key)"
    fi
done <<<"$STAGED"

# Conflict markers in staged text.
if echo "$STAGED" | grep -q .; then
    if git diff --cached | grep -E '^\+<<<<<<<' >/dev/null; then
        fail "merge conflict markers in the index"
    fi
fi

SWIFT_FILES="$(echo "$STAGED" | grep '\.swift$' || true)"
if [ -n "$SWIFT_FILES" ]; then
    if command -v swiftformat >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        echo "$SWIFT_FILES" | tr '\n' '\0' | xargs -0 swiftformat --config "$ROOT/.swiftformat"
        echo "$SWIFT_FILES" | while IFS= read -r file; do
            [ -n "$file" ] || continue
            git add -- "$file"
        done
    else
        echo "pre-commit: swiftformat not installed; skip format (run ./Scripts/bootstrap.sh)" >&2
    fi
fi
