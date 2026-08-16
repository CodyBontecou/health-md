#!/usr/bin/env python3
"""Adversarial tests for the App Store metadata validator."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "validate-app-store-metadata.py"
SPEC = importlib.util.spec_from_file_location("validate_app_store_metadata", VALIDATOR_PATH)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def run_against(tree: dict[str, str]) -> tuple[int, list[str]]:
    """Run the validator against a metadata tree; return (main rc, errors)."""
    import contextlib
    import io

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, body in tree.items():
            target = root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
        validator.APP_INFO_DIR = root / "app-info"
        validator.VERSION_DIR = root / "version"
        errors: list[str] = []
        app_info = validator.validate_app_info(errors)
        validator.validate_version(errors, app_info)
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            rc = validator.main()
        return rc, errors


def app_info(name: str, subtitle: str) -> str:
    return json.dumps(
        {"name": name, "subtitle": subtitle, "privacyPolicyUrl": "https://example.com/p"},
        ensure_ascii=False,
    )


def version_file(keywords: str, *, whats_new: str = "Fixes") -> str:
    return json.dumps(
        {
            "description": "Description",
            "keywords": keywords,
            "marketingUrl": "https://example.com",
            "supportUrl": "https://example.com/s",
            "whatsNew": whats_new,
        },
        ensure_ascii=False,
    )


VALID_APP_INFO = app_info("Health.md", "Daily Health Journal & Export")
VALID_VERSION = version_file("obsidian,hrv,sleep,markdown,tracker")


class KeywordFieldTests(unittest.TestCase):
    def test_valid_fields_pass(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": VALID_VERSION,
            }
        )
        self.assertEqual((rc, errors), (0, []))

    def test_over_limit_keywords_fail(self) -> None:
        keywords = ",".join(["abcdefghij"] * 10)  # 109 chars
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": version_file(keywords),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("109 chars" in e for e in errors))

    def test_space_after_comma_fails(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": version_file("obsidian, hrv"),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("space after a comma" in e for e in errors))

    def test_duplicate_term_fails(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": version_file("obsidian,OBSIDIAN,hrv"),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("duplicate keyword term" in e for e in errors))

    def test_exact_visible_token_duplicate_fails(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": app_info("Health.md", "Daily Health Journal & Export"),
                "version/3.0.6/en-US.json": version_file("obsidian,journal,hrv"),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("visible name/subtitle token" in e for e in errors))

    def test_clean_checkout_without_version_dir_passes(self) -> None:
        rc, errors = run_against({"app-info/en-US.json": VALID_APP_INFO})
        self.assertEqual((rc, errors), (0, []))


if __name__ == "__main__":
    unittest.main()
