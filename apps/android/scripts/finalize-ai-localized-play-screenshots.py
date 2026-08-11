#!/usr/bin/env python3
"""Validate and import gpt-image-2 localized Play screenshots into the authored tree."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw

ANDROID_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ANDROID_ROOT.parents[1]
AI_ROOT = REPO_ROOT / "app-store-output/android-ai-edits"
OUTPUT_ROOT = ANDROID_ROOT / "play-console/screenshots"
CONTACT_ROOT = ANDROID_ROOT / "build/play-screenshot-contact-sheets"
SLIDES = (
    ("core-export", "1-core-export.png"),
    ("export-formats", "2-export-formats.png"),
    ("health-metrics", "3-health-metrics.png"),
    ("private-by-design", "4-private-by-design.png"),
    ("scheduled-exports", "5-scheduled-exports.png"),
    ("file-preview", "6-file-preview.png"),
    ("home-screen-widgets", "7-home-screen-widgets.png"),
    ("direct-cli", "8-direct-cli.png"),
)


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", help="Comma-separated locales; defaults to every draft Play locale")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finalize_locale(locale: str, force: bool) -> list[dict]:
    destination = OUTPUT_ROOT / locale / "phone"
    if destination.exists() and any(destination.glob("*.png")) and not force:
        raise RuntimeError(f"Refusing to overwrite {destination}; pass --force")
    destination.mkdir(parents=True, exist_ok=True)
    if force:
        for existing in destination.glob("*.png"):
            existing.unlink()

    records: list[dict] = []
    images: list[Image.Image] = []
    for index, (slide_id, filename) in enumerate(SLIDES, start=1):
        source_dir = AI_ROOT / locale / slide_id
        source = source_dir / filename
        manifest_path = source_dir / "manifest.json"
        if not source.is_file() or not manifest_path.is_file():
            raise RuntimeError(f"Missing paid AI output for {locale} slide {index}: {source_dir}")
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("paid") is not True or manifest.get("provider") != "openai-direct-images-edit" or manifest.get("model") != "gpt-image-2":
            raise RuntimeError(f"Unverified AI manifest: {manifest_path}")
        with Image.open(source) as image:
            if image.size != (1080, 1920):
                raise RuntimeError(f"Unexpected dimensions {image.size}: {source}")
            rgb = image.convert("RGB")
            images.append(rgb.copy())
            target = destination / filename
            rgb.save(target, optimize=True)
        records.append({"slide": index, "id": slide_id, "file": str(target.relative_to(ANDROID_ROOT)), "sha256": checksum(target)})

    tile_width, tile_height = 270, 480
    sheet = Image.new("RGB", (tile_width * 4, (tile_height + 28) * 2), "white")
    draw = ImageDraw.Draw(sheet)
    for index, ((slide_id, _), image) in enumerate(zip(SLIDES, images)):
        x = (index % 4) * tile_width
        y = (index // 4) * (tile_height + 28)
        sheet.paste(image.resize((tile_width, tile_height), Image.Resampling.LANCZOS), (x, y + 28))
        draw.text((x + 6, y + 6), f"{index + 1} · {slide_id}", fill="#111")
    CONTACT_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(CONTACT_ROOT / f"{locale}-ai.jpg", quality=90)
    return records


def main() -> None:
    args = arguments()
    locale_manifest = json.loads((ANDROID_ROOT / "play-console/locales.json").read_text())
    drafts = [entry["playLocale"] for entry in locale_manifest["locales"] if entry["status"] == "draft"]
    locales = args.locales.split(",") if args.locales else drafts
    unknown = sorted(set(locales) - set(drafts))
    if unknown:
        raise SystemExit(f"Locales are not draft Play locales: {', '.join(unknown)}")

    output: dict[str, list[dict]] = {}
    for locale in locales:
        output[locale] = finalize_locale(locale, args.force)
        print(f"Imported {locale}: {len(output[locale])} gpt-image-2 screenshots")
    manifest = {"schemaVersion": 1, "provider": "openai-direct-images-edit", "model": "gpt-image-2", "locales": output}
    manifest_path = ANDROID_ROOT / "build/play-screenshot-ai-finalization-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(manifest_path.relative_to(ANDROID_ROOT))


if __name__ == "__main__":
    main()
