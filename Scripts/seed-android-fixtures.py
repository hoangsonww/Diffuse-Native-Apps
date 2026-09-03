#!/usr/bin/env python3
"""Rewrites two golden fixtures into Android snapshots for screenshot capture.

Capturing live on an idle emulator gives two snapshots taken seconds apart with
nothing between them, which renders as "Nothing changed" — a useless picture of
a tool whose whole job is showing differences. These are the same fixtures the
tests use, so the comparison has real content in it, with the platform, device
and timestamps rewritten so an Android screenshot does not claim to be a Mac.

Seeding also makes the images reproducible: rerunning the capture produces the
same screens instead of whatever the emulator happened to be doing.

Usage: seed-android-fixtures.py <repo-root> <output-dir>
"""

from __future__ import annotations

import json
import pathlib
import sys

# (fixture, id, capturedAt) — two points on the same day so the timeline groups
# them under one heading and the comparison reads forwards.
PAIRS = [
    ("mac-baseline.json", "seed-baseline", "2026-09-03T09:04:00Z"),
    ("mac-after-workday.json", "seed-after-workday", "2026-09-03T18:21:00Z"),
]

DEVICE = {
    "name": "Pixel 6",
    "model": "Pixel 6",
    "systemName": "Android",
    "architecture": "arm64",
}


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2

    root = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    for source, new_id, captured in PAIRS:
        path = root / "Fixtures" / "snapshots" / source
        payload = json.loads(path.read_text(encoding="utf-8"))
        # The fixtures are export envelopes; the snapshot itself is one level in.
        snapshot = payload["snapshot"]
        snapshot["id"] = new_id
        snapshot["capturedAt"] = captured
        snapshot["platform"] = "android"
        snapshot["device"] = {**snapshot.get("device", {}), **DEVICE}
        (out / f"{new_id}.json").write_text(
            json.dumps(snapshot, indent=2), encoding="utf-8"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
