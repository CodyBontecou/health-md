"""Check the Siri metadata rule surfaced by ASC upload error 90626."""
import re
import unittest
from pathlib import Path


class AppIntentDescriptionTests(unittest.TestCase):
    def test_descriptions_do_not_name_mac_hardware(self):
        root = Path(__file__).resolve().parents[2] / "HealthMd" / "iOS" / "AppIntents"
        descriptions = [
            (path, match.group(1))
            for path in root.rglob("*.swift")
            for match in re.finditer(r'IntentDescription\(\s*"((?:[^"\\]|\\.)*)"', path.read_text())
        ]
        self.assertTrue(descriptions, "Expected App Intent descriptions to validate")
        for path, description in descriptions:
            with self.subTest(file=path.name, description=description):
                self.assertIsNone(re.search(r"\bmac\b", description, re.IGNORECASE))


if __name__ == "__main__":
    unittest.main()
