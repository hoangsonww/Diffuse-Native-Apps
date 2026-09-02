---
name: native-apps
description: Change Mac, iOS, iPad, or Watch UI that sits on DiffuseUI. Use when a screen, widget, complication, or menu-bar extra is involved.
---

# Native apps

Four apps, one `DiffuseUI`. Platform code only for platform mechanisms (menu bar extra, widgets, complications, BGAppRefresh, Watch refresh).

- No per-capability screens. Lists, inspectors, and search are generic on schema.
- iPad regular width always shows three columns (`IPadRootView.threeColumnWorkspace`).
- Mac Snapshots inspector auto-selects the latest snapshot.
- Preferences (`DiffusePreferences`) already cover retention, redaction, schedule, search.
- Unsigned CI builds: never add a development team to `project.yml`.

Build and run without opening Xcode or looking up a simulator UDID:

```bash
make ios-run      # DiffuseiOS on an iPhone simulator
make ipados-run   # DiffuseiPadOS on an iPad simulator
make watch-run    # DiffuseWatch on a watch simulator
make mac-run      # DiffuseMac on this machine
make apple-devices
```

Each resolves and boots the right device family. Pin one with `DIFFUSE_SIMULATOR_ID`. Use these rather than calling `xcrun` or `xcodebuild` bare; `Scripts/apple.sh` handles project generation, device resolution, install, and launch.

Read `Documentation/adr/0006-four-native-apps.md` and `Apps/AGENTS.md`.
