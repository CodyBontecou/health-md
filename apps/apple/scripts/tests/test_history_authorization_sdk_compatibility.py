"""Compile the production history adapter method against pre-27 Apple SDKs."""

import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


APPLE_ROOT = Path(__file__).resolve().parents[2]
ADAPTER = APPLE_ROOT / "HealthMd/Shared/Protocols/SystemHealthStoreAdapter.swift"


@unittest.skipUnless(platform.system() == "Darwin" and shutil.which("xcrun"), "requires Apple SDKs")
class HistoryAuthorizationSDKCompatibilityTests(unittest.TestCase):
    def test_production_history_method_compiles_with_older_iphone_sdk(self):
        sdk_version = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True
        ).strip()
        if int(sdk_version.split(".")[0]) >= 27:
            self.skipTest("this regression requires an SDK without the history boundary API")

        source = ADAPTER.read_text()
        start = source.index("    func historyAuthorizationDates(")
        # Match braces so this compiles the actual method, including its SDK and
        # runtime guards, without unrelated app/UI dependencies or copied logic.
        opening = source.index("{", start)
        depth = 1
        end = opening + 1
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        method = source[start:end]
        probe = """import Foundation
import HealthKit
enum HealthHistoryQueryOutcome {
    case unavailable, failure, boundaries([String: Date])
}
final class SDKCompatibilityProbe {
    let store = HKHealthStore()
    var isAvailable: Bool { true }
""" + method + "\n}\n"

        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
        ).strip()
        with tempfile.TemporaryDirectory(prefix="healthmd-history-sdk-") as folder:
            directory = Path(folder)
            path = directory / "Probe.swift"
            path.write_text(probe)
            result = subprocess.run(
                ["xcrun", "swiftc", "-typecheck", "-sdk", sdk,
                 "-target", "arm64-apple-ios17.0",
                 "-module-cache-path", str(directory / "module-cache"), str(path)],
                capture_output=True, text=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
