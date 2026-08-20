# Documentation

This folder is the product and engineering record for Diffuse: why the system looks the way it does, how to extend it, and what is deliberately out of scope.

If you are new, read in this order:

1. [Architecture](Architecture.md) — layers, data flow, what is *not* here
2. [Glossary](Glossary.md) — the words the rest of these pages use
3. [ADRs](adr/) — the decisions those layers encode
4. The guide for the work you are about to do (capability, collector, tests, apps, CLI, repository)

The root [README](../README.md) is the public face. [AGENTS.md](../AGENTS.md) is the contract for coding agents. Procedural workflows live in [`.agents/skills/`](../.agents/skills/).

## Guides

| Document | Read when |
| --- | --- |
| [Architecture](Architecture.md) | You need the map of packages and the capture → diff → UI path |
| [Glossary](Glossary.md) | A term in another page is unfamiliar |
| [Capability guide](CapabilityGuide.md) | You are adding something Diffuse can observe |
| [Collector guide](CollectorGuide.md) | You are writing or debugging a collector |
| [Snapshot schema](SnapshotSchema.md) | You are changing serialized shape, descriptors, or fixtures |
| [Diff engine](DiffEngine.md) | Comparison, identity matching, severity, or clustering looks wrong |
| [Storage](Storage.md) | Save/load, query, retention, or on-disk layout |
| [Privacy](Privacy.md) | Classification, redaction, export, threat model |
| [Apps](Apps.md) | Mac / iOS / iPad / Watch UI, widgets, scheduling |
| [CLI](CLI.md) | `diffuse-dev` commands and how they reuse the domain engine |
| [Testing](Testing.md) | Where a test belongs, fixtures, coverage, common pitfalls |
| [Repository](Repository.md) | Scripts, Makefile, CI, Docker, hooks, tree layout |

## Architecture decision records

Numbered, append-only. Status is **Accepted** unless a later ADR supersedes it. Do not silently reverse one of these in a “small feature.” New records copy [adr/template.md](adr/template.md).

| ADR | Decision |
| --- | --- |
| [0001](adr/0001-local-first.md) | Snapshots never leave the device |
| [0002](adr/0002-capability-driven.md) | Observations are capabilities, not special cases |
| [0003](adr/0003-schema-driven-diff.md) | Comparison rules travel inside the snapshot |
| [0004](adr/0004-no-third-party-deps.md) | First-party Swift package graph only |
| [0005](adr/0005-generated-unsigned.md) | XcodeGen project; unsigned CI |
| [0006](adr/0006-four-native-apps.md) | Four genuine native apps, not one max-target |
| [0007](adr/0007-privacy-classification.md) | Every field is classified; redaction is on export |
| [0008](adr/0008-no-cloud-sync.md) | No iCloud, no backend, no cross-device history |

## Related files outside this folder

| Path | Role |
| --- | --- |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Setup, PR rules, tests |
| [SECURITY.md](../SECURITY.md) | Vulnerability reporting |
| [SUPPORT.md](../SUPPORT.md) | How to ask for help |
| [CHANGELOG.md](../CHANGELOG.md) | What shipped |
| [Fixtures/](../Fixtures/) | Golden snapshots and expected diffs |
| [docs/screenshots/](../docs/screenshots/) | Full-resolution UI shots used by the README |
| [Design/Icons/](../Design/Icons/) | App icon masters |
| [Landing page](../index.html) | Public marketing site (GitHub Pages) |
