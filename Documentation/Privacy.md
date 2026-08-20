# Privacy

Diffuse is local-first. If a snapshot is on your device, it is because that device captured it. There is no Diffuse account, no Diffuse cloud, and no telemetry.

This document is the contract. The generated **privacy ledger** in the app and `diffuse-dev privacy` is the live inventory — it is built from capability metadata, so it cannot drift when a collector is added. Hand-written marketing copy is not the source of truth.

See [adr/0001-local-first.md](adr/0001-local-first.md), [adr/0007-privacy-classification.md](adr/0007-privacy-classification.md), [adr/0008-no-cloud-sync.md](adr/0008-no-cloud-sync.md), and skill `privacy`.

## Guarantees

- No account, no cloud, no crash reporter that uploads snapshots.
- GitHub is used for source and CI artifacts, not for user data.
- Export is explicit. Redaction is classification-driven.
- Import is explicit. An imported snapshot is tagged and never mistaken for a local capture.
- Widgets receive a two-integer summary, never a snapshot.

`PrivacyLedger.neverCollected` is a design commitment asserted by tests. It currently names: passwords/tokens/API keys, Keychain, SSH/GPG private keys, environment variable values including `.env` files, file contents, message/mail/photo/browsing history, location data, and anything sent off the device.

## Classifications

Every property and section carries a `PrivacyClassification`:

| Class | Meaning | Export |
| --- | --- | --- |
| `public` | OS version, model identifier | Always included |
| `local` | Device name, mildly identifying | Included by default (`standard`) |
| `sensitive` | SSID, repository path | Redacted unless the user picks full detail |
| `restricted` | Never designed to leave | **Always** redacted, including `RedactionPolicy.none` |

`RedactionPolicy`:

| Policy | Threshold (lowest class that is redacted) | UI name |
| --- | --- | --- |
| `none` | `restricted` only | Full detail |
| `standard` (default) | `sensitive` and above | Standard |
| `strict` | `local` and above | Strict |

A stricter policy never reveals a value a looser policy hid. Redaction is a **copy**: `Snapshot.redacted` does not mutate the library. Restricted properties on a local section are still stripped — the engine walks descriptors, not only section-level privacy.

Primary properties that are redacted also redact the entity display name (`‹redacted›`) so a “HomeNet” SSID does not leak through the title.

## Collection rules

- **No secrets.** No tokens, no Keychain, no file contents, no clipboard, no `.env` values.
- **Processes** are opt-in (`isEnabledByDefault: false`).
- **Git** is metadata: branch, dirty, ahead/behind, remote host. Not file names, not diffs, not commit messages, not hunks.
- **Wi-Fi** is the joined network’s name, and only with Location on macOS. Diffuse does not read coordinates, BSSID, or nearby networks. Location is used solely because CoreWLAN/SSID APIs require it.
- **Developer tools** record tool name + version, not project files.
- **Repo watch list** is paths the user added. Those paths are `sensitive`.

## macOS sandbox

The Mac app is **not sandboxed**. Collecting developer tools means spawning `git` and `node --version`. The App Sandbox forbids that without a temporary-exception entitlement for every binary, which is neither honest nor maintainable. This is documented rather than papered over.

iOS, iPadOS, and watchOS run in their platform sandboxes as normal apps. They do not shell out.

## Widgets and app groups

The change-count widget/complication runs in another process. The app writes `changeCount`, `peakSeverity`, and `capturedAt` into an app group. That payload is not a snapshot and contains no sensitive properties.

App groups:

- `group.com.diffuse.watch`
- `group.com.diffuse.ios`
- `group.com.diffuse.ipados`

Without a signed build the container is unavailable; widgets show empty rather than crashing. That is expected for unsigned CI artifacts ([adr/0005](adr/0005-generated-unsigned.md)).

## Export and the CLI

Apps and `diffuse-dev` share `SnapshotService.exportSnapshot` / `exportDiff` / `exportReport` and `ReportRenderer`. There is no second template in an app target. Default redaction is `.standard`. Reports end with a footer that the data did not leave the device *as part of generation* — the user still chose to paste the file.

`swift run diffuse-dev snapshot out.json` is an explicit file write of a **full** (unredacted) snapshot. Treat it like an export you have not redacted yet; do not attach it to a public issue.

The privacy screen’s “what would this policy redact?” list comes from `PrivacyLedger.redactedCapabilities(under:)`.

## Threat model (honest)

Diffuse does **not** protect you from someone with your unlocked device and your user account. Full Disk Access, an unlocked session, and backups of Application Support can all read snapshots.

It **does** protect you from:

- Accidental sharing (classification + redaction on export)
- Silent cloud copies (there are none)
- Collectors that would otherwise vacuum a home directory
- A laptop that wakes every minute filling a timeline with near-identical snapshots (scheduler floor + skip-if-unchanged)
- A restricted field slipping out because the section was merely `local`

Report vulnerabilities privately: [SECURITY.md](../SECURITY.md).
