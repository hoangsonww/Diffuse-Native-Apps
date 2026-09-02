# ADR 0010: Server-driven surfaces, with no server

## Status

Accepted.

## Date

2026-08.

## Context

Diffuse may ship on the App Store and Play Store. Store releases are slow: a
typo in the onboarding copy, a help section that confuses people, or an
announcement worth making all wait days for review. Every mature store app
solves this with server-driven UI — the screen is described by data the app
fetches rather than by code it ships.

Diffuse cannot fetch anything. [ADR 0001](0001-local-first.md) and
[ADR 0008](0008-no-cloud-sync.md) make local-first a product guarantee, and the
Android app declares no `INTERNET` permission. Adding one is visible on the
store listing and changes what the app is.

Doing nothing has a cost too: retrofitting SDUI later means touching every
screen at exactly the moment there is release pressure.

## Decision

Build the whole SDUI runtime — schema, validator, renderer, source protocol,
fallback rules, tests — and ship it with **one source: the app bundle.**

The contract:

- A `Surface` is a versioned tree of typed nodes with properties, children, and
  named actions. It describes *content and structure only*.
- The renderer owns every visual decision. A payload supplies text and ordering;
  it never supplies colours, fonts, or spacing.
- Actions are **names**, resolved by the host against a handler map. A payload
  can ask for `capture` but cannot describe how to capture.
- **Every surface has a hand-written native fallback.** A payload that is
  missing, unreadable, built for a newer schema, aimed at a newer app version,
  or composed entirely of unknown nodes renders nothing and the native UI shows
  instead.
- Unknown node types and nodes missing required properties are pruned
  individually. Their siblings still render.
- `SurfaceSource` is the seam. `BundledSurfaceSource` is the only implementation
  wired into an app.

The apps therefore behave exactly as they did before this ADR. Nothing observable
changed; what changed is that adding a publisher later is one new `SurfaceSource`
and one line of wiring rather than a refactor of every screen.

## Alternatives considered

- **Ship a remote source now, unwired.** Rejected: dead code that looks
  load-bearing, and the networking stack would sit in the binary unused.
- **Do nothing until it is needed.** Rejected: the expensive part is not the
  transport, it is designing the contract, the fallback semantics, and the
  version gate. Doing that under release pressure is how a bad contract ships.
- **Describe whole screens, including the diff view.** Rejected: the diff view is
  driven by real snapshot data through the schema-driven path in
  [ADR 0003](0003-schema-driven-diff.md). Two competing description systems on
  one screen would be worse than either.
- **Let payloads carry styling.** Rejected: a payload that can set colours can
  make text unreadable or the app off-brand, and it defeats Dynamic Type and
  Reduce Motion. Content in, presentation owned by the app.
- **Let payloads carry behaviour** (expressions, scripts). Rejected outright:
  that turns a data channel into an execution channel.

## Consequences

- Adding a remote publisher is a deliberate, reviewable decision with a known
  cost: an `INTERNET` permission on Android, a privacy-policy update, an
  amendment to this ADR and to ADR 0001/0008, and a cache/staleness policy. The
  code cost is one type.
- The surface vocabulary is a compatibility surface of its own. Adding a node
  type is additive; changing one is a `schemaVersion` bump.
- A published payload is untrusted input and is validated like any other.
- The bundled payloads are validated in CI, so a broken default cannot ship.
