"""Every hand-written Info.plist declares the development region.

Without CFBundleDevelopmentRegion, a bundle that has no lproj for the user's language (the watch app
compiles no en.lproj from its string catalog) falls back to its first localization, so the Apple
Watch dashboard showed German labels to English users (fixed in 4.0.1).
"""

import plistlib
import re
import unittest
from pathlib import Path

APPLE = Path(__file__).resolve().parents[2]
PROJECT = APPLE / "HealthMd.xcodeproj" / "project.pbxproj"


def hand_written_info_plists() -> list[Path]:
    text = PROJECT.read_text(encoding="utf-8")
    variables = dict(re.findall(r"\b(HEALTHMD_[A-Z_]+_INFO_PLIST) = ([^;]+);", text))
    paths = set()
    for value in re.findall(r"\bINFOPLIST_FILE = ([^;]+);", text):
        value = value.strip().strip('"')
        match = re.fullmatch(r"\$\((\w+)\)", value)
        if match:
            value = variables.get(match.group(1), "").strip().strip('"')
        if value and value != "YES":
            paths.add(APPLE / value)
    return sorted(paths)


class InfoPlistDevelopmentRegionTests(unittest.TestCase):
    def test_every_hand_written_info_plist_declares_development_region(self):
        plists = hand_written_info_plists()
        self.assertIn(APPLE / "HealthMdWatch" / "Info.plist", plists)
        for path in plists:
            with self.subTest(plist=str(path.relative_to(APPLE))):
                with path.open("rb") as handle:
                    info = plistlib.load(handle)
                self.assertEqual(info.get("CFBundleDevelopmentRegion"), "$(DEVELOPMENT_LANGUAGE)")


if __name__ == "__main__":
    unittest.main()
