#!/usr/bin/env python3
"""Generate highlighted variants of doc screenshots.

For each entry in highlights.json, takes the source PNG, blurs and dims
the entire image, then composites the original through a soft-edged mask
over the focal regions. Adds a thin accent stroke around each focal area.

Output: highlighted/{name}.png at the same resolution as the source.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
HIGHLIGHTS = ROOT / "highlights.json"
OUT_DIR = ROOT / "highlighted"

# Tunables
BLUR_RADIUS = 18           # gaussian blur applied to the dim background
DIM_AMOUNT = 0.45          # 0.0 = pitch black, 1.0 = original brightness
FEATHER = 36               # px of soft edge around each focal rect
CORNER_RADIUS = 28         # rounded corners on focal rects
ACCENT_STROKE = 6          # px stroke around each focal rect
ACCENT_COLOR = (122, 87, 167, 255)  # matches website accent
GLOW_RADIUS = 22           # soft glow outside the stroke

# Source screenshots are scaled relative to a 1206x2622 reference
# (iPhone 16 Pro at @3x logical resolution). Coordinates in highlights.json
# use that reference; we rescale per-image to whatever resolution the
# raw PNG actually has.
REF_W, REF_H = 1206, 2622


def build_mask(size: tuple[int, int], regions, scale_x: float, scale_y: float) -> Image.Image:
    """Soft-edged mask: white = keep sharp, black = use blurred background."""
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    for region in regions:
        x = int(region["x"] * scale_x)
        y = int(region["y"] * scale_y)
        w = int(region["w"] * scale_x)
        h = int(region["h"] * scale_y)
        draw.rounded_rectangle(
            (x, y, x + w, y + h),
            radius=int(CORNER_RADIUS * min(scale_x, scale_y)),
            fill=255,
        )
    feather = max(1, int(FEATHER * min(scale_x, scale_y)))
    return mask.filter(ImageFilter.GaussianBlur(radius=feather))


def build_glow(size: tuple[int, int], regions, scale_x: float, scale_y: float) -> Image.Image:
    """Outer accent glow + crisp accent stroke around each focal rect."""
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    stroke = max(1, int(ACCENT_STROKE * min(scale_x, scale_y)))
    radius = int(CORNER_RADIUS * min(scale_x, scale_y))
    for region in regions:
        x = int(region["x"] * scale_x)
        y = int(region["y"] * scale_y)
        w = int(region["w"] * scale_x)
        h = int(region["h"] * scale_y)
        draw.rounded_rectangle(
            (x, y, x + w, y + h),
            radius=radius,
            outline=ACCENT_COLOR,
            width=stroke,
        )
    glow_radius = max(1, int(GLOW_RADIUS * min(scale_x, scale_y)))
    blurred = glow.filter(ImageFilter.GaussianBlur(radius=glow_radius))
    out = Image.alpha_composite(blurred, glow)
    return out


def render(source_path: Path, regions, output_path: Path) -> None:
    src = Image.open(source_path).convert("RGBA")
    sw, sh = src.size
    scale_x = sw / REF_W
    scale_y = sh / REF_H

    # Dim + blur background
    bg = src.filter(ImageFilter.GaussianBlur(radius=int(BLUR_RADIUS * min(scale_x, scale_y))))
    dim = Image.new("RGBA", src.size, (0, 0, 0, 255))
    bg = Image.blend(dim, bg, DIM_AMOUNT)

    # Soft mask: keep src in focal areas, fade to bg elsewhere
    mask = build_mask(src.size, regions, scale_x, scale_y)
    composed = Image.composite(src, bg, mask)

    # Accent glow + stroke on top
    glow = build_glow(src.size, regions, scale_x, scale_y)
    composed = Image.alpha_composite(composed.convert("RGBA"), glow)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    composed.save(output_path, "PNG", optimize=True)
    print(f"  wrote {output_path.relative_to(ROOT)}")


def main() -> int:
    if not HIGHLIGHTS.exists():
        print(f"missing config: {HIGHLIGHTS}", file=sys.stderr)
        return 1

    config = json.loads(HIGHLIGHTS.read_text())
    entries = config.get("highlights", [])
    if not entries:
        print("no highlights defined", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for entry in entries:
        source = ROOT / entry["source"]
        if not source.exists():
            print(f"  skip (missing source): {entry['source']}")
            continue
        out = OUT_DIR / f"{entry['name']}.png"
        regions = entry.get("regions") or []
        if not regions:
            print(f"  skip (no regions): {entry['name']}")
            continue
        render(source, regions, out)

    return 0


if __name__ == "__main__":
    sys.exit(main())
