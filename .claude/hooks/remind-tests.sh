#!/usr/bin/env bash
# Claude Code Stop: remind the agent to run tests before claiming done.
set -euo pipefail

cat <<'EOF'
Before finishing a code change: run ./Scripts/format.sh and swift test --parallel (or ./Scripts/coverage.sh if Packages/ or Tests/ changed). Do not add CodeQL, third-party Swift packages, or signing material. Do not weaken Fixtures/ to pass a test.
EOF
