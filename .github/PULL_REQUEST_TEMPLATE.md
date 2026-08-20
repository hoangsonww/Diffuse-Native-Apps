## Summary

<!-- What changed, and why. One concern per PR. Link an ADR or guide if this is architectural. -->

## Test plan

- [ ] `./Scripts/format.sh` (or the pre-commit hook) has been run
- [ ] `swift test --parallel` passes
- [ ] Touched Packages/ or Tests/? `./Scripts/coverage.sh` (or at least the relevant `--filter`). See `Documentation/Testing.md`.
- [ ] New collector or schema change includes tests (a fake is enough; no live hardware required)
- [ ] `./Scripts/generate-fixtures.sh` reviewed if a golden fixture moved — do not weaken expected diffs
- [ ] No signing identities, team IDs, or provisioning profiles
- [ ] CI can still produce **unsigned** artifacts
- [ ] No CodeQL / Super-Linter / Scorecard / Semgrep / Trivy / Sonar

## Notes

<!-- Screenshots, capability IDs, privacy classification of new fields, follow-ups. Leave blank if none. -->
