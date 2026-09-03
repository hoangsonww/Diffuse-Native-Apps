#!/usr/bin/env python3
"""Derives web/media/*.jpg from the committed docs/screenshots/*.png.

The marketing page shows the same screens as the gallery, as JPEGs because they
are smaller over the wire. Producing them by hand is how they end up a release
behind the PNGs — the site kept showing a UI the apps no longer had. This
regenerates every JPEG that has a same-named PNG, so the two cannot drift.

`og.jpg` is a composed social card rather than a screenshot, so it is left
alone.

Usage: build-web-media.py [--check]

  --check  report what would change and exit non-zero if anything is stale,
           without writing. Suitable for CI.
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "screenshots"
MEDIA = ROOT / "web" / "media"

# Composed artwork, not a screenshot of anything.
SKIP = {"og"}

# Chosen to land near the sizes already committed: visually clean at the widths
# the page displays them, without shipping a megabyte per screen.
QUALITY = 82


def derive(check: bool) -> int:
    if not MEDIA.is_dir():
        print(f"No {MEDIA}", file=sys.stderr)
        return 2

    stale: list[str] = []
    written = 0

    for jpeg in sorted(MEDIA.glob("*.jpg")):
        stem = jpeg.stem
        if stem in SKIP:
            continue
        source = SHOTS / f"{stem}.png"
        if not source.exists():
            print(f"  {stem}: no matching screenshot, leaving alone")
            continue

        with Image.open(source) as image:
            rgb = image.convert("RGB")
            if check:
                with Image.open(jpeg) as current:
                    if current.size != rgb.size:
                        stale.append(f"{stem} ({current.size} -> {rgb.size})")
                continue
            rgb.save(jpeg, "JPEG", quality=QUALITY, optimize=True, progressive=True)
        written += 1
        print(f"  {stem}.jpg  {rgb.size}  {jpeg.stat().st_size // 1024} KB")

    if check:
        if stale:
            print("Stale web media:", ", ".join(stale), file=sys.stderr)
            return 1
        print("web/media is in step with docs/screenshots")
        return 0

    print(f"Wrote {written} JPEG(s) from docs/screenshots/")
    return 0


if __name__ == "__main__":
    raise SystemExit(derive("--check" in sys.argv))
