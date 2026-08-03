#!/usr/bin/env python3
"""Create localized App Store screenshot drafts without sending app UI to AI.

Dark marketing copy is removed locally with an OpenCV inpaint mask, translated
copy is rendered with local SF Pro fonts, and Spanish simulator captures are
composited into the existing device artwork. Dry-run is the default. Pass
--generate to write PNGs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ABSOLUTE_MAX_IMAGES = 3
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPO_ROOT / "app-store-input/localizations/es-ES-test.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create marketing-copy-only App Store localization drafts."
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Plan only (default).")
    mode.add_argument("--generate", action="store_true", help="Write localized PNG drafts.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG), help="Localization JSON config.")
    parser.add_argument("--max-images", type=int, default=3, help="Hard generation cap (maximum 3).")
    parser.add_argument("--force", action="store_true", help="Overwrite existing outputs.")
    args = parser.parse_args()
    if args.max_images < 1 or args.max_images > ABSOLUTE_MAX_IMAGES:
        parser.error(f"--max-images must be between 1 and {ABSOLUTE_MAX_IMAGES}")
    return args


def repo_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else REPO_ROOT / path


def read_config(path: Path) -> dict[str, Any]:
    try:
        config = json.loads(path.read_text())
    except FileNotFoundError as error:
        raise RuntimeError(f"Config not found: {path}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Invalid JSON in {path}: {error}") from error

    slides = config.get("slides")
    if not isinstance(slides, list) or not slides:
        raise RuntimeError("Config must contain a non-empty slides array")
    return config


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_text_mask(image_rgb: np.ndarray, regions: list[dict[str, Any]]) -> np.ndarray:
    height, width = image_rgb.shape[:2]
    gray = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2GRAY)
    hsv = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2HSV)
    saturation = hsv[:, :, 1]
    mask = np.zeros((height, width), dtype=np.uint8)

    for region in regions:
        x = int(region["x"])
        y = int(region["y"])
        region_width = int(region["width"])
        region_height = int(region["height"])
        x2 = min(width, x + region_width)
        y2 = min(height, y + region_height)
        if x < 0 or y < 0 or x >= x2 or y >= y2:
            raise RuntimeError(f"Invalid erase region: {region}")

        max_gray = int(region.get("maxGray", 232))
        max_saturation = int(region.get("maxSaturation", 80))
        selected = (gray[y:y2, x:x2] < max_gray) & (
            saturation[y:y2, x:x2] < max_saturation
        )
        mask[y:y2, x:x2][selected] = 255

    kernel_size = 11
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    return cv2.dilate(mask, kernel, iterations=1)


def erase_source_copy(image: Image.Image, regions: list[dict[str, Any]]) -> Image.Image:
    image_rgb = np.array(image.convert("RGB"))
    mask = make_text_mask(image_rgb, regions)
    image_bgr = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)
    cleaned_bgr = cv2.inpaint(image_bgr, mask, 9, cv2.INPAINT_TELEA)
    cleaned_rgb = cv2.cvtColor(cleaned_bgr, cv2.COLOR_BGR2RGB)
    return Image.fromarray(cleaned_rgb)


def load_font(spec: dict[str, Any]) -> ImageFont.FreeTypeFont:
    font_path = Path(spec["font"])
    if not font_path.exists():
        raise RuntimeError(f"Font not found: {font_path}")
    return ImageFont.truetype(str(font_path), int(spec["fontSize"]))


def color(value: str) -> str:
    if not isinstance(value, str) or not value.startswith("#"):
        raise RuntimeError(f"Expected a hex color, got {value!r}")
    return value


def validate_text_width(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    max_width: int,
    label: str,
) -> None:
    for line in text.splitlines():
        box = draw.textbbox((0, 0), line, font=font, anchor="lt")
        width = box[2] - box[0]
        if width > max_width:
            raise RuntimeError(f"{label} line is {width}px wide, exceeding {max_width}px: {line}")


def draw_copy(image: Image.Image, slide: dict[str, Any]) -> Image.Image:
    draw = ImageDraw.Draw(image)
    for label in ("headline", "subheadline"):
        spec = slide[label]
        text = str(spec["text"])
        font = load_font(spec)
        max_width = int(spec["maxWidth"])
        validate_text_width(draw, text, font, max_width, label)
        x = int(spec["x"])
        y = int(spec["y"])
        default_line_height = round(int(spec["fontSize"]) * (1.04 if label == "headline" else 1.18))
        line_height = int(spec.get("lineHeight", default_line_height)) + int(spec.get("spacing", 0))
        for line_index, line in enumerate(text.splitlines()):
            draw.text(
                (x, y + line_index * line_height),
                line,
                font=font,
                fill=color(spec["color"]),
                anchor="lt",
            )
    return image


def composite_simulator_capture(
    image: Image.Image, slide: dict[str, Any]
) -> tuple[Image.Image, dict[str, Any] | None]:
    spec = slide.get("simulatorCapture")
    if spec is None:
        return image, None

    capture_path = repo_path(spec["path"])
    if not capture_path.exists():
        raise RuntimeError(f"Simulator capture not found: {capture_path}")

    expected = spec.get("expectedDimensions", {})
    with Image.open(capture_path) as opened_capture:
        opened_capture.load()
        capture = opened_capture.convert("RGBA")

    if expected and (
        capture.width != int(expected["width"])
        or capture.height != int(expected["height"])
    ):
        raise RuntimeError(
            f"Simulator capture is {capture.width}x{capture.height}, expected "
            f"{expected['width']}x{expected['height']}: {capture_path}"
        )

    backdrop_path: Path | None = None
    backdrop_spec = spec.get("statusBarBackdrop")
    if backdrop_spec:
        backdrop_path = repo_path(backdrop_spec["path"])
        if not backdrop_path.exists():
            raise RuntimeError(f"Status-bar backdrop not found: {backdrop_path}")
        height = int(backdrop_spec["height"])
        with Image.open(backdrop_path) as opened_backdrop:
            opened_backdrop.load()
            backdrop = opened_backdrop.convert("RGBA")
        if backdrop.size != capture.size:
            raise RuntimeError("Status-bar backdrop and simulator capture dimensions differ")
        capture.paste(backdrop.crop((0, 0, capture.width, height)), (0, 0))

    source_island = spec["sourceDynamicIsland"]
    target_island = spec["targetDynamicIsland"]
    scale = float(target_island["width"]) / float(source_island["width"])
    resized_width = round(capture.width * scale)
    resized_height = round(capture.height * scale)
    capture = capture.resize((resized_width, resized_height), Image.Resampling.LANCZOS)

    source_center_x = float(source_island["x"]) + float(source_island["width"]) / 2
    source_center_y = float(source_island["y"]) + float(source_island["height"]) / 2
    target_center_x = float(target_island["x"]) + float(target_island["width"]) / 2
    target_center_y = float(target_island["y"]) + float(target_island["height"]) / 2
    paste_x = round(target_center_x - source_center_x * scale)
    paste_y = round(target_center_y - source_center_y * scale)

    mask = Image.new("L", capture.size, 0)
    radius = round(float(spec.get("screenCornerRadius", 175)) * scale)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, resized_width - 1, resized_height - 1), radius=radius, fill=255
    )
    composited = image.convert("RGBA")
    composited.paste(capture, (paste_x, paste_y), mask)

    metadata: dict[str, Any] = {
        "path": str(capture_path.relative_to(REPO_ROOT)),
        "sha256": sha256(capture_path),
        "dimensions": {"width": resized_width, "height": resized_height},
        "placement": {"x": paste_x, "y": paste_y},
    }
    if backdrop_path is not None:
        metadata["statusBarBackdrop"] = {
            "path": str(backdrop_path.relative_to(REPO_ROOT)),
            "sha256": sha256(backdrop_path),
        }
    return composited.convert("RGB"), metadata


def render_slide(slide: dict[str, Any], output_dir: Path, force: bool) -> dict[str, Any]:
    source = repo_path(slide["source"])
    output = output_dir / slide["output"]
    if not source.exists():
        raise RuntimeError(f"Source image not found: {source}")
    if output.exists() and not force:
        raise RuntimeError(f"Refusing to overwrite {output}; pass --force if intentional")

    with Image.open(source) as source_image:
        source_image.load()
        cleaned = erase_source_copy(source_image, slide["eraseRegions"])
        localized = draw_copy(cleaned, slide)
        localized, capture_metadata = composite_simulator_capture(localized, slide)
        output.parent.mkdir(parents=True, exist_ok=True)
        localized.save(output, format="PNG", optimize=True)
        dimensions = {"width": localized.width, "height": localized.height}

    file_metadata = {
        "source": str(source.relative_to(REPO_ROOT)),
        "sourceSha256": sha256(source),
        "output": str(output.relative_to(REPO_ROOT)),
        "outputSha256": sha256(output),
        "dimensions": dimensions,
        "headline": slide["headline"]["text"],
        "subheadline": slide["subheadline"]["text"],
    }
    if capture_metadata is not None:
        file_metadata["simulatorCapture"] = capture_metadata
    return file_metadata


def main() -> int:
    args = parse_args()
    config_path = repo_path(args.config)
    config = read_config(config_path)
    slides = config["slides"]
    if len(slides) > args.max_images:
        raise RuntimeError(
            f"Refusing to continue: {len(slides)} slides exceed --max-images {args.max_images}"
        )

    output_dir = repo_path(config["outputDirectory"])
    print("App Store screenshot localization plan")
    print("======================================")
    print(f"Mode: {'generate (local-only)' if args.generate else 'dry-run'}")
    print(f"Locale: {config['locale']}")
    print(f"Scope: {config['scope']}")
    print(f"Planned images: {len(slides)}")
    print("Provider: local OpenCV/Pillow compositor (no AI/API calls)")
    print(f"Output: {output_dir.relative_to(REPO_ROOT)}")
    for index, slide in enumerate(slides, start=1):
        print(f"\n{index}. {slide['source']}")
        print(f"   Headline: {slide['headline']['text'].replace(chr(10), ' / ')}")
        print(f"   Subheadline: {slide['subheadline']['text'].replace(chr(10), ' / ')}")
        if "simulatorCapture" in slide:
            print(f"   Simulator UI: {slide['simulatorCapture']['path']}")

    uses_simulator_captures = all("simulatorCapture" in slide for slide in slides)
    localized_elements = ["marketing headline", "marketing subheadline"]
    if uses_simulator_captures:
        localized_elements.append("app UI from Spanish simulator captures")
    manifest: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "locale": config["locale"],
        "scope": config["scope"],
        "draftOnly": True,
        "provider": "local-opencv-pillow",
        "paidGeneration": False,
        "plannedImages": len(slides),
        "localizedElements": localized_elements,
        "unchangedElements": ["decorative labels and artwork"],
        "files": [],
    }

    if not args.generate:
        print("\nDry run complete. No images were written.")
        return 0

    if output_dir.exists() and not args.force:
        existing_pngs = list(output_dir.glob("*.png"))
        if existing_pngs:
            raise RuntimeError(
                "Output directory already contains PNGs; pass --force to replace this draft set"
            )
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest["files"] = [render_slide(slide, output_dir, args.force) for slide in slides]
    manifest_path = output_dir.parent / f"{config['locale']}-manifest.json"
    if manifest_path.exists() and not args.force:
        raise RuntimeError(f"Refusing to overwrite {manifest_path}; pass --force if intentional")
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"\nGenerated {len(slides)} Spanish draft screenshots.")
    print(f"Manifest: {manifest_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"\nError: {error}", file=sys.stderr)
        raise SystemExit(1)
