#!/usr/bin/env bash
# Reject empty or absurdly long subjects. Conventional commits are not required.
set -euo pipefail

MSG_FILE="${1:-}"
[ -n "$MSG_FILE" ] || exit 0

subject="$(sed -n '1p' "$MSG_FILE" | tr -d '\r')"

case "$subject" in
    '' | \#*)
        echo "commit-msg: empty subject" >&2
        exit 1
        ;;
esac

if [ "${#subject}" -gt 120 ]; then
    echo "commit-msg: subject longer than 120 characters" >&2
    exit 1
fi
