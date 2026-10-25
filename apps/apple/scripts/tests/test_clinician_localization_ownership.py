"""Keep generic-label exceptions tied to a real non-report consumer."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("clinician_localizations", Path(__file__).parents[1] / "validate-clinician-report-localizations.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class SharedUIOwnershipTests(unittest.TestCase):
    def test_current_shared_setup_owns_close_without_exempting_other_legacy_keys(self):
        apple = Path(__file__).resolve().parents[2]
        owned = validator.reviewed_shared_ui_keys(apple)
        self.assertEqual(owned, {"Close"})
        self.assertIn("Blood Glucose", validator.LEGACY_UNREVIEWED_KEYS - owned)

    def test_missing_or_changed_owner_rejects_the_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            apple = Path(directory)
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                validator.reviewed_shared_ui_keys(apple)
            owner = apple / "HealthMd/iOS/SharedSetup/SharedSetupCoordinator.swift"
            owner.parent.mkdir(parents=True)
            owner.write_text('Button("Finish") {}')
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                validator.reviewed_shared_ui_keys(apple)


if __name__ == "__main__":
    unittest.main()
