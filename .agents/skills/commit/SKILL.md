---
name: commit
description: Split and describe a git commit for Diffuse. Use when the user asks to commit, or when a change should be multiple commits.
---

# Commit

Only commit when the user asked. Do not update git config, do not `--no-verify`, do not force-push main.

1. `git status`, `git diff`, `git log` (style).
2. Stage only the files that belong. Do not add `.env`, `*.p12`, `coverage/`, `Diffuse.xcodeproj/`.
3. Message: 1–2 sentences on **why**, conventional if the log already is. Pass via HEREDOC.

```bash
git commit -m "$(cat <<'EOF'
Why this change exists.

EOF
)"
```

If a hook rewrites files, make a **new** commit rather than amending unless the user asked to amend, HEAD is yours, and it is not pushed.

Capability work, fixture regeneration, and harness edits are easier to review as separate commits when the user wants that split.
