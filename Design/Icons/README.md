# Diffuse icons

The mark is the seven-circle cluster from the Mac menu bar (`circle.hexagongrid`): one node in the middle, six around it — a compact “network of observations.”

Regenerate masters with:

```bash
python3 Scripts/generate-icons.py   # needs Pillow
```

Do not hand-edit the 1024px PNGs and then forget the Icon Composer source.

| File | Used for |
| --- | --- |
| `AppIcon-iOS.png` | Home screen, Spotlight, Settings, notifications (light) |
| `AppIcon-iOS-dark.png` | iOS 18+ dark home screen (transparent, system fill) |
| `AppIcon-iOS-tinted.png` | iOS 18+ tinted home screen (grayscale) |
| `AppIcon-watchOS.png` | Watch home screen (circular crop, extra inset) |
| `AppIcon-macOS.png` | Dock, Finder, Spotlight (rounded plate + shadow) |
| `Grid-glyph.png` | Icon Composer layer, menu bar source |
| `Snapshot-document.png` | Finder icon for `.diffuse` snapshot files |
| `../AppIcon.icon` | Xcode 26 Icon Composer / Liquid Glass source |

Platform asset catalogs live next to each app target and compile from these masters. Xcode generates the remaining iOS/watch sizes from the 1024px images; macOS still ships every Dock size explicitly.

App **screenshots** (README marketing shots) are a different pipeline: [docs/screenshots/README.md](../../docs/screenshots/README.md).
