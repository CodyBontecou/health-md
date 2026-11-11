#!/usr/bin/env python3
"""Host-only regression for the actual SDK27 workflow receipt comparison."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "compare-history-sdk27-receipts.py"
RECEIPT = """HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
TREE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
ImageOS=macos27 ImageVersion=20261022.0305.3
DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer ARCH=arm64
ProductName: macOS
ProductVersion: 27.0.1
BuildVersion: 26A999
Xcode 27.0
Build version 27A266a
Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
SDK=iphonesimulator VERSION=27.0 PATH=/sdk/simulator TARGET=arm64-apple-ios17.0-simulator
PASS public declaration: iphonesimulator (compilation only)
SDK=iphoneos VERSION=27.0 PATH=/sdk/iphoneos TARGET=arm64-apple-ios17.0
PASS public declaration: iphoneos (compilation only)
SDK=macosx VERSION=27.0 PATH=/sdk/macosx TARGET=arm64-apple-macosx14.0
PASS public declaration: macosx (compilation only)
"""


class SDK27ProvenanceTests(unittest.TestCase):
    def compare(self, producer, consumer):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b = root / "producer.txt", root / "consumer.txt"
            a.write_text(producer)
            b.write_text(consumer)
            result = subprocess.run([sys.executable, str(SCRIPT), str(b), str(a)],
                                    capture_output=True, text=True)
            self.assertEqual(a.read_text(), producer)
            self.assertEqual(b.read_text(), consumer)
            return result

    def test_runner_image_version_is_diagnostic_not_build_identity(self):
        consumer = RECEIPT.replace("20261022.0305.3", "20261023.0307.1")
        result = self.compare(RECEIPT, consumer)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_source_os_toolchain_sdk_and_probe_changes_still_fail(self):
        changes = [
            ("HEAD=aaaa", "HEAD=cccc"), ("TREE=bbbb", "TREE=dddd"),
            ("ImageOS=macos27", "ImageOS=macos26"),
            ("ARCH=arm64", "ARCH=x86_64"),
            ("/Applications/Xcode_27.app", "/Applications/Xcode_26.app"),
            ("ProductVersion: 27.0.1", "ProductVersion: 27.0.2"),
            ("BuildVersion: 26A999", "BuildVersion: 26A998"),
            ("Build version 27A266a", "Build version 27A266b"),
            ("swiftlang-6.4.0.34.1", "swiftlang-6.4.0.35.1"),
            ("VERSION=27.0", "VERSION=26.0"),
            ("/sdk/iphoneos", "/different/iphoneos"),
            ("arm64-apple-ios17.0", "arm64-apple-ios18.0"),
            ("PASS public declaration: macosx", "FAIL public declaration: macosx"),
        ]
        for before, after in changes:
            with self.subTest(field=before):
                result = self.compare(RECEIPT, RECEIPT.replace(before, after))
                self.assertNotEqual(result.returncode, 0)

    def test_missing_or_duplicate_diagnostic_line_fails_closed(self):
        line = "ImageOS=macos27 ImageVersion=20261022.0305.3\n"
        for malformed in [RECEIPT.replace(line, ""), RECEIPT + line]:
            with self.subTest(receipt=malformed):
                self.assertNotEqual(self.compare(malformed, malformed).returncode, 0)

    def test_sdk_qualification_remains_an_explicit_diagnostic_not_a_portable_dependency(self):
        # The native qualification utilities remain usable, but their former
        # five-job hosted topology is no longer a regression requirement.
        repo = SCRIPT.parents[3]
        self.assertTrue(SCRIPT.with_name('qualify-history-authorization-sdk27.sh').is_file())
        text = (repo / '.github/workflows/ci.yml').read_text()
        self.assertNotIn('qualify-history-authorization-sdk27.sh', text)
        self.assertNotIn('compare-history-sdk27-receipts.py', text)
        self.assertIn('scripts/ci/run.py', text)


if __name__ == "__main__":
    unittest.main()
