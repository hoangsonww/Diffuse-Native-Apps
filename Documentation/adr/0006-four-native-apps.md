# ADR 0006: Four genuine native apps

## Status

Accepted.

## Date

2026-08.

## Context

A single multiplatform SwiftUI target can ship on Mac, iPhone, iPad, and Watch. It also tends to produce a phone app in a Mac window, a Mac inspector on a phone, and a Watch app that is a truncated list of the same screens.

Diffuse’s question is the same everywhere; the *way you ask it* is not.

## Decision

Four application targets, four navigation models:

| App | Shape |
| --- | --- |
| Mac | NavigationSplitView + menu bar extra + settings for schedule/repos |
| iPhone | TabView + NavigationStack, cards and sheets |
| iPad | Three-column workspace (snapshots / changes / detail), including regular-width portrait |
| Watch | Glance list + complications, standalone |

Shared: `DiffuseUI` components and `DiffuseModel`. Not shared: root navigation, scheduling driver, capability set.

iPhone and iPad are separate targets even though they share an SDK. They share collectors via `IOSCapabilityRegistry` but report platform as `.iOS` vs `.iPadOS`.

## Alternatives considered

- **One `multiplatform` target + size classes.** Rejected: Watch and Mac would inherit phone navigation; iPad would collapse in portrait.
- **Mac Catalyst for the Mac app.** Rejected: menu bar extra, `NSWorkspace`, process tools, and windowing are AppKit/Mac-native work.

## Consequences

- More app code than a max-target. Acceptable: the amount is small.
- Widgets/complications are per-app extensions with per-app groups.
- A layout bug on iPad cannot be “fixed” by breaking the phone.

## Related

[Apps.md](../Apps.md), [0002](0002-capability-driven.md).
