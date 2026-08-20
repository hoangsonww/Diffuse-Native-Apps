---
description: Diffuse architecture, commands, and hard rules for Cursor agents
alwaysApply: true
---

Read `AGENTS.md` in the repository root before editing. Product docs: `Documentation/README.md`.

Diffuse is local-first. Four native Apple apps share a capability-driven domain engine. No cloud, no account, no telemetry, no third-party Swift packages, no signing identities in the tree.

```
Apps → DiffuseUI → DiffuseCapabilities / DiffuseCore → DiffuseModels
                                                     → DiffuseDiff
                                                     → DiffuseStorage
```

Adding a capability must not require edits to the diff engine, store, search, export, or app screens. See `Documentation/CapabilityGuide.md`.

Verify with `./Scripts/format.sh` and `swift test`. Full health check: `./Scripts/verify.sh`.

Do not add CodeQL or noisy static scanners.
