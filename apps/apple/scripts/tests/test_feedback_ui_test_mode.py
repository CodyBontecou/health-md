"""Execute the actual TestMode launch gate without app SDKs or a simulator."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

APPLE_ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("swiftc"), "Swift compiler is required")
class FeedbackUITestModeTests(unittest.TestCase):
    def test_feedback_scenarios_require_debug_and_explicit_ui_testing(self):
        with tempfile.TemporaryDirectory(prefix="feedback-test-mode-") as directory:
            root = Path(directory)
            # Other TestMode properties use these unrelated export types. No app services run.
            support = root / "Support.swift"
            support.write_text("""
            enum AppleExportDetailPolicy { case summary, detailedTimeSeries, archiveOnly, lossless }
            enum ExportFormat: CaseIterable { case markdown, obsidianBases }
            @main struct Probe {
                static func main() {
                    print(TestMode.rejectsFeedbackHandoffs, TestMode.simulatesFailedMailSheet)
                }
            }
            """)
            for debug in (False, True):
                executable = root / ("debug" if debug else "release")
                command = ["swiftc", "-module-cache-path", str(root / "module-cache")]
                if debug:
                    command += ["-D", "DEBUG"]
                command += [str(APPLE_ROOT / "HealthMd/Shared/TestMode.swift"),
                            str(support), "-o", str(executable)]
                subprocess.run(command, check=True, capture_output=True, text=True)
                for ui_testing in (False, True):
                    for scenario in ("rejected-handoffs", "failed-mail-sheet", "unknown", ""):
                        for arguments_instead_of_environment in (False, True):
                            with self.subTest(debug=debug, ui_testing=ui_testing,
                                              scenario=scenario,
                                              arguments=arguments_instead_of_environment):
                                environment = dict(os.environ)
                                environment.pop("UITEST_FEEDBACK_SCENARIO", None)
                                arguments = [str(executable)]
                                if ui_testing:
                                    arguments += ["--uitesting"]
                                if arguments_instead_of_environment:
                                    arguments += ["-UITEST_FEEDBACK_SCENARIO", scenario]
                                else:
                                    environment["UITEST_FEEDBACK_SCENARIO"] = scenario
                                result = subprocess.run(arguments, env=environment, check=True,
                                                        capture_output=True, text=True)
                                enabled = debug and ui_testing
                                expected = (f"{str(enabled and scenario == 'rejected-handoffs').lower()} "
                                            f"{str(enabled and scenario == 'failed-mail-sheet').lower()}")
                                self.assertEqual(result.stdout.strip(), expected)


if __name__ == "__main__":
    unittest.main()
