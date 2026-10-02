"""Behavior tests for the registry's product/UI ownership boundary."""
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "import-native-registry.py"
SPEC = importlib.util.spec_from_file_location("native_registry_importer", SCRIPT)
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


class CoreCapabilitiesTests(unittest.TestCase):
    def test_support_parity_does_not_change_pinned_core_capabilities(self):
        export = {"id": "export.daily-files", "platforms": {"apple": {"state": "available"}}}
        direct = {"id": "direct.cli_agent_wake", "platforms": {"android": {"state": "available"}}}
        support = {"id": "support.local-reporting-fallback", "platforms": {"apple": {"state": "available"}}}
        inventory = {"capabilities": [support, export, direct]}
        self.assertEqual(IMPORTER.core_capabilities(inventory), [export, direct])
        self.assertEqual(inventory["capabilities"], [support, export, direct], "Do not mutate product parity")

    def test_existing_capabilities_and_order_are_preserved(self):
        capabilities = [{"id": identifier} for identifier in (
            "export.daily-files", "android.planned-workouts", "setup.share-portable-configuration",
            "source.private-platform-database", "core.shared-rust-profile-engine",
        )]
        self.assertEqual(IMPORTER.core_capabilities({"capabilities": capabilities}), capabilities)

    def test_empty_or_support_only_inventory_yields_no_core_capabilities(self):
        self.assertEqual(IMPORTER.core_capabilities({"capabilities": []}), [])
        self.assertEqual(IMPORTER.core_capabilities({"capabilities": [{"id": "support.future-ui"}]}), [])


if __name__ == "__main__":
    unittest.main()
