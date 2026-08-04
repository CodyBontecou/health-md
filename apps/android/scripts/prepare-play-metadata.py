#!/usr/bin/env python3
"""Build and validate canonical Google Play metadata from the authored source tree."""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


TITLE_LIMIT = 30
SHORT_DESCRIPTION_LIMIT = 80
FULL_DESCRIPTION_LIMIT = 4_000
MAX_SCREENSHOTS_PER_TYPE = 8
MAX_SCREENSHOT_BYTES = 8 * 1024 * 1024
EXPECTED_DEFAULT_TITLE = "Health.md – Health Data Export"
EXPECTED_SLIDE_IDS = (
    "core-export",
    "export-formats",
    "health-metrics",
    "private-by-design",
    "scheduled-exports",
    "file-preview",
    "home-screen-widgets",
    "direct-cli",
)
SCREENSHOT_TYPES = {
    "phone": "phoneScreenshots",
    "sevenInch": "sevenInchScreenshots",
    "tenInch": "tenInchScreenshots",
}
GRAPHIC_FILES = (
    "icon.png",
    "featureGraphic.png",
    "promoGraphic.png",
    "tvBanner.png",
)
NON_LOCALE_RESOURCE_DIRS = {
    "values-night",
}


class ValidationError(RuntimeError):
    """Raised when authored Play metadata is incomplete or unsafe to publish."""


@dataclass(frozen=True)
class LocaleConfig:
    resource_qualifier: str
    play_locale: str
    status: str
    direction: str

    @property
    def is_reviewed(self) -> bool:
        return self.status == "reviewed"


@dataclass(frozen=True)
class PreparedSummary:
    locales: tuple[str, ...]
    listing_files: int
    image_files: int


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    script_path = Path(__file__).resolve()
    default_android_root = script_path.parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "Convert apps/android/play-console into the Fastlane-style layout "
            "consumed by gplay. Draft locales are excluded unless requested."
        )
    )
    parser.add_argument(
        "--android-root",
        type=Path,
        default=default_android_root,
        help="Path to apps/android (default: inferred from this script)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Canonical output directory (default: <android-root>/build/play-metadata)",
    )
    parser.add_argument(
        "--include-drafts",
        action="store_true",
        help="Include draft locales for offline validation. Publishing output excludes them by default.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate and prepare in a temporary directory without changing build output.",
    )
    return parser.parse_args(argv)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValidationError(f"Missing required file: {path}") from error
    except json.JSONDecodeError as error:
        raise ValidationError(f"Invalid JSON in {path}: {error}") from error


def load_locale_config(android_root: Path) -> tuple[str, tuple[LocaleConfig, ...]]:
    manifest_path = android_root / "play-console" / "locales.json"
    manifest = load_json(manifest_path)
    if manifest.get("schemaVersion") != 1:
        raise ValidationError(f"Unsupported locale manifest schema in {manifest_path}")

    default_locale = manifest.get("defaultLocale")
    raw_locales = manifest.get("locales")
    if not isinstance(default_locale, str) or not isinstance(raw_locales, list):
        raise ValidationError(f"Invalid locale manifest shape in {manifest_path}")

    locales: list[LocaleConfig] = []
    for index, raw in enumerate(raw_locales):
        if not isinstance(raw, dict):
            raise ValidationError(f"Locale entry {index} in {manifest_path} must be an object")
        try:
            locale = LocaleConfig(
                resource_qualifier=raw["resourceQualifier"],
                play_locale=raw["playLocale"],
                status=raw["status"],
                direction=raw["direction"],
            )
        except KeyError as error:
            raise ValidationError(f"Locale entry {index} is missing {error.args[0]}") from error
        if locale.status not in {"reviewed", "draft"}:
            raise ValidationError(f"Invalid locale status for {locale.play_locale}: {locale.status}")
        if locale.direction not in {"ltr", "rtl"}:
            raise ValidationError(f"Invalid direction for {locale.play_locale}: {locale.direction}")
        locales.append(locale)

    play_locales = [locale.play_locale for locale in locales]
    resource_qualifiers = [locale.resource_qualifier for locale in locales]
    if len(play_locales) != len(set(play_locales)):
        raise ValidationError("Duplicate Play locale in play-console/locales.json")
    if len(resource_qualifiers) != len(set(resource_qualifiers)):
        raise ValidationError("Duplicate Android resource qualifier in play-console/locales.json")
    if default_locale not in play_locales:
        raise ValidationError(f"Default locale {default_locale} is not declared")
    default_config = next(locale for locale in locales if locale.play_locale == default_locale)
    if not default_config.is_reviewed:
        raise ValidationError("The default locale must be reviewed")

    validate_android_locale_coverage(android_root, locales)
    return default_locale, tuple(locales)


