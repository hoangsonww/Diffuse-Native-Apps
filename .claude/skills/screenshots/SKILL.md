---
name: screenshots
description: Regenerate docs/screenshots from the live apps. Use when UI changed and README/docs images are stale, or the user asks for new screenshots.
---

# Screenshots

Replace PNGs in `docs/screenshots/`. Do not invent marketing images.

Use the scripts; they encode the traps.

```bash
Scripts/capture-macos-screenshots.sh          # or one screen by name
Scripts/capture-simulator-screenshots.sh      # ios | ipados | watchos
Scripts/capture-android-screenshots.sh        # or one screen by name
python3 Scripts/build-web-media.py            # derive web/media/*.jpg
```

- A denied Screen Recording permission yields a **black PNG, not an error**. The scripts check colour variance before replacing a committed file.
- Granting Screen Recording to a debug build does not stick — ad-hoc signing changes identity each rebuild. macOS captures run `screencapture` from the terminal instead.
- Android navigation is gated: a missing tap target fails rather than photographing whatever is in front, and the script refuses when Diffuse is not foreground. That is how a phone home screen once shipped as `android-search.png`.
- The Android library is seeded from `Fixtures/` and the capture-on-open pruned, so comparisons show real changes and reruns are reproducible.
- `simctl launch` only forwards `SIMCTL_CHILD_`-prefixed variables; anything else is argv.
- Update the date at the top of `docs/screenshots/README.md` when images are replaced.
- `Scripts/generate-icons.py` is for app icons, not these shots.
