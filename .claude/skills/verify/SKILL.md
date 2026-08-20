---
name: verify
description: Run Diffuse's health check (format, tests, SDK cross-check, unsigned app builds). Use before claiming a change is done, after touching Packages, Apps, Tools, or Tests, or when the user asks if the checkout is healthy.
---

# Verify

From the repository root on **macOS with Xcode**:

```bash
./Scripts/format.sh
swift test --parallel
```

Full gate CI uses:

```bash
./Scripts/verify.sh
```

A healthy checkout prints `Diffuse is healthy.`

Touched domain or tests? Prefer `./Scripts/coverage.sh` so the llvm-cov report is fresh.

Do not skip a failing golden fixture by editing `Fixtures/` until the expected diff is understood. Do not add CodeQL or other scanners.

Docker and the Dev Container cannot run this skill — they have no Xcode.
