# Apps

Four native apps sharing `DiffuseUI` + the domain engine. Guide: `Documentation/Apps.md`. ADR 0006.

Platform-specific only when the platform is genuinely different (menu bar extra, widgets, complications, BGAppRefresh).

- Do not add a SwiftUI view for one capability. The UI is generic on capability metadata.
- Preferences, search, retention, redaction, and scheduling are already wired through `DiffusePreferences` / `SnapshotService`.
- iPad regular-width stays three columns (`IPadRootView.threeColumnWorkspace`).
- Signing stays unsigned in CI. No team IDs or provisioning in-tree.
- Screenshots: `Documentation/Apps.md`, `docs/screenshots/README.md`, skill `screenshots`.
