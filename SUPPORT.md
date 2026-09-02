# Support

Diffuse is a local-first device-history product. There is no hosted service to page, and snapshots never leave the device they were captured on.

## Questions about using Diffuse

- [README.md](README.md) — what the apps do
- [Documentation/README.md](Documentation/README.md) — full index
- [Documentation/Privacy.md](Documentation/Privacy.md) — what is collected and what export redacts
- [Documentation/Apps.md](Documentation/Apps.md) — Mac / iPhone / iPad / Watch / Android behaviour
- [Documentation/Glossary.md](Documentation/Glossary.md) — product vocabulary
- [Documentation/Troubleshooting.md](Documentation/Troubleshooting.md) — a build, test, emulator, or hook that is failing
- [Documentation/TechStack.md](Documentation/TechStack.md) — every technology in the repository
- Open a GitHub issue using the Bug, Feature, or Capability template

### Common points

| Question | Answer |
| --- | --- |
| Where are snapshots stored? | Application Support / `Diffuse/` on Apple devices; the app-private files directory on Android. One JSON file per snapshot plus rebuildable `index.json`. See [Storage](Documentation/Storage.md). |
| Can I see my Mac history on my iPhone or Android? | No. Each device is a closed history ([ADR 0008](Documentation/adr/0008-no-cloud-sync.md)). Export if you need a copy. |
| Does Android need Internet? | No `INTERNET` permission. Connectivity is observed via `ACCESS_NETWORK_STATE`. Snapshots are excluded from backup. |
| Why is the Mac app not sandboxed? | Developer-tool collectors spawn `git` / `node --version`. Documented in [Privacy.md](Documentation/Privacy.md). |
| Why are widgets empty in a CI / unsigned build? | No app-group container without a signed identity. Expected. The extension still compiles. |
| How do I dump a snapshot from the terminal? | `swift run diffuse-dev snapshot` — [CLI](Documentation/CLI.md). That writes a file you name; it does not touch the app library. |
| Why did a scheduled capture not save? | Skip-if-unchanged (automatic captures only) or the 15-minute floor. Manual capture always persists. |
| Why did retention keep an old snapshot? | Pinned or labelled snapshots are protected by default. The newest snapshot is never deleted. |
| Why does export still hide a field on “full detail”? | `restricted` never leaves, including `RedactionPolicy.none`. |
| Process list is empty. | It is opt-in (`isEnabledByDefault: false`). Enable it in Capabilities / Settings. |
| Wi-Fi name is missing on Mac. | Grant Location. Diffuse uses it solely for the SSID; coordinates are not read. |
| How do I know the privacy screen is complete? | It is generated from live capability metadata (`PrivacyLedger`). `swift run diffuse-dev privacy` prints the same contract. |

## Questions about contributing

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [Documentation/Testing.md](Documentation/Testing.md)
- [Documentation/Repository.md](Documentation/Repository.md)
- [AGENTS.md](AGENTS.md) if you are an agent (or using one)

## Security

Do not open a public issue. See [SECURITY.md](SECURITY.md) and
https://github.com/hoangsonww/Diffuse-Native-Apps/security/advisories/new
