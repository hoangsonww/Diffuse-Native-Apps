---
name: privacy
description: Classify collected fields, apply export redaction, and keep the generated privacy ledger truthful. Use when adding properties, changing RedactionPolicy, or touching export/privacy UI.
---

# Privacy

Local-first. Nothing leaves the device unless the user exports. No account, no telemetry.

## Classification

| Level | Meaning |
|---|---|
| `public` | Safe to share (OS version) |
| `local` | Mildly identifying, kept on device |
| `sensitive` | Identifies the user or environment (SSID, repo path) |
| `restricted` | Never collected, or always stripped on export |

`RedactionPolicy.none` still redacts `restricted`. `standard` (default) redacts `sensitive`+. `strict` redacts `local`+.

Redaction is a **copy**. `Snapshot.redacted` must not mutate the stored snapshot.

## Checks

- New fields have a classification on the descriptor.
- `PrivacyLedger.neverCollected` stays a design commitment; do not silently delete lines.
- Export paths (`SnapshotService.exportSnapshot/Diff/Report`) apply a policy.
- Tests: `Tests/Domain/PrivacyAndRedactionTests.swift` and redaction invariants.

Read `Documentation/adr/0007-privacy-classification.md` and `Documentation/Privacy.md`.
