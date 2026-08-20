# Screenshots

Taken from the running native apps on **18 Aug 2026**. Replace these PNGs from the live apps when UI changes. Do not invent marketing images. Skill: `screenshots`. App icons are a different pipeline: [Design/Icons/README.md](../../Design/Icons/README.md).

The iPhone shots are full-device framebuffers (1206×2622). A missing launch screen previously letterboxed the UI to a 320×480 compatibility size; that is fixed.

## How they were taken

- **iPhone, iPad, Watch** — Simulator framebuffers (`simctl io screenshot`). iOS timeline needed `simctl launch --console` or the framebuffer stayed Springboard.
- **macOS** — live window captures (`screencapture -l`). Launch via `open --env DIFFUSE_SCREENSHOT=…` so the process has a window; a sandboxed binary launch may not.

Seed the library from `Fixtures/snapshots/` (rewrite timestamps, device identity, and platform if the UI would otherwise look empty). Avoid auto-capture on open while shooting: the 15-minute scheduler floor plus `capturesOnSystemEvents` will otherwise insert a live snapshot.

`DIFFUSE_SCREENSHOT` values the apps honour:

| App | Values |
| --- | --- |
| Mac | `overview`, `snapshots`, `compare`, `capabilities`, `privacy` |
| iPhone | `overview`, `timeline`, `compare`, `settings` |
| iPad | `privacy`, `capabilities` (sheets on the three-column workspace) |

On Mac, `compare` also triggers `model.compareLatest()`.

## iPhone

| Overview | Snapshots |
| --- | --- |
| ![iOS Overview](ios-overview.png) | ![iOS Snapshots](ios-timeline.png) |
| Compare | Settings |
| ![iOS Compare](ios-compare.png) | ![iOS Settings](ios-settings.png) |

## iPad

| Workspace | Privacy |
| --- | --- |
| ![iPad workspace](ipados-workspace.png) | ![iPad privacy](ipados-privacy.png) |

## Apple Watch

![Watch glance](watchos-glance.png)

## macOS

| Overview | Snapshots |
| --- | --- |
| ![macOS Overview](macos-overview.png) | ![macOS Snapshots](macos-snapshots.png) |
| Compare | Capabilities |
| ![macOS Compare](macos-compare.png) | ![macOS Capabilities](macos-capabilities.png) |

![macOS Privacy](macos-privacy.png)
