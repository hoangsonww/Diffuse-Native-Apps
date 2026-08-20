# Agent skills

Canonical skill tree for every coding agent (Claude Code, Codex, Cursor, Gemini, Copilot).

Each folder is `<name>/SKILL.md` with a third-person YAML `description`. Agents load a skill when that description matches the task.

`.claude/skills/` is a copy of this tree so Claude Code auto-discovers the same files. Edit here, then:

```bash
rm -rf .claude/skills && mkdir -p .claude/skills && cp -R .agents/skills/. .claude/skills/
```

Procedural workflows belong in skills, not in the root `AGENTS.md`. Product and engineering prose lives in `Documentation/` (`Documentation/README.md` is the index).
