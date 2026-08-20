#!/usr/bin/env bash
# Claude Code PreToolUse: refuse writes to signing material and dotenv secrets.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

python3 - <<'PY'
import json, os, sys

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
base = os.path.basename(path)
blocked_ext = (".p12", ".mobileprovision", ".cer", ".p8", ".pem")
blocked_name = {".env", "AuthKey.p8", "id_rsa", "id_ed25519"}

if path.endswith(blocked_ext) or base in blocked_name:
    print(f"Refusing to write signing or secret file: {path}", file=sys.stderr)
    raise SystemExit(2)
if base.startswith(".env") and base != ".env.example":
    print(f"Refusing to write {path}; use .env.example", file=sys.stderr)
    raise SystemExit(2)
PY
