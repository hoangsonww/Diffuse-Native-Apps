# Architecture decision records

Append-only. Newest number is next. When a decision changes, write a new ADR that **supersedes** the old one; do not edit history until it says the opposite of what we shipped.

Copy [template.md](template.md) for a new record (Status, Date, Context, Decision, Alternatives considered, Consequences, Related). When a decision changes, write a **new** ADR that supersedes the old one — do not edit an Accepted ADR until it says the opposite of what we shipped.

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-local-first.md) | Local-first | Accepted |
| [0002](0002-capability-driven.md) | Capability-driven architecture | Accepted |
| [0003](0003-schema-driven-diff.md) | Schema-driven diff | Accepted |
| [0004](0004-no-third-party-deps.md) | No third-party Swift dependencies | Accepted |
| [0005](0005-generated-unsigned.md) | Generated Xcode project, unsigned CI | Accepted |
| [0006](0006-four-native-apps.md) | Four genuine native apps | Accepted |
| [0007](0007-privacy-classification.md) | Privacy classification on every field | Accepted |
| [0008](0008-no-cloud-sync.md) | No cloud sync | Accepted |
| [0009](0009-native-android.md) | Native Kotlin Android app with fixture compatibility | Accepted |
| [0010](0010-server-driven-surfaces.md) | Server-driven surfaces, with no server | Accepted |
