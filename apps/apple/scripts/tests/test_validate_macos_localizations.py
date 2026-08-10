#!/usr/bin/env python3
"""Adversarial tests for the macOS localization validator."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "validate-macos-localizations.py"
SPEC = importlib.util.spec_from_file_location("validate_macos_localizations", VALIDATOR_PATH)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class SourceScanningTests(unittest.TestCase):
    def test_explicit_string_localized_is_scanned(self) -> None:
        scanned = validator.scan_source_text(
            'let value = String(localized: "Not ready")\n'
        )
        self.assertIn(("Not ready", "String(localized:)", 1), scanned)

    def test_explicit_interpolated_string_resolves_catalog_key(self) -> None:
        scanned = validator.scan_source_text(
            'let value = String(localized: "Received \\(recordCount) record(s)")\n'
        )
        raw = scanned[0][0]
        self.assertEqual(
            validator.catalog_key_candidates(raw, {"Received %lld record(s)"}),
            ["Received %lld record(s)"],
        )

    def test_appkit_assignment_accepts_arbitrary_variable_name(self) -> None:
        scanned = validator.scan_source_text(
            'let warning = NSAlert()\nwarning.informativeText = "Choose a folder"\n'
        )
        self.assertIn(("Choose a folder", "AppKit assignment", 2), scanned)

    def test_computed_display_return_is_scanned(self) -> None:
        scanned = validator.scan_source_text(
            'var readinessText: String {\n    return "Not ready"\n}\n'
        )
        self.assertIn(
            ("Not ready", "computed display producer readinessText", 2),
            scanned,
        )


class PartialFailureSummaryTests(unittest.TestCase):
    def test_raw_summary_is_rejected_in_mac_visible_warning_ui(self) -> None:
        preview = validator.APPLE_ROOT / "HealthMd/Shared/Views/ExportPreviewView.swift"
        errors = validator.validate_partial_failure_ui_summary(
            preview,
            "Text(failure.summary)\nText(failure.localizedSummary)\n",
        )
        self.assertEqual(len(errors), 1)
        self.assertIn("use localizedSummary", errors[0])

    def test_raw_summary_remains_allowed_for_query_and_protocol_consumers(self) -> None:
        consumers = [
            validator.APPLE_ROOT / "HealthMd/Shared/Query/HealthMdQueryContextProjector.swift",
            validator.APPLE_ROOT / "HealthMd/Shared/Models/HealthData.swift",
        ]
        for consumer in consumers:
            with self.subTest(consumer=consumer.name):
                self.assertEqual(
                    validator.validate_partial_failure_ui_summary(
                        consumer,
                        "note: failure.summary,\n",
                    ),
                    [],
                )


class PlaceholderTests(unittest.TestCase):
    def test_position_and_type_mismatch_is_rejected(self) -> None:
        source = validator.token_signature("%1$lld of %2$@")
        wrong_position = validator.token_signature("%2$lld sur %1$@")
        wrong_type = validator.token_signature("%1$@ sur %2$lld")
        reordered_correctly = validator.token_signature("%2$@ : %1$lld")
        self.assertNotEqual(source, wrong_position)
        self.assertNotEqual(source, wrong_type)
        self.assertEqual(source, reordered_correctly)


class VariationTests(unittest.TestCase):
    def test_missing_and_typo_plural_branches_are_rejected(self) -> None:
        missing_other = {
            "variations": {"plural": {"one": {"stringUnit": {"value": "one"}}}}
        }
        typo_branch = {
            "variations": {
                "plural": {
                    "one": {"stringUnit": {"value": "one"}},
                    "othre": {"stringUnit": {"value": "other"}},
                }
            }
        }
        missing_leaf = {
            "variations": {
                "plural": {
                    "one": {},
                    "other": {"stringUnit": {"value": "other"}},
                }
            }
        }
        missing_errors = validator.validate_variation_schema(missing_other, "en", "count")
        typo_errors = validator.validate_variation_schema(typo_branch, "en", "count")
        leaf_errors = validator.validate_variation_schema(missing_leaf, "en", "count")
        self.assertTrue(any("missing 'other'" in error for error in missing_errors))
        self.assertTrue(any("othre" in error for error in typo_errors))
        self.assertTrue(any("no stringUnit leaf" in error for error in leaf_errors))


class SourceEqualTests(unittest.TestCase):
    def test_unallowlisted_english_copy_is_rejected(self) -> None:
        errors = validator.validate_source_equal(
            "Continue", "de", "Continue", "Continue", set()
        )
        self.assertEqual(len(errors), 1)
        self.assertIn("not reviewed", errors[0])

        self.assertEqual(
            validator.validate_source_equal(
                "Health.md", "de", "Health.md", "Health.md", {"Health.md"}
            ),
            [],
        )

    def test_positional_syntax_cannot_hide_source_equal_copy(self) -> None:
        errors = validator.validate_source_equal(
            "%lld of %lld",
            "de",
            "%1$lld of %2$lld",
            "%lld of %lld",
            set(),
        )
        self.assertEqual(len(errors), 1)


class MetricRegistryTests(unittest.TestCase):
    def test_generated_registry_names_and_units_have_reviewed_coverage(self) -> None:
        names, units = validator.metric_registry_terms()
        self.assertEqual(len(names), 230)
        self.assertEqual(len(set(names)), 230)
        self.assertIn("Total Sleep", names)
        self.assertIn("bpm", units)

        catalog = validator.json.loads(validator.CATALOG_PATH.read_text())["strings"]
        manifest = validator.json.loads(validator.MANIFEST_PATH.read_text())
        reviewed = set(manifest["keys"])
        for term in names + units + ["Source records only"]:
            self.assertIn(term, catalog)
            self.assertIn(term, reviewed)
            for locale in manifest["locales"]:
                self.assertIn(locale, catalog[term]["localizations"])


if __name__ == "__main__":
    unittest.main()
