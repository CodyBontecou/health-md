#!/usr/bin/env python3
"""Map raw MarketingCapture PNGs into the nine App Store slide inputs."""

from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
CAPTURE_MAP = {
    "01-export-top.png": "01-export.png",
    "02-export-formats.png": "05-export-formats.png",
    "03-daily-note-injection.png": "09-daily-note-injection.png",
    "04-health-metrics.png": "06-metric-selection.png",
    "05-format-customization.png": "07-format-customization.png",
    "06-export-preview.png": "10-export-preview.png",
    "07-individual-tracking.png": "08-individual-tracking.png",
    "08-scheduled-exports.png": "02-schedule.png",
    "09-mac-destination.png": "03-sync.png",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locale", required=True, help="Canonical App Store locale, such as de-DE")
    parser.add_argument("--capture-locale", required=True, help="Folder emitted by capture-marketing.sh, such as de")
    parser.add_argument(
        "--status-source",
        default="app-store-output/simulator-captures/es-ES/04-health-metrics.png",
        help="A 1320x2868 simulator screenshot whose top status-bar strip should be reused",
    )
    parser.add_argument("--status-height", type=int, default=140)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source_dir = REPO_ROOT / "apps/apple/marketing" / args.capture_locale
    output_dir = REPO_ROOT / "app-store-output/simulator-captures" / args.locale
    status_path = REPO_ROOT / args.status_source

    if not source_dir.is_dir():
        raise SystemExit(f"Missing raw capture directory: {source_dir}")
    if not status_path.is_file():
        raise SystemExit(f"Missing status source: {status_path}")

    status = Image.open(status_path).convert("RGBA")
    output_dir.mkdir(parents=True, exist_ok=True)

    for output_name, source_name in CAPTURE_MAP.items():
        source_path = source_dir / source_name
        if not source_path.is_file():
            raise SystemExit(f"Missing raw capture: {source_path}")
        image = Image.open(source_path).convert("RGBA")
        if image.size != status.size:
            raise SystemExit(f"Unexpected dimensions for {source_path}: {image.size}; expected {status.size}")
        image.alpha_composite(status.crop((0, 0, status.width, args.status_height)), (0, 0))
        output_path = output_dir / output_name
        image.save(output_path, optimize=True)
        print(output_path.relative_to(REPO_ROOT))


if __name__ == "__main__":
    main()
