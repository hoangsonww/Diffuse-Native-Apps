Diffuse is a local-first Apple-platform product. Four native apps (macOS, iOS, iPadOS, watchOS) share one capability-driven domain engine. Snapshots never leave the device.

Before changing code, read `AGENTS.md` (and the nested `AGENTS.md` in Packages/Apps/Tests/Tools) and `Documentation/README.md`. Skills live in `.agents/skills/`.

Rules:

- No third-party Swift packages.
- No signing identities, team IDs, or provisioning profiles.
- CI produces unsigned artifacts only.
- Do not add CodeQL, Super-Linter, Scorecard, Semgrep, or similar scanners.
- Adding a capability must not require edits to the diff engine, storage, search, export, or app screens.
- Run `./Scripts/format.sh` and `swift test` before finishing.
- Do not weaken golden fixtures in `Fixtures/` to make a test pass.

Dependency direction:

```
Apps → DiffuseUI → DiffuseCapabilities / DiffuseCore → DiffuseModels
                                                     → DiffuseDiff
                                                     → DiffuseStorage
```
