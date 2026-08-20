@AGENTS.md

# Diffuse — Claude Code

The contract for every agent is `AGENTS.md`. Product docs start at `Documentation/README.md`. This file is Claude-only wiring.

- Skills: `.claude/skills/` (mirrors `.agents/skills/`)
- Hooks: `.claude/hooks/` (format Swift after edits; block signing material; remind to test on stop)
- Settings: `.claude/settings.json`
- Subagents: `.claude/agents/`

Do not add CodeQL, Super-Linter, or other noisy static scanners. Do not put signing identities in the tree.
