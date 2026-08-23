# Screenshots

Taken from the running native apps on **20 Aug 2026**; the iPad set was retaken on **22 Aug 2026** after the workspace column alignment fix, and the Watch set on **23 Aug 2026** after the glance rework, the wrapping severity chips, and the pushed-screen background fix. Replace these PNGs from the live apps when UI changes. Do not invent marketing images. Skill: `screenshots`. App icons are a different pipeline: [Design/Icons/README.md](../../Design/Icons/README.md).

The iPhone shots are full-device framebuffers (1206×2622). A missing launch screen previously letterboxed the UI to a 320×480 compatibility size; that is fixed.

`landing-*.png` at the repository root are local Playwright QA captures of the marketing site, and `Android/screenshots/` holds raw emulator verification passes. Both are gitignored on purpose and are not product screenshots — do not check them in. This directory is the only versioned gallery.

## How they were taken

- **iPhone, iPad, Watch** — Simulator framebuffers (`simctl io screenshot`). Pass the screen name with `SIMCTL_CHILD_DIFFUSE_SCREENSHOT=…` so `simctl launch` actually forwards the environment; extra launch arguments become argv, not env.
- **macOS** — `DIFFUSE_SCREENSHOT` plus `DIFFUSE_WRITE_SCREENSHOT` (`ScreenshotWriter`). Launch via `open --env` / the debug binary so the process has a window.
- **Android** — Pixel 6 API 34 emulator, debug APK, captured with `adb exec-out screencap -p`. Raw QA passes are written to the gitignored `Android/screenshots/`; the curated set that ships lives here.

Seed the Apple library from `Fixtures/snapshots/` (rewrite timestamps, device identity, and platform if the UI would otherwise look empty). Avoid auto-capture on open while shooting: the 15-minute scheduler floor plus `capturesOnSystemEvents` will otherwise insert a live snapshot.

`DIFFUSE_SCREENSHOT` values the apps honour:

| App | Values |
| --- | --- |
| Mac | `overview`, `snapshots`, `compare`, `capabilities`, `privacy`, `search`, `snapshot-detail`, `entity-detail`, `named-snapshot` |
| iPhone | `overview`, `timeline`, `compare`, `settings`, `capabilities`, `privacy`, `search`, `snapshot-detail`, `entity-detail` |
| iPad | workspace (default), `privacy`, `capabilities`, `settings`, `search`, `snapshot-detail`, `entity-detail`, `change-detail` |
| Watch | glance (default), `settings`, `snapshot-detail`, `change-detail` |

On Mac, `compare` also triggers `model.compareLatest()`.

## Android

| Overview | Snapshots |
| --- | --- |
| ![Android overview](android-overview.png) | ![Android snapshots](android-snapshots.png) |
| Compare | Settings |
| ![Android compare](android-compare.png) | ![Android settings](android-settings.png) |
| Snapshot detail | Search |
| ![Android snapshot](android-snapshot-detail.png) | ![Android search](android-search.png) |
| Privacy | Capabilities |
| ![Android privacy](android-privacy.png) | ![Android capabilities](android-capabilities.png) |
| Library | Share |
| ![Android library](android-library.png) | ![Android share](android-share-chooser.png) |

Also: [never collected](android-privacy-never-collected.png), [import picker](android-import-picker.png), [delete all](android-delete-all-confirmation.png), [delete one](android-delete-snapshot-confirmation.png), [labelled + pinned](android-snapshot-labelled-pinned.png), [overview landscape](android-overview-landscape.png), [compare landscape](android-compare-landscape.png), [settings landscape](android-settings-landscape.png).

## iPhone

| Overview | Snapshots |
| --- | --- |
| ![iOS Overview](ios-overview.png) | ![iOS Snapshots](ios-timeline.png) |
| Compare | Settings |
| ![iOS Compare](ios-compare.png) | ![iOS Settings](ios-settings.png) |
| Privacy | Capabilities |
| ![iOS Privacy](ios-privacy.png) | ![iOS Capabilities](ios-capabilities.png) |
| Search | Snapshot |
| ![iOS Search](ios-search.png) | ![iOS Snapshot](ios-snapshot-detail.png) |

![iOS entity](ios-entity-detail.png)

## iPad

| Workspace | Privacy |
| --- | --- |
| ![iPad workspace](ipados-workspace.png) | ![iPad privacy](ipados-privacy.png) |
| Capabilities | Settings |
| ![iPad capabilities](ipados-capabilities.png) | ![iPad settings](ipados-settings.png) |
| Search | Snapshot |
| ![iPad search](ipados-search.png) | ![iPad snapshot](ipados-snapshot-detail.png) |
| Entity | Change |
| ![iPad entity](ipados-entity-detail.png) | ![iPad change](ipados-change-detail.png) |

## Apple Watch

| Glance | Settings |
| --- | --- |
| ![Watch glance](watchos-glance.png) | ![Watch settings](watchos-settings.png) |
| Snapshot | Change |
| ![Watch snapshot](watchos-snapshot-detail.png) | ![Watch change](watchos-change-detail.png) |

## macOS

| Overview | Snapshots |
| --- | --- |
| ![macOS Overview](macos-overview.png) | ![macOS Snapshots](macos-snapshots.png) |
| Compare | Capabilities |
| ![macOS Compare](macos-compare.png) | ![macOS Capabilities](macos-capabilities.png) |
| Privacy | Search |
| ![macOS Privacy](macos-privacy.png) | ![macOS Search](macos-search.png) |
| Snapshot | Entity |
| ![macOS Snapshot](macos-snapshot-detail.png) | ![macOS Entity](macos-entity-detail.png) |

![Name this snapshot](macos-named-snapshot.png)
