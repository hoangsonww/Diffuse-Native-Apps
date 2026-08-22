---
name: screenshots
description: Regenerate docs/screenshots from the live apps. Use when UI changed and README/docs images are stale, or the user asks for new screenshots.
---

# Screenshots

Replace PNGs in `docs/screenshots/`. Do not invent marketing images.

- Seed `Application Support/Diffuse/snapshots/` from `Fixtures/snapshots/` (rewrite timestamps/device if needed). Avoid auto-capture on open (15-minute floor + `capturesOnSystemEvents`).
- Mac: launch via `open --env DIFFUSE_SCREENSHOT=…` so the binary has a window. Sandbox-launched binaries may not.
- iOS / iPad / Watch: `simctl io screenshot`. Pass `SIMCTL_CHILD_DIFFUSE_SCREENSHOT=…` — extra `simctl launch` arguments are argv, not environment.
- Android: `adb exec-out screencap -p`. Raw QA passes go to the gitignored `Android/screenshots/`; only curated `docs/screenshots/android-*.png` are versioned.
- Generator: `Scripts/generate-icons.py` is for app icons, not these shots.
- Update the screenshot date in README if the images are replaced.
