---
name: coverage
description: Generate first-party Swift package coverage (llvm-cov HTML, lcov, text summary). Use when the user asks for coverage, after expanding Tests/, or before claiming test work is done.
---

# Coverage

Hermetic, first-party. Do **not** add Codecov, Coveralls, Code Climate, or similar.

```bash
./Scripts/coverage.sh
```

Writes gitignored `coverage/`:

- `summary.txt` / `summary.md` — line coverage by file
- `coverage.lcov` — for local tools
- `html/index.html` — browsable report

CI already runs this on the `test` job and uploads `coverage/` as an artifact. Open the HTML from the artifact; do not commit it.

Ignore patterns exclude `.build` and `Tests/` so the denominator is package sources.

```bash
SKIP_TEST=1 ./Scripts/coverage.sh   # rebuild the report from an existing profile
```
