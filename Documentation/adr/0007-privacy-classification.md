# ADR 0007: Privacy classification on every field

## Status

Accepted.

## Date

2026-08.

## Context

Once a snapshot exists, someone will want to export it — a bug report, a gist, a screenshot’s worth of JSON. Collection-time “we just won’t collect sensitive things” fails as soon as an SSID is useful *on device* (you want to see that you switched networks) but harmful *off device*.

## Decision

Every property descriptor has a `PrivacyClassification`. Collection stores the real value. Export and `diffuse-dev privacy` apply a `RedactionPolicy`. `restricted` never exports, including under “full detail,” and including when the enclosing section is only `local`. Process listing is additionally opt-in at collection time.

The privacy ledger is generated from live capability metadata so it cannot drift.

## Alternatives considered

- **Collect nothing sensitive.** Rejected: then “home → office” cannot appear in a workday diff.
- **Encrypt the library.** Rejected as theatre on an unlocked Mac; FileVault already encrypts the disk. Redaction is for *sharing*, not for at-rest access control.
- **A single “private mode” boolean.** Rejected: too coarse; public OS version and restricted secrets are not the same knob.

## Consequences

- Collectors must classify; “default public” would be a footgun, so reviews should check new descriptors.
- The privacy ledger is a product feature, not a settings afterthought.
- Redaction is not encryption and not access control. See [Privacy.md](../Privacy.md).

## Related

[0001](0001-local-first.md), [Privacy.md](../Privacy.md).
