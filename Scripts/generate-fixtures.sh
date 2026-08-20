#!/usr/bin/env bash
#
# Regenerates the checked-in snapshot and diff fixtures.
#
# The fixtures are the contract the integration tests assert against. After
# changing a collector schema or the fixture generator, run this and review
# the resulting diff before committing.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift run --package-path "$ROOT" diffuse-dev generate-fixture
echo "Fixtures written to Fixtures/"
