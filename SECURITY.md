# Security

Diffuse is local-first. Snapshots live on the device that captured them. There is no account, no cloud backend, and no telemetry. The threat model, classifications, and collection rules are in [Documentation/Privacy.md](Documentation/Privacy.md). Architecture decisions: [ADR 0001](Documentation/adr/0001-local-first.md), [ADR 0007](Documentation/adr/0007-privacy-classification.md), [ADR 0008](Documentation/adr/0008-no-cloud-sync.md).

## What to report

Please report vulnerabilities that would let an attacker:

- read another user’s snapshots from a shared Mac without that user’s account (for example a world-readable store path)
- exfiltrate sensitive snapshot fields through export, widgets, the CLI, logs, or a report footer despite redaction — including a `restricted` field on a merely `local` section
- execute unexpected processes via a collector or tool adapter (command injection, unsanitized arguments to `git` / `node` / Docker)
- corrupt the on-disk store so that a later open crashes, silently drops history, or mis-diffs
- bypass capability enablement to collect process lists or other opt-in data
- turn a widget or app-group file into a snapshot dump

Do **not** open a public issue for these. Open a private GitHub security advisory:

https://github.com/hoangsonww/Diffuse/security/advisories/new

Include: Diffuse version or commit, platform and OS version, steps to reproduce, impact (read / write / execute / exfiltrate), and whether any real user data was involved. Redact host names, SSIDs, and process lists from attachments.

We aim to acknowledge reports within a few days and to ship a fix on a reasonable timeline for the severity. There is no bug bounty.

## What is intentional

These are product decisions, not bugs:

- The macOS app is **not sandboxed**. Reading the developer environment means running tools such as `git` and `node --version`, which the App Sandbox forbids without a temporary-exception entitlement per binary. See [Documentation/Privacy.md](Documentation/Privacy.md).
- Process enumeration is **opt-in** and off by default.
- Git collection records metadata only (branch, ahead/behind, remote host). It never stores file names, diffs, commit messages, or file contents.
- Wi-Fi SSID collection on macOS requires Location permission. Diffuse never reads coordinates, BSSID, or nearby networks.
- Snapshots are **not encrypted at rest** beyond the OS (FileVault / device encryption). Anyone with the user’s unlocked account can read Application Support. Redaction is for *sharing*, not for at-rest access control.
- CI builds are **unsigned**. Distribution signing is configured outside this repository.
- Widgets are empty in unsigned builds because the app group container is unavailable.
- `diffuse-dev snapshot` writes a file you named. That is an explicit export, not a silent cloud copy.

## Scope

**In scope:** packages under `Packages/`, apps under `Apps/`, `Tools/diffuse-dev`, on-disk store format, export/redaction, collectors, widget payloads, CI scripts that handle snapshots.

**Out of scope:** third-party tools invoked by collectors (Homebrew, Docker, language runtimes); the security of the user’s OS account; physical access to an unlocked device; social engineering; supply-chain issues in Apple SDKs.

## Coordinated disclosure

Please give us a chance to ship a fix before posting a write-up. We will credit reporters who want to be named. Do not attach live snapshot JSON containing `sensitive` or `restricted` fields to a public gist.
