---
name: release
description: Cut an unsigned GitHub release of the four apps. Use when the user asks to release, tag, or ship artifacts.
---

# Release

CI release workflows build **unsigned** artifacts. No developer-account secrets in GitHub.

- Version lives in the places `project.yml` / CHANGELOG already use. Update `CHANGELOG.md` Unreleased → a dated section.
- Do not embed a signing identity to "make TestFlight easier" in this repo.
- Workflows: `.github/workflows/release-macos.yml`, `release-apple.yml`.
- Tags should match the changelog version.

Read `Documentation/adr/0005-generated-unsigned.md`.
