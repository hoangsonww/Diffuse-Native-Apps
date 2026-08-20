---
name: crosscheck
description: Type-check shared packages against the iOS and watchOS SDKs. Use after editing core packages, before verify, or when CI crosscheck fails.
---

# Cross-check

Core packages must compile for iOS and watchOS even when you developed on macOS.

```bash
./Scripts/crosscheck.sh ios
./Scripts/crosscheck.sh watchos
```

Failures usually mean an AppKit/UIKit import leaked into `Packages/Diffuse*` core, or an API that does not exist on that SDK.

Do not skip this to land a Mac-only type in Core. Put it in the app target or `DiffuseCollectors` behind the right registry.
