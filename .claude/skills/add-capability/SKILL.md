---
name: add-capability
description: Add something Diffuse can observe on a device (typed capability, collector, registry line, and tests). Use when the user wants a new collector, observable, or capability ID.
---

# Add a capability

Read in order: `Documentation/CapabilityGuide.md`, `Documentation/CollectorGuide.md`, `Documentation/adr/0002-capability-driven.md`.

## Create

1. Capability ID and schema in `Packages/DiffuseCapabilities` (or the catalog the guide points at).
2. A collector in `Packages/DiffuseCollectors` for each platform that can actually observe it. Do not pretend a Watch can enumerate Mac apps.
3. A registry line on each platform that should expose it.
4. Tests with a **fake** — never require live hardware in CI. Put API tests in `Tests/Domain` if the new type is public.

## Do not touch

Adding a capability must **not** require edits to the diff engine, snapshot store, search, export, or app screens. If you are adding a SwiftUI view for one capability, stop.

## Privacy

Every collected field needs `public` / `local` / `sensitive` / `restricted`. Restricted fields should not be collected. See skill `privacy`.

```bash
swift test --parallel
./Scripts/format.sh
```

If a golden fixture schema changed, skill `fixtures`.
