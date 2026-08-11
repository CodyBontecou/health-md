from __future__ import annotations

import importlib.util
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "prepare-play-metadata.py"
SPEC = importlib.util.spec_from_file_location("prepare_play_metadata", SCRIPT_PATH)
assert SPEC and SPEC.loader
prepare_play_metadata = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = prepare_play_metadata
SPEC.loader.exec_module(prepare_play_metadata)


class PreparePlayMetadataTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "android"
        self.output = self.root / "build" / "play-metadata"
        self._write_fixture()

    def test_reviewed_output_uses_canonical_names_and_excludes_drafts(self) -> None:
        summary = prepare_play_metadata.prepare_metadata(
            android_root=self.root,
            output_dir=self.output,
            include_drafts=False,
        )

        self.assertEqual(summary.locales, ("en-US",))
        self.assertEqual(summary.listing_files, 3)
        self.assertEqual(summary.image_files, 2)
        self.assertEqual(
            (self.output / "en-US" / "short_description.txt").read_text(encoding="utf-8"),
            "Export Health Connect data to files you control.\n",
        )
        self.assertTrue(
            (self.output / "en-US" / "images" / "phoneScreenshots" / "1.png").is_file()
        )
        self.assertFalse((self.output / "de-DE").exists())

    def test_include_drafts_emits_every_configured_locale(self) -> None:
        summary = prepare_play_metadata.prepare_metadata(
            android_root=self.root,
            output_dir=self.output,
            include_drafts=True,
        )

        self.assertEqual(summary.locales, ("en-US", "de-DE"))
        self.assertTrue((self.output / "de-DE" / "full_description.txt").is_file())

    def test_unmapped_android_ui_locale_fails(self) -> None:
        extra = self.root / "app" / "src" / "main" / "res" / "values-fr"
        extra.mkdir(parents=True)
        (extra / "strings.xml").write_text("<resources />\n", encoding="utf-8")

        with self.assertRaisesRegex(
            prepare_play_metadata.ValidationError,
            "Android UI locales missing",
        ):
            prepare_play_metadata.prepare_metadata(
                android_root=self.root,
                output_dir=self.output,
                include_drafts=True,
            )

    def test_default_title_change_fails(self) -> None:
        title = self.root / "play-console" / "listing" / "en-US" / "title.txt"
        title.write_text("Health.md Export\n", encoding="utf-8")

        with self.assertRaisesRegex(
            prepare_play_metadata.ValidationError,
            "default title must remain exactly",
        ):
            prepare_play_metadata.prepare_metadata(
                android_root=self.root,
                output_dir=self.output,
                include_drafts=False,
            )

    def test_screenshot_template_ids_must_match(self) -> None:
        template_path = self.root / "play-store-screenshots" / "locales" / "de-DE.json"
        template = json.loads(template_path.read_text(encoding="utf-8"))
        template["slides"] = list(reversed(template["slides"]))
        template_path.write_text(json.dumps(template), encoding="utf-8")

        with self.assertRaisesRegex(
            prepare_play_metadata.ValidationError,
            "IDs/order differ",
        ):
            prepare_play_metadata.prepare_metadata(
                android_root=self.root,
                output_dir=self.output,
                include_drafts=True,
            )

    def test_screenshot_with_alpha_channel_fails(self) -> None:
        screenshot = (
            self.root
            / "play-console"
            / "screenshots"
            / "en-US"
            / "phone"
            / "1.png"
        )
        write_png(screenshot, width=320, height=640, color_type=6)

        with self.assertRaisesRegex(
            prepare_play_metadata.ValidationError,
            "must not contain an alpha channel",
        ):
            prepare_play_metadata.prepare_metadata(
                android_root=self.root,
                output_dir=self.output,
                include_drafts=False,
            )

    def _write_fixture(self) -> None:
        for qualifier in ("values", "values-de"):
            resource = self.root / "app" / "src" / "main" / "res" / qualifier
            resource.mkdir(parents=True, exist_ok=True)
            (resource / "strings.xml").write_text("<resources />\n", encoding="utf-8")

        manifest = {
            "schemaVersion": 1,
            "defaultLocale": "en-US",
            "locales": [
                {
                    "resourceQualifier": "values",
                    "playLocale": "en-US",
                    "status": "reviewed",
                    "direction": "ltr",
                },
                {
                    "resourceQualifier": "values-de",
                    "playLocale": "de-DE",
                    "status": "draft",
                    "direction": "ltr",
                },
            ],
        }
        manifest_path = self.root / "play-console" / "locales.json"
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        for locale, title in (
            ("en-US", prepare_play_metadata.EXPECTED_DEFAULT_TITLE),
            ("de-DE", "Health.md – Datenexport"),
        ):
            listing = self.root / "play-console" / "listing" / locale
            listing.mkdir(parents=True, exist_ok=True)
            (listing / "title.txt").write_text(title + "\n", encoding="utf-8")
            (listing / "short-description.txt").write_text(
                "Export Health Connect data to files you control.\n",
                encoding="utf-8",
            )
            (listing / "full-description.txt").write_text(
                "Health.md exports Health Connect records to Markdown, JSON and CSV. "
                "FHIR records remain read-only.\n",
                encoding="utf-8",
            )
            write_template(
                self.root / "play-store-screenshots" / "locales" / f"{locale}.json",
                locale=locale,
                status="reviewed" if locale == "en-US" else "draft",
            )

        phone = self.root / "play-console" / "screenshots" / "en-US" / "phone"
        write_png(phone / "1.png", width=320, height=640)
        write_png(phone / "2.png", width=320, height=640)


def write_template(path: Path, locale: str, status: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    template = {
        "schemaVersion": 1,
        "locale": locale,
        "status": status,
        "direction": "ltr",
        "slides": [
            {
                "id": slide_id,
                "headline": f"Headline {index}",
                "supportingLine": f"Supporting line {index}",
            }
            for index, slide_id in enumerate(prepare_play_metadata.EXPECTED_SLIDE_IDS, start=1)
        ],
    }
    path.write_text(json.dumps(template), encoding="utf-8")


def write_png(path: Path, width: int, height: int, color_type: int = 2) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    channels = 4 if color_type == 6 else 3
    pixel = bytes([0] * channels)
    raw = b"".join(b"\x00" + pixel * width for _ in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)

    def chunk(name: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + name
            + data
            + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    unittest.main()
