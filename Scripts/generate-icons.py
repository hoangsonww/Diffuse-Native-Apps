#!/usr/bin/env python3
"""Generate Diffuse's app icons, catalog variants, and supporting glyphs.

Run from the repo root (or via Scripts/bootstrap.sh). Masters live in
Design/Icons; platform asset catalogs are written next to each app target.

The mark is the same seven-circle cluster as the Mac menu bar
(`circle.hexagongrid`): one node in the middle, six around it. iOS/watch
artwork fills the canvas (the system applies the mask). macOS artwork is a
rounded plate with room around it.
"""

from __future__ import annotations

import json
import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "Design" / "Icons"

INDIGO = (47, 74, 138, 255)  # #2F4A8A
PAPER = (243, 240, 232, 255)  # #F3F0E8
LIGHT_GRID = (232, 236, 248, 255)
TINTED = (255, 255, 255, 255)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def hex_grid_mask(size: int, filled: bool | None = None, fit: float = 1.0) -> Image.Image:
    """The menu-bar mark: seven circles in hexagonal packing.

    Rings at large sizes (matching SF Symbol `circle.hexagongrid`); solid dots
    below ~40px so the cluster still reads in the Dock.
    """
    if filled is None:
        filled = size <= 40
    scale = 4
    s = max(size * scale, 4)
    canvas = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(canvas)
    cx = cy = s / 2
    radius = s * 0.108 * fit
    pitch = radius * 2.18
    stroke = max(int(radius * 0.38), scale)
    points = [(cx, cy)]
    for i in range(6):
        angle = math.radians(30 + 60 * i)
        points.append((cx + pitch * math.cos(angle), cy + pitch * math.sin(angle)))
    for x, y in points:
        box = [x - radius, y - radius, x + radius, y + radius]
        if filled:
            draw.ellipse(box, fill=255)
        else:
            draw.ellipse(box, outline=255, width=stroke)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def tint(mask: Image.Image, color: tuple[int, int, int, int]) -> Image.Image:
    image = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    overlay = Image.new("RGBA", mask.size, color)
    image.paste(overlay, (0, 0), mask)
    return image


def bleed_icon(
    size: int,
    fill: tuple[int, int, int, int],
    glyph: tuple[int, int, int, int],
    fit: float = 1.0,
) -> Image.Image:
    image = Image.new("RGBA", (size, size), fill)
    image.alpha_composite(tint(hex_grid_mask(size, fit=fit), glyph))
    return image


