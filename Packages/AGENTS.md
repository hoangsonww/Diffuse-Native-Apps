# Packages

Domain engine. No UIKit, no AppKit, no third-party Swift packages.

Product map: `Documentation/README.md`, then `Documentation/Architecture.md`. Adding an observation: `Documentation/CapabilityGuide.md`.

```
DiffuseModels → DiffuseDiff / DiffuseStorage / DiffuseCapabilities
             → DiffuseCore → DiffuseCollectors / DiffuseUI / diffuse-dev
```

- Adding a capability must not edit the diff engine, store, search, export, or app screens. Use skill `add-capability`.
- Collectors live in `DiffuseCollectors` and register per platform.
- `./Scripts/crosscheck.sh ios` and `watchos` must keep compiling.
- Package-local tests sit next to sources (`Packages/<Name>/Tests`). Cross-cutting suites live in `/Tests`.
