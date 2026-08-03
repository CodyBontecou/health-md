#!/usr/bin/env python3
"""Assemble, verify, and document a nine-slide localized review set."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[2]
EXPECTED_SIZE = (1284, 2778)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locale", required=True)
    parser.add_argument("--successful-image-edits", type=int, default=9)
    parser.add_argument("--retry-counts", default="{}", help="JSON object keyed by slide number")
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    args = parse_args()
    retry_counts = json.loads(args.retry_counts)
    review_dir = REPO_ROOT / "app-store-output/localized-tests" / args.locale
    review_dir.mkdir(parents=True, exist_ok=True)
    expected_review_names = {f"appstore-ios-slide-{n}-{args.locale}-test.png" for n in range(1, 10)}
    for existing in review_dir.iterdir():
        if existing.is_file() and existing.name not in expected_review_names:
            raise SystemExit(f"Unexpected file in validation directory: {existing}")

    images: list[dict[str, object]] = []
    method_counts: dict[str, int] = {}
    thumbnails: list[Image.Image] = []
    for slide in range(1, 10):
        edit_dir = REPO_ROOT / f"app-store-output/ai-edits/{args.locale}-slide-{slide}-reference-swap"
        source = edit_dir / f"slide-{slide}-ai-edit-final.png"
        mask_path = edit_dir / "references" / f"slide-{slide}-local-edit-mask.png"
        base_path = REPO_ROOT / f"apps/apple/fastlane/screenshots/en-US/appstore-ios-slide-{slide}.png"
        if not source.is_file() or not mask_path.is_file():
            raise SystemExit(f"Missing accepted source or mask for slide {slide}")
        slide_manifest_path = edit_dir / "manifest.json"
        slide_manifest = json.loads(slide_manifest_path.read_text()) if slide_manifest_path.is_file() else {}
        generation_method = str(slide_manifest.get("provider", "unknown"))
        method_counts[generation_method] = method_counts.get(generation_method, 0) + 1

        with Image.open(source) as opened:
            final = opened.convert("RGBA")
        if final.size != EXPECTED_SIZE:
            raise SystemExit(f"Slide {slide}: unexpected dimensions {final.size}")
        base = np.array(Image.open(base_path).convert("RGBA"))
        pixels = np.array(final)
        mask = np.array(Image.open(mask_path).convert("RGBA"))[:, :, 3]
        changed_outside = int(np.count_nonzero(np.any(base[mask == 0] != pixels[mask == 0], axis=1)))
        if changed_outside:
            raise SystemExit(f"Slide {slide}: {changed_outside} pixels changed outside the mask")

        review = review_dir / f"appstore-ios-slide-{slide}-{args.locale}-test.png"
        shutil.copyfile(source, review)
        if source.read_bytes() != review.read_bytes():
            raise SystemExit(f"Slide {slide}: review copy differs from accepted source")
        images.append({
            "slide": slide,
            "source": str(source.relative_to(REPO_ROOT)),
            "reviewImage": str(review.relative_to(REPO_ROOT)),
            "dimensions": list(EXPECTED_SIZE),
            "sha256": sha256(review),
            "outsideMaskChangedPixels": 0,
            "generationMethod": generation_method,
        })

        thumb_width = 260
        thumb_height = round(final.height * thumb_width / final.width)
        thumb = final.convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        tile = Image.new("RGB", (thumb_width, thumb_height + 34), "white")
        tile.paste(thumb, (0, 34))
        ImageDraw.Draw(tile).text((10, 9), f"SLIDE {slide}", fill="black")
        thumbnails.append(tile)

    gap = 12
    tile_width, tile_height = thumbnails[0].size
    contact = Image.new(
        "RGB",
        (3 * tile_width + 2 * gap, 3 * tile_height + 2 * gap),
        (220, 220, 220),
    )
    for index, thumbnail in enumerate(thumbnails):
        contact.paste(thumbnail, ((index % 3) * (tile_width + gap), (index // 3) * (tile_height + gap)))
    contact_path = REPO_ROOT / f"app-store-output/localized-tests/{args.locale}-contact-sheet.png"
    contact.save(contact_path)

    workflow = (
        "masked OpenAI reference-swap edit with deterministic localized phone compositing"
        if set(method_counts) <= {"openai-direct-images-edit"}
        else "mixed masked OpenAI and deterministic local billing-limit fallback with localized phone compositing"
    )
    manifest = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "locale": args.locale,
        "workflow": workflow,
        "model": "gpt-image-2",
        "quality": "medium",
        "acceptedImages": 9,
        "successfulPaidImageEdits": args.successful_image_edits,
        "retryCounts": retry_counts,
        "generationMethods": method_counts,
        "uploadedReferenceTypes": [
            "English App Store master",
            f"{args.locale} simulator capture",
            f"{args.locale} marketing-copy image",
        ],
        "validation": {"displayType": "APP_IPHONE_65", "readyFiles": 9},
        "appStoreUploadPerformed": False,
        "submissionWithdrawalPerformed": False,
        "contactSheet": str(contact_path.relative_to(REPO_ROOT)),
        "images": images,
    }
    manifest_path = REPO_ROOT / f"app-store-output/localized-tests/{args.locale}-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(review_dir.relative_to(REPO_ROOT))
    print(contact_path.relative_to(REPO_ROOT))
    print(manifest_path.relative_to(REPO_ROOT))


if __name__ == "__main__":
    main()
