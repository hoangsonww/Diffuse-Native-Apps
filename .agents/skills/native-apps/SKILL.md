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

Read `Documentation/adr/0006-four-native-apps.md` and `Apps/AGENTS.md`.
