# Apps

Four genuinely native applications share `DiffuseUI` and the domain engine. They are **not** one multiplatform target with size-class branches. The question is the same everywhere; the way you ask it is not.

See [adr/0006-four-native-apps.md](adr/0006-four-native-apps.md) and skill `native-apps`. Navigation, scheduling drivers, and capability registries live under `Apps/`; generic rows, search, privacy, and preference *surfaces* live in `DiffuseUI`.

## Shared vs not shared

| Shared | Per app |
| --- | --- |
| `DiffuseUI` components, theme, generic section/change/search/privacy views | Root navigation |
| `DiffuseModel` (`@Observable` façade over `SnapshotService`) | Scheduling mechanism (Timer vs BGAppRefresh vs Watch refresh) |
| Preferences shape (`DiffusePreferences`: retention, redaction, cadence, skip-if-unchanged, system events) | Capability registry (Mac vs iOS vs Watch) |
| Capture / diff / export / search | Widgets, complications, menu bar extra |

Do not add a SwiftUI view for one capability. If Git needs a special row, the schema and `Change` already carry enough to render it. A `switch` on `CapabilityID` in an app screen is an architecture bug.

## macOS — DiffuseMac

Source: `Apps/DiffuseMac/`. Destinations in `RootView` (`MacDestination`): Overview, Snapshots, Compare, Capabilities, Privacy (⌘1–⌘5).

- `NavigationSplitView` workspace: sidebar + canvas. The Snapshots inspector **auto-selects the latest** snapshot.
- Menu bar extra (`MenuBarContent`) for capture-at-a-glance without opening the window.
- Scheduled capture on a `Timer` **and** on wake/unlock (`SnapshotSchedulerDriver`), gated by `SnapshotScheduler` (15-minute floor on every trigger).
- Settings (`MacSettings` / `SettingsView`): retention, schedule, redaction, repository watch list (paths fed into `MacGitCollector`).
- Developer-tool collectors; **not sandboxed** (see [Privacy.md](Privacy.md)).
- Fullest capability set (`MacCapabilityRegistry`):

  system, hardware, displays, power, network interfaces, network path, Wi-Fi, storage (all volumes), applications, processes (opt-in), developer tools, git (watched repos).

Screenshot seed: `DIFFUSE_SCREENSHOT=overview|snapshots|compare|capabilities|privacy`. Compare auto-selects the latest pair.

## iOS — DiffuseiOS

Source: `Apps/DiffuseiOS/`. Tabs in `IOSRootView` (`IOSTab`): Overview, Snapshots (timeline), Compare, Settings.

- Capture on open, on demand, and via `BGAppRefreshTask`. The same `SnapshotScheduler.decide` function; a different driver.
- Home Screen and Lock Screen widgets (`Δ N` + peak severity) via `group.com.diffuse.ios`.
- Collectors (`IOSCapabilityRegistry`): device, system, battery, screen, storage (app-container volume), network interfaces, network path. No process list, no `git` spawn, no developer-tool probes.

## iPadOS — DiffuseiPadOS

Source: `Apps/DiffuseiPadOS/`. Separate target even though it shares an SDK with iPhone. Snapshots report `Platform.iPadOS` so capability sets and history stay honest.

- Regular width **always shows three columns** (`IPadRootView.threeColumnWorkspace`): snapshots / changes / detail. Portrait on a typical iPad stays regular-width; do not “fix” it by collapsing to the phone tabs.
- Compact width (Slide Over, some splits) uses a two-column compact split — not the iPhone tab bar.
- Same collectors as iPhone (`IOSCapabilityRegistry(platform: .iPadOS)`).
- Privacy, capabilities, and settings are sheets, not sidebar destinations.
- Widgets via `group.com.diffuse.ipados`.

## watchOS — DiffuseWatch

Source: `Apps/DiffuseWatch/` plus `Apps/DiffuseWatchComplication/`.

- Standalone (`WKRunsIndependentlyOfCompanionApp`). No paired iPhone required.
- Glance UI: summary, recent changes, short history, capture button. No capability editor, no export, no search — those belong on a device with a keyboard.
- `Δ N` complications via `group.com.diffuse.watch`.
- Capability set (`WatchCapabilityRegistry`): watch device, battery, shared system info, storage (container volume), network path.
- Refresh via `WKApplicationRefreshBackgroundTask`. Same `decide` function; a different driver.

## Widgets and complications

They never decode a snapshot. After a successful persist the host app writes `change-count.json` into the app group (`ChangeCountSummary`: `changeCount`, `peakSeverity`, `capturedAt`).

| App | Group |
| --- | --- |
| iOS | `group.com.diffuse.ios` |
| iPadOS | `group.com.diffuse.ipados` |
| watchOS | `group.com.diffuse.watch` |

Unsigned CI builds still **compile** the extensions; the container is missing, so reads fall back to `.empty` rather than crashing. That is expected ([adr/0005](adr/0005-generated-unsigned.md)).

Shared widget code: `Apps/Shared/ChangeCountWidget.swift`, `ChangeCountSummary.swift`, `ChangeCountPublisher.swift`.

## Preferences and scheduling

Retention, redaction, schedule (cadence, system events, skip-if-unchanged), and capability toggles are already wired through `DiffusePreferences` / `SnapshotService` on all four apps. Do not add a fifth copy of “delete snapshots older than…” logic in a view.

Product defaults (enforced by `SnapshotScheduler` / `RetentionPlanner`, not by each app):

- Cadence every **four hours**, **15-minute floor** on every trigger including wake
- Skip persist when an automatic capture diffs empty against the latest snapshot (`skipsWhenUnchanged` is applied by `SnapshotService`, not by `decide`)
- Retention: 90 days, 1 GiB, protects pinned **and** labelled snapshots; newest always kept
- First run with no history captures immediately when the schedule is enabled
- Disabled = cadence off **and** no system-event captures

macOS can offer a longer retention window in the UI; the planner itself is platform-agnostic.

## Signing

`project.yml` has no development team. CI builds with `CODE_SIGNING_ALLOWED=NO`. Local shipping signs **outside** this repository ([adr/0005](adr/0005-generated-unsigned.md)).

## Screenshots

Replace PNGs in `docs/screenshots/` from the live apps. See [docs/screenshots/README.md](../docs/screenshots/README.md) and skill `screenshots`. Seed from `Fixtures/snapshots/` (rewrite timestamps/device/platform if the UI would otherwise look empty). Disable auto-capture on open while shooting or the 15-minute floor plus system events will insert a live snapshot. Do not invent marketing images.
