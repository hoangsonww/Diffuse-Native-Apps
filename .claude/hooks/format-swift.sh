#!/usr/bin/env bash
# Claude Code PostToolUse: format a Swift file that was just written.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

if ! command -v swiftformat >/dev/null 2>&1; then
    exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CONFIG="$ROOT/.swiftformat"

python3 - "$CONFIG" <<'PY'
import json, os, subprocess, sys

config = sys.argv[1]
raw = sys.stdin.read()
if not raw.strip():
    raise SystemExit(0)
try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)

path = (
    payload.get("tool_input", {}).get("file_path")
    or payload.get("tool_input", {}).get("path")
    or ""
)
if not path.endswith(".swift"):
    raise SystemExit(0)
if not os.path.isfile(path):
    raise SystemExit(0)

subprocess.run(["swiftformat", path, "--config", config], check=False)
PY