def validate_android_locale_coverage(android_root: Path, locales: Iterable[LocaleConfig]) -> None:
    resources_root = android_root / "app" / "src" / "main" / "res"
    configured = {locale.resource_qualifier for locale in locales}
    missing = sorted(
        qualifier
        for qualifier in configured
        if not (resources_root / qualifier / "strings.xml").is_file()
    )
    if missing:
        raise ValidationError(
            "Play locales reference missing Android string resources: " + ", ".join(missing)
        )

    discovered = {
        path.name
        for path in resources_root.glob("values*")
        if (path / "strings.xml").is_file() and path.name not in NON_LOCALE_RESOURCE_DIRS
    }
    unconfigured = sorted(discovered - configured)
    if unconfigured:
        raise ValidationError(
            "Android UI locales missing from play-console/locales.json: " + ", ".join(unconfigured)
        )


def read_text(path: Path) -> str:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise ValidationError(f"Missing required file: {path}") from error
    if "\ufffd" in raw:
        raise ValidationError(f"Invalid replacement character in {path}")
    text = raw.strip()
    if not text:
        raise ValidationError(f"Required file is empty: {path}")
    return text


def validate_listing(android_root: Path, locale: LocaleConfig, default_locale: str) -> dict[str, str]:
    source = android_root / "play-console" / "listing" / locale.play_locale
    values = {
        "title.txt": read_text(source / "title.txt"),
        "short_description.txt": read_text(source / "short-description.txt"),
        "full_description.txt": read_text(source / "full-description.txt"),
    }
    lengths = {
        "title.txt": TITLE_LIMIT,
        "short_description.txt": SHORT_DESCRIPTION_LIMIT,
        "full_description.txt": FULL_DESCRIPTION_LIMIT,
    }
    for filename, text in values.items():
        limit = lengths[filename]
        if len(text) > limit:
            raise ValidationError(
                f"{locale.play_locale}/{filename} is {len(text)} characters; maximum is {limit}"
            )
    if locale.play_locale == default_locale and values["title.txt"] != EXPECTED_DEFAULT_TITLE:
        raise ValidationError(
            f"The reviewed default title must remain exactly {EXPECTED_DEFAULT_TITLE!r}"
        )

    full_description = values["full_description.txt"]
    for required_term in ("Health.md", "Health Connect", "FHIR", "Markdown", "JSON", "CSV"):
        if required_term not in full_description:
            raise ValidationError(
                f"{locale.play_locale}/full-description.txt is missing required term {required_term!r}"
            )
    return values


def validate_screenshot_template(android_root: Path, locale: LocaleConfig) -> None:
    template_path = android_root / "play-store-screenshots" / "locales" / f"{locale.play_locale}.json"
    template = load_json(template_path)
    if template.get("schemaVersion") != 1:
        raise ValidationError(f"Unsupported screenshot template schema in {template_path}")
    if template.get("locale") != locale.play_locale:
        raise ValidationError(f"Screenshot template locale mismatch in {template_path}")
    if template.get("status") != locale.status:
        raise ValidationError(f"Screenshot template status mismatch in {template_path}")
    if template.get("direction") != locale.direction:
        raise ValidationError(f"Screenshot template direction mismatch in {template_path}")

    slides = template.get("slides")
    if not isinstance(slides, list):
        raise ValidationError(f"Screenshot template slides must be a list in {template_path}")
    slide_ids = tuple(slide.get("id") for slide in slides if isinstance(slide, dict))
    if slide_ids != EXPECTED_SLIDE_IDS:
        raise ValidationError(
            f"Screenshot template IDs/order differ from the canonical sequence in {template_path}"
        )
    for slide in slides:
        if not isinstance(slide.get("headline"), str) or not slide["headline"].strip():
            raise ValidationError(f"Empty screenshot headline in {template_path}")
        if not isinstance(slide.get("supportingLine"), str) or not slide["supportingLine"].strip():
            raise ValidationError(f"Empty screenshot supporting line in {template_path}")


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        signature = image.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            raise ValidationError(f"Store screenshot must be PNG: {path}")
        length_bytes = image.read(4)
        chunk_type = image.read(4)
        if len(length_bytes) != 4 or chunk_type != b"IHDR":
            raise ValidationError(f"Malformed PNG header: {path}")
        length = struct.unpack(">I", length_bytes)[0]
        ihdr = image.read(length)
        if len(ihdr) < 13:
            raise ValidationError(f"Malformed PNG IHDR: {path}")
        width, height = struct.unpack(">II", ihdr[:8])
        color_type = ihdr[9]
        if color_type in {4, 6}:
            raise ValidationError(f"Google Play screenshots must not contain an alpha channel: {path}")
        return width, height


