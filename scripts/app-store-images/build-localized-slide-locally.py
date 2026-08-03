#!/usr/bin/env python3
"""Build a localized slide without another paid image call.

Uses an accepted masked donor slide for the edited background, removes only the
donor marketing glyphs, draws exact localized copy, and composites the real
localized simulator UI inside the existing phone display.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
SIZE = (1284, 2778)

LAYOUTS = {
    1: {"headline": 92, "subheadline": 48, "text": (.072, .111, .56), "phone": (.151, .267, .698, None, .061)},
    2: {"headline": 82, "subheadline": 43, "text": (.058, .133, .625), "phone": (.122, .381, .709, None, .055)},
    3: {"headline": 88, "subheadline": 46, "text": (.066, .105, .555), "phone": (.162, .294, .664, None, .052)},
    4: {"headline": 92, "subheadline": 44, "text": (.072, .119, .58), "phone": (.182, .312, .636, .67, .074)},
    5: {"headline": 92, "subheadline": 43, "text": (.07, .092, .51), "phone": (.181, .283, .636, .695, .074)},
    6: {"headline": 82, "subheadline": 43, "text": (.078, .116, .61), "phone": (.152, .29, .7, .703, .078)},
    7: {"headline": 82, "subheadline": 42, "text": (.07, .095, .72), "phone": (.217, .269, .661, .69, .074)},
    8: {"headline": 82, "subheadline": 43, "text": (.055, .098, .685), "phone": (.167, .29, .653, .703, .074)},
    9: {"headline": 82, "subheadline": 39, "text": (.055, .105, .66), "subWidth": .465, "phone": (.159, .281, .68, .7, .078)},
}

CAPTURE_FILES = {
    1: "01-export-top.png",
    2: "02-export-formats.png",
    3: "03-daily-note-injection.png",
    4: "04-health-metrics.png",
    5: "05-format-customization.png",
    6: "06-export-preview.png",
    7: "07-individual-tracking.png",
    8: "08-scheduled-exports.png",
    9: "09-mac-destination.png",
}

FONT_SPECS = {
    "latin": {
        "headline": ("/Library/Fonts/SF-Pro-Display-Bold.otf", 0),
        "subheadline": ("/Library/Fonts/SF-Pro-Display-Regular.otf", 0),
    },
    "ja": {
        "headline": ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 0),
        "subheadline": ("/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc", 0),
    },
    "ko": {
        "headline": ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6),
        "subheadline": ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 0),
    },
    "zh-Hans": {
        "headline": ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2),
        "subheadline": ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0),
    },
}


def args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locale", required=True)
    parser.add_argument("--slide", required=True, type=int, choices=range(1, 10))
    parser.add_argument("--donor-locale", default="de-DE")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def glyph_units(value: str) -> float:
    total = 0.0
    for character in value:
        code = ord(character)
        if (
            0x3400 <= code <= 0x9FFF
            or 0x3040 <= code <= 0x30FF
            or 0xAC00 <= code <= 0xD7AF
        ):
            total += 1.0
        elif character.isspace():
            total += 0.32
        elif character.isupper():
            total += 0.64
        else:
            total += 0.54
    return total


def fitted_size(base: int, lines: list[str], width: float, minimum: int) -> int:
    longest = max((glyph_units(line) for line in lines), default=1.0)
    return min(base, max(minimum, int(width // longest)))


def line_bands(mask: np.ndarray) -> list[tuple[int, int]]:
    active = np.count_nonzero(mask, axis=1) >= 3
    ys = np.flatnonzero(active)
    if not len(ys):
        return []
    bands: list[tuple[int, int]] = []
    start = previous = int(ys[0])
    for raw_y in ys[1:]:
        y = int(raw_y)
        if y - previous > 8:
            if previous - start >= 5:
                bands.append((start, previous + 1))
            start = y
        previous = y
    if previous - start >= 5:
        bands.append((start, previous + 1))
    return bands


def main() -> None:
    options = args()
    slide = options.slide
    layout = LAYOUTS[slide]
    output_dir = REPO_ROOT / f"app-store-output/ai-edits/{options.locale}-slide-{slide}-reference-swap"
    output_dir.mkdir(parents=True, exist_ok=True)
    final_path = output_dir / f"slide-{slide}-ai-edit-final.png"
    if final_path.exists() and not options.force:
        raise SystemExit(f"Refusing to overwrite {final_path}; pass --force")

    donor_path = REPO_ROOT / f"app-store-output/ai-edits/{options.donor_locale}-slide-{slide}-reference-swap/slide-{slide}-ai-edit-final.png"
    mask_path = output_dir / "references" / f"slide-{slide}-local-edit-mask.png"
    capture_path = REPO_ROOT / "app-store-output/simulator-captures" / options.locale / CAPTURE_FILES[slide]
    copy_path = REPO_ROOT / "app-store-input/localizations" / f"marketing-{options.locale}.json"
    for required in (donor_path, mask_path, capture_path, copy_path):
        if not required.is_file():
            raise SystemExit(f"Missing required input: {required}")

    copy_config = json.loads(copy_path.read_text())
    copy = copy_config["slides"][str(slide)]
    donor = np.array(Image.open(donor_path).convert("RGBA"))
    edit_mask = np.array(Image.open(mask_path).convert("RGBA"))[:, :, 3] > 0
    phone_y = round(SIZE[1] * layout["phone"][1])
    text_allowed = edit_mask.copy()
    text_allowed[phone_y:, :] = False

    rgb = donor[:, :, :3].astype(np.int32)
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    luminance = (rgb[:, :, 0] * 299 + rgb[:, :, 1] * 587 + rgb[:, :, 2] * 114) // 1000
    glyph_mask = text_allowed & (luminance < 218) & (chroma < 24)
    bands = line_bands(glyph_mask)
    if len(bands) < 4:
        raise SystemExit(f"Could not identify donor copy lines for slide {slide}; bands={bands}")

    donor_headline_count = 2
    headline_bands = bands[:donor_headline_count]
    subtitle_bands = bands[donor_headline_count:]
    headline_pixels = glyph_mask.copy()
    headline_pixels[: headline_bands[0][0], :] = False
    headline_pixels[headline_bands[-1][1] :, :] = False
    subtitle_pixels = glyph_mask.copy()
    subtitle_pixels[: subtitle_bands[0][0], :] = False
    subtitle_pixels[subtitle_bands[-1][1] :, :] = False
    headline_x = int(np.flatnonzero(np.any(headline_pixels, axis=0))[0])
    subtitle_x = int(np.flatnonzero(np.any(subtitle_pixels, axis=0))[0])
    headline_top = headline_bands[0][0]
    subtitle_top = subtitle_bands[0][0]

    erase_mask = np.zeros(glyph_mask.shape, dtype=np.uint8)
    for band_start, band_end in bands:
        band_pixels = glyph_mask[band_start:band_end]
        xs = np.flatnonzero(np.any(band_pixels, axis=0))
        if not len(xs):
            continue
        left = max(0, int(xs[0]) - 18)
        right = min(SIZE[0], int(xs[-1]) + 19)
        top = max(0, band_start - 14)
        bottom = min(SIZE[1], band_end + 14)
        erase_mask[top:bottom, left:right] = 1
    erase_mask = (erase_mask.astype(bool) & text_allowed).astype(np.uint8) * 255
    clean_rgb = cv2.inpaint(donor[:, :, :3], erase_mask, 11, cv2.INPAINT_TELEA)
    clean = np.dstack((clean_rgb, donor[:, :, 3]))

    _, _, text_width_fraction = layout["text"]
    headline_width = text_width_fraction * SIZE[0] - 80
    sub_width_fraction = layout.get("subWidth", text_width_fraction)
    subtitle_width = sub_width_fraction * SIZE[0] - 45
    headline_size = copy.get("headlineFontSize") or fitted_size(layout["headline"], copy["headlineLines"], headline_width, 52)
    subtitle_size = copy.get("subheadlineFontSize") or fitted_size(layout["subheadline"], copy["subheadlineLines"], subtitle_width, 29)

    font_key = options.locale if options.locale in FONT_SPECS else "latin"
    headline_spec = FONT_SPECS[font_key]["headline"]
    subtitle_spec = FONT_SPECS[font_key]["subheadline"]
    headline_font = ImageFont.truetype(headline_spec[0], headline_size, index=headline_spec[1])
    subtitle_font = ImageFont.truetype(subtitle_spec[0], subtitle_size, index=subtitle_spec[1])
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    headline_line_height = round(headline_size * 1.12)
    subtitle_line_height = round(subtitle_size * 1.32)
    for index, line in enumerate(copy["headlineLines"]):
        draw.text(
            (headline_x, headline_top + index * headline_line_height),
            line,
            font=headline_font,
            fill=(23, 23, 23, 255),
            anchor="lt",
        )
    for index, line in enumerate(copy["subheadlineLines"]):
        draw.text((subtitle_x, subtitle_top + index * subtitle_line_height), line, font=subtitle_font, fill=(90, 90, 90, 255), anchor="lt")

    layer_pixels = np.array(layer)
    layer_pixels[~text_allowed] = 0
    result = Image.fromarray(clean, "RGBA")
    result.alpha_composite(Image.fromarray(layer_pixels, "RGBA"))

    phone_x = round(SIZE[0] * layout["phone"][0])
    phone_width = round(SIZE[0] * layout["phone"][2])
    phone_height_fraction = layout["phone"][3]
    phone_height = round(SIZE[1] * phone_height_fraction) if phone_height_fraction else SIZE[1] - phone_y + 8
    phone_radius = round(SIZE[0] * layout["phone"][4])
    screenshot = Image.open(capture_path).convert("RGBA").resize((phone_width, phone_height), Image.Resampling.LANCZOS)
    rounded = Image.new("L", (phone_width, phone_height), 0)
    ImageDraw.Draw(rounded).rounded_rectangle((0, 0, phone_width - 1, phone_height - 1), radius=phone_radius, fill=255)
    screenshot.putalpha(rounded)
    result.alpha_composite(screenshot, (phone_x, phone_y))
    result.save(final_path, optimize=True)

    manifest = {
        "locale": options.locale,
        "slideNumber": slide,
        "provider": "local-deterministic-billing-limit-fallback",
        "paid": False,
        "donorLocale": options.donor_locale,
        "donorImage": str(donor_path.relative_to(REPO_ROOT)),
        "localizedUI": str(capture_path.relative_to(REPO_ROOT)),
        "headline": copy["headline"],
        "subheadline": copy["subheadline"],
        "finalOutput": str(final_path.relative_to(REPO_ROOT)),
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(final_path.relative_to(REPO_ROOT))


if __name__ == "__main__":
    main()
