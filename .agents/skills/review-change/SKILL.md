---
name: review-change
description: Review a Diffuse diff against architecture, privacy, fixtures, dependencies, and CI constraints. Use after a non-trivial edit or when the user asks for a review.
---

# Review a change

Read `AGENTS.md` and `Documentation/Architecture.md`. Inspect `git diff`.

Report only problems that matter, one line each:

- `architecture:` dependency direction, or a new app screen for something that should be a capability
- `privacy:` collected field classification, redaction, or something that leaves the device
- `deps:` a third-party Swift package
- `signing:` identities, team IDs, provisioning
- `fixtures:` golden files weakened to pass a test
- `ci:` CodeQL / noisy scanners / CI that can no longer produce unsigned artifacts
- `tests:` behaviour changed with no Domain or Invariant coverage

Skip formatting nits. SwiftFormat is the formatter. If there are no findings, say so in one sentence.

Dispatch `.claude/agents/reviewer.md` for a second pass on large diffs.
