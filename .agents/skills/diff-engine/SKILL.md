---
name: diff-engine
description: Change comparison rules, severity, identity matching, or change correlation. Use when diffs look wrong, a capability needs a new ComparisonRule, or clustering/timeline is involved.
---

# Diff engine

The engine is generic. Capabilities declare `ComparisonRule` and `ChangeSeverity` on property descriptors. Do not add `if capability == .docker` branches.

- `ValueComparator` is the only place two readings are judged "the same".
- Identity matching is `EntityIdentity` (normalized value + kind + optional scope). Path identities use `EntityIdentity.path`.
- `diff(A, A)` is empty. Reverse diffs swap added/removed counts. Property tests in `Packages/DiffuseDiff/Tests` and `Tests/Invariants` guard this.
- Severity can escalate on a major version jump; do not special-case tools by name.
- Correlation (`ChangeCorrelator`) groups by time window, not by inference.

Read `Documentation/DiffEngine.md` and `Documentation/adr/0003-schema-driven-diff.md`.

After changes: `swift test --filter DiffuseDiffTests` and `swift test --filter DiffuseInvariantTests`.