def mac_icon(size: int) -> Image.Image:
    """macOS icons are a plate on a transparent canvas, not a full bleed."""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset = max(int(size * 0.08), 1)
    radius = max(int(size * 0.195), 2)
    plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(plate)
    box = (inset, inset, size - inset - 1, size - inset - 1)
    draw.rounded_rectangle(box, radius=radius, fill=INDIGO)

    if size >= 64:
        shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow)
        drop = (inset, inset + max(size // 48, 1), size - inset - 1, size - inset - 1 + max(size // 48, 1))
        sdraw.rounded_rectangle(drop, radius=radius, fill=(0, 0, 0, 70))
        blur = max(size // 28, 1)
        shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
        image.alpha_composite(shadow)

    image.alpha_composite(plate)
    glyph_canvas = size - 2 * inset
    glyph = tint(hex_grid_mask(glyph_canvas), PAPER)
    image.alpha_composite(glyph, (inset, inset))
    return image


def document_icon(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset = max(int(size * 0.14), 2)
    draw = ImageDraw.Draw(image)
    page = [inset, inset, size - inset, size - inset]
    radius = max(int(size * 0.08), 2)
    # Soft shadow
    if size >= 64:
        shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (page[0], page[1] + size // 40, page[2], page[3] + size // 40),
            radius=radius,
            fill=(0, 0, 0, 50),
        )
        image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(size // 32, 1))))
    draw.rounded_rectangle(page, radius=radius, fill=PAPER)
    # Folded corner
    fold = max(int(size * 0.18), 6)
    draw.polygon(
        [
            (page[2] - fold, page[1]),
            (page[2], page[1] + fold),
            (page[2] - fold, page[1] + fold),
        ],
        fill=(226, 222, 210, 255),
    )
    # Small indigo plate with Δ
    plate = max(int(size * 0.42), 8)
    px = (size - plate) // 2
    py = int(size * 0.38)
    inner = Image.new("RGBA", (plate, plate), (0, 0, 0, 0))
    ImageDraw.Draw(inner).rounded_rectangle((0, 0, plate - 1, plate - 1), radius=max(plate // 5, 1), fill=INDIGO)
    inner.alpha_composite(tint(hex_grid_mask(plate), PAPER))
    image.alpha_composite(inner, (px, py))
    return image


def menu_bar_icon(size: int) -> Image.Image:
    """Template glyph matching SF Symbol `circle.hexagongrid`."""
    return tint(hex_grid_mask(size, filled=size <= 32), (255, 255, 255, 255))


def catalog_root(path: Path) -> Path:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)
    write_json(path / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    return path


def write_accent(catalog: Path) -> None:
    write_json(
        catalog / "AccentColor.colorset" / "Contents.json",
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "blue": "0.541", "green": "0.290", "red": "0.184"},
                    },
                    "idiom": "universal",
                },
                {
                    "appearances": [{"appearance": "luminosity", "value": "dark"}],
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "blue": "0.910", "green": "0.643", "red": "0.545"},
                    },
                    "idiom": "universal",
                },
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


def write_ios_appicon(catalog: Path, light: Image.Image, dark: Image.Image, tinted: Image.Image) -> None:
    folder = catalog / "AppIcon.appiconset"
    save(light, folder / "AppIcon.png")
    save(dark, folder / "AppIcon-dark.png")
    save(tinted, folder / "AppIcon-tinted.png")
    write_json(
        folder / "Contents.json",
        {
            "images": [
                {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
                {
                    "appearances": [{"appearance": "luminosity", "value": "dark"}],
                    "filename": "AppIcon-dark.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                },
                {
                    "appearances": [{"appearance": "luminosity", "value": "tinted"}],
                    "filename": "AppIcon-tinted.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                },
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


def write_watch_appicon(catalog: Path, image: Image.Image) -> None:
    folder = catalog / "AppIcon.appiconset"
    save(image, folder / "AppIcon.png")
    write_json(
        folder / "Contents.json",
        {
            "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        },
    )


def write_mac_appicon(catalog: Path) -> None:
    folder = catalog / "AppIcon.appiconset"
    images = []
    # (points, scale) → pixel size
    slots = [
        (16, 1),
        (16, 2),
        (32, 1),
        (32, 2),
        (128, 1),
        (128, 2),
        (256, 1),
        (256, 2),
        (512, 1),
        (512, 2),
    ]
    for points, scale in slots:
        pixels = points * scale
        name = f"icon_{points}x{points}" + (f"@{scale}x" if scale > 1 else "") + ".png"
        save(mac_icon(pixels), folder / name)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    write_json(folder / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def write_imageset(catalog: Path, name: str, files: dict[str, Image.Image], template: bool = False) -> None:
    folder = catalog / f"{name}.imageset"
    images = []
    for scale, image in files.items():
        filename = f"{name}{'' if scale == '1x' else f'@{scale}'}.png"
        save(image, folder / filename)
        images.append({"filename": filename, "idiom": "universal", "scale": scale})
    payload: dict = {"images": images, "info": {"author": "xcode", "version": 1}}
    if template:
        payload["properties"] = {"template-rendering-intent": "template", "preserves-vector-representation": False}
    write_json(folder / "Contents.json", payload)


def write_iconset_and_icns(iconset: Path, icns: Path, renderer) -> None:
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    sizes = [16, 32, 128, 256, 512]
    for points in sizes:
        save(renderer(points), iconset / f"icon_{points}x{points}.png")
        save(renderer(points * 2), iconset / f"icon_{points}x{points}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", "-o", str(icns), str(iconset)], check=True)


def write_composer_icon(light_glyph: Image.Image) -> None:
    package = ROOT / "Design" / "AppIcon.icon"
    assets = package / "Assets"
    if package.exists():
        shutil.rmtree(package)
    assets.mkdir(parents=True)
    save(light_glyph, assets / "Grid.png")
    write_json(
        package / "icon.json",
        {
            "fill-specializations": [
                {"value": {"solid": "extended-srgb:0.18431,0.29020,0.54118,1.00000"}},
                {
                    "appearance": "dark",
                    "value": {"solid": "extended-srgb:0.09412,0.14902,0.29020,1.00000"},
                },
            ],
            "groups": [
                {
                    "name": "Mark",
                    "layers": [
                        {
                            "name": "Grid",
                            "image-name": "Grid.png",
                            "glass": True,
                            "fill-specializations": [
                                {"value": {"solid": "extended-srgb:0.95294,0.94118,0.90980,1.00000"}},
                                {
                                    "appearance": "dark",
                                    "value": {"solid": "extended-srgb:0.90980,0.92549,0.97255,1.00000"},
                                },
                                {
                                    "appearance": "tinted",
                                    "value": {"solid": "extended-gray:1.00000,1.00000"},
                                },
                            ],
                        }
                    ],
                    "shadow": {"kind": "neutral", "opacity": 0.35},
                    "specular": True,
                    "translucency": {"enabled": True, "value": 0.18},
                }
            ],
            "supported-platforms": {"circles": ["watchOS"], "squares": ["iOS", "macOS"]},
        },
    )


def write_svg(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cx = cy = 512
    r = 110
    pitch = r * 2.18
    circles = [(cx, cy)]
    for i in range(6):
        a = math.radians(30 + 60 * i)
        circles.append((cx + pitch * math.cos(a), cy + pitch * math.sin(a)))
    rings = "\n".join(
        f'  <circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="none" stroke="#F3F0E8" stroke-width="42"/>'
        for x, y in circles
    )
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#2F4A8A"/>
{rings}
</svg>
"""
    )


def main() -> None:
    DESIGN.mkdir(parents=True, exist_ok=True)

    master = 1024
    light = bleed_icon(master, INDIGO, PAPER)
    dark = tint(hex_grid_mask(master), LIGHT_GRID)
    tinted = tint(hex_grid_mask(master), TINTED)
    watch = bleed_icon(master, INDIGO, PAPER, fit=0.88)
    mac_master = mac_icon(master)
    glyph = tint(hex_grid_mask(master), (255, 255, 255, 255))

    save(light, DESIGN / "AppIcon-iOS.png")
    save(dark, DESIGN / "AppIcon-iOS-dark.png")
    save(tinted, DESIGN / "AppIcon-iOS-tinted.png")
    save(watch, DESIGN / "AppIcon-watchOS.png")
    save(mac_master, DESIGN / "AppIcon-macOS.png")
    save(glyph, DESIGN / "Grid-glyph.png")
    save(document_icon(1024), DESIGN / "Snapshot-document.png")
    write_svg(DESIGN / "AppIcon.svg")

    # iPhone
    ios = catalog_root(ROOT / "Apps/DiffuseiOS/Resources/Assets.xcassets")
    write_ios_appicon(ios, light, dark, tinted)
    write_accent(ios)
    write_imageset(ios, "AppLogo", {"1x": bleed_icon(180, INDIGO, PAPER), "2x": bleed_icon(360, INDIGO, PAPER), "3x": bleed_icon(540, INDIGO, PAPER)})

    # iPad
    ipad = catalog_root(ROOT / "Apps/DiffuseiPadOS/Resources/Assets.xcassets")
    write_ios_appicon(ipad, light, dark, tinted)
    write_accent(ipad)
    write_imageset(ipad, "AppLogo", {"1x": bleed_icon(180, INDIGO, PAPER), "2x": bleed_icon(360, INDIGO, PAPER)})

    # Watch
    watch_cat = catalog_root(ROOT / "Apps/DiffuseWatch/Resources/Assets.xcassets")
    write_watch_appicon(watch_cat, watch)
    write_accent(watch_cat)

    # Mac
    mac = catalog_root(ROOT / "Apps/DiffuseMac/Resources/Assets.xcassets")
    write_mac_appicon(mac)
    write_accent(mac)
    write_imageset(
        mac,
        "MenuBarIcon",
        {
            "1x": menu_bar_icon(22),
            "2x": menu_bar_icon(44),
            "3x": menu_bar_icon(66),
        },
        template=True,
    )
    write_imageset(mac, "AppLogo", {"1x": mac_icon(128), "2x": mac_icon(256)})

    # Widgets / complication — accent only; gallery uses the parent app icon.
    for widget in (
        ROOT / "Apps/DiffuseiOSWidget/Resources/Assets.xcassets",
        ROOT / "Apps/DiffuseiPadOSWidget/Resources/Assets.xcassets",
        ROOT / "Apps/DiffuseWatchComplication/Resources/Assets.xcassets",
    ):
        catalog = catalog_root(widget)
        write_accent(catalog)

    write_iconset_and_icns(
        DESIGN / "Snapshot.iconset",
        ROOT / "Apps/DiffuseMac/Resources/Snapshot.icns",
        document_icon,
    )
    write_iconset_and_icns(
        DESIGN / "AppIcon-macOS.iconset",
        ROOT / "Apps/DiffuseMac/Resources/AppIcon.icns",
        mac_icon,
    )

    write_composer_icon(glyph)

    # README / docs preview (not compiled into a target)
    save(light.resize((256, 256), Image.Resampling.LANCZOS), ROOT / "docs" / "app-icon.png")

    print("Wrote icons under Design/Icons and each app's Assets.xcassets")


if __name__ == "__main__":
    main()