def validate_screenshot(path: Path) -> None:
    if path.stat().st_size > MAX_SCREENSHOT_BYTES:
        raise ValidationError(f"Screenshot exceeds 8 MB: {path}")
    width, height = png_dimensions(path)
    minimum = min(width, height)
    maximum = max(width, height)
    if minimum < 320 or maximum > 3_840 or maximum > minimum * 2:
        raise ValidationError(
            f"Screenshot dimensions are outside Play limits ({width}x{height}): {path}"
        )


def image_files(source: Path) -> list[Path]:
    if not source.is_dir():
        return []
    unsupported = sorted(
        path.name
        for path in source.iterdir()
        if path.is_file() and path.suffix.lower() not in {".png", ".md"}
    )
    if unsupported:
        raise ValidationError(f"Unsupported store image files in {source}: {', '.join(unsupported)}")
    return sorted(
        (path for path in source.glob("*.png") if path.is_file()),
        key=lambda path: path.name,
    )


def copy_images(android_root: Path, locale: LocaleConfig, destination: Path) -> int:
    copied = 0
    screenshot_root = android_root / "play-console" / "screenshots" / locale.play_locale
    images_destination = destination / "images"
    for source_name, canonical_name in SCREENSHOT_TYPES.items():
        files = image_files(screenshot_root / source_name)
        if not files:
            continue
        minimum_count = 2 if source_name == "phone" else 4
        if not minimum_count <= len(files) <= MAX_SCREENSHOTS_PER_TYPE:
            raise ValidationError(
                f"{locale.play_locale}/{source_name} needs {minimum_count}-{MAX_SCREENSHOTS_PER_TYPE} "
                f"screenshots; found {len(files)}"
            )
        target = images_destination / canonical_name
        target.mkdir(parents=True, exist_ok=True)
        for source in files:
            validate_screenshot(source)
            shutil.copy2(source, target / source.name)
            copied += 1

    graphics_root = android_root / "play-console" / "graphics" / locale.play_locale
    for filename in GRAPHIC_FILES:
        source = graphics_root / filename
        if source.is_file():
            images_destination.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, images_destination / filename)
            copied += 1
    return copied


def prepare_metadata(
    android_root: Path,
    output_dir: Path,
    include_drafts: bool,
) -> PreparedSummary:
    android_root = android_root.resolve()
    default_locale, locales = load_locale_config(android_root)
    selected = tuple(locale for locale in locales if include_drafts or locale.is_reviewed)
    if not selected:
        raise ValidationError("No locales selected for canonical Play metadata")

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    listing_files = 0
    image_count = 0
    for locale in selected:
        listing = validate_listing(android_root, locale, default_locale)
        validate_screenshot_template(android_root, locale)
        locale_destination = output_dir / locale.play_locale
        locale_destination.mkdir(parents=True, exist_ok=True)
        for filename, text in listing.items():
            (locale_destination / filename).write_text(text + "\n", encoding="utf-8")
            listing_files += 1
        image_count += copy_images(android_root, locale, locale_destination)

    return PreparedSummary(
        locales=tuple(locale.play_locale for locale in selected),
        listing_files=listing_files,
        image_files=image_count,
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    android_root = args.android_root.resolve()
    output_dir = (args.output_dir or android_root / "build" / "play-metadata").resolve()
    try:
        if args.check:
            with tempfile.TemporaryDirectory(prefix="healthmd-play-metadata-") as temporary:
                summary = prepare_metadata(
                    android_root=android_root,
                    output_dir=Path(temporary) / "metadata",
                    include_drafts=args.include_drafts,
                )
        else:
            summary = prepare_metadata(
                android_root=android_root,
                output_dir=output_dir,
                include_drafts=args.include_drafts,
            )
    except ValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    scope = "reviewed and draft" if args.include_drafts else "reviewed"
    print(
        f"Prepared {scope} Play metadata for {len(summary.locales)} locale(s): "
        f"{', '.join(summary.locales)}"
    )
    print(f"Validated {summary.listing_files} listing files and {summary.image_files} image files")
    if not args.check:
        print(f"Canonical output: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
