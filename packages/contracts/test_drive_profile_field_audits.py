"""Drive's local bindings must not widen the portable Shared Setup v2 grammar."""
import json
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent
SETUP = ROOT / "shared-setup" / "v2"


class DriveProfileFieldAuditTests(unittest.TestCase):
    def test_revision_three_preserves_current_fields_and_historical_drive_classifications(self):
        for platform, field_name in (("apple", "field"), ("android", "serialized_field")):
            with self.subTest(platform=platform):
                original = json.loads((SETUP / f"{platform}-profile-field-coverage.json").read_text())
                current = json.loads((SETUP / f"{platform}-profile-field-coverage-v3.json").read_text())
                self.assertEqual(original["schema_version"], 1)
                self.assertEqual(current["schema_version"], 3)
                self.assertEqual(current["schema"], original["schema"])
                self.assertEqual(current["target_contract"], original["target_contract"])
                self.assertEqual(current["target_contract"], {"schema": "healthmd.shared_setup", "schema_version": 2})
                key = lambda row: (row["source_type"], row[field_name])
                old_rows = {key(row): row for row in original["fields"]}
                new_rows = {key(row): row for row in current["fields"]}
                self.assertEqual(len(new_rows), len(current["fields"]), "Audit identities must remain unique")
                for identity, row in old_rows.items():
                    self.assertEqual(new_rows[identity], row, f"Existing classification changed: {identity}")
                expected_additions = {
                    "apple": {("ExportProfile", "googleDriveDestinationID")},
                    "android": {
                        ("ExportProfile", "destinationId"),
                        ("PendingScheduledExportRequest", "driveOperationId"),
                        ("ScheduledProfilePendingExport", "destinationId"),
                    },
                }[platform]
                self.assertEqual(new_rows.keys() - old_rows.keys(), expected_additions)
                for identity in expected_additions:
                    self.assertEqual(new_rows[identity]["disposition"], "prohibited")
                    self.assertIsNone(new_rows[identity]["contract_path"])

    def test_historical_drive_audits_remain_exact_bytes(self):
        expected = {
            "apple": "56a0c3c9c13b3abd414bdd63b3029c7388118b90778e70be356bfa7174ae1bfd",
            "android": "c1fec3f1245fe0506125c28753a15291c1989248d215e8e859bb9117e2cb5f81",
        }
        for platform, digest in expected.items():
            with self.subTest(platform=platform):
                data = (SETUP / f"{platform}-profile-field-coverage-v2.json").read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
                old = json.loads(data)
                current = json.loads((SETUP / f"{platform}-profile-field-coverage-v3.json").read_text())
                key = "field" if platform == "apple" else "serialized_field"
                rows = {(r["source_type"], r[key]): r for r in current["fields"]}
                for row in old["fields"]:
                    self.assertEqual(rows[(row["source_type"], row[key])], row)

    def test_new_drive_binding_references_are_prohibited_not_portable(self):
        for platform, field_name, binding in (
            ("apple", "field", "googleDriveDestinationID"),
            ("android", "serialized_field", "destinationId"),
        ):
            with self.subTest(platform=platform):
                current = json.loads((SETUP / f"{platform}-profile-field-coverage-v3.json").read_text())
                rows = [row for row in current["fields"] if row["source_type"] == "ExportProfile" and row[field_name] == binding]
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0]["disposition"], "prohibited")
                self.assertIsNone(rows[0]["contract_path"])
                self.assertTrue(rows[0].get("reason", rows[0].get("evidence", "")).strip())

    def test_drive_audits_are_registered_contract_authorities(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        contract = next(row for row in manifest["contracts"] if row["id"] == "healthmd.shared_setup" and row["version"] == 2)
        for platform in ("apple", "android"):
            self.assertIn(f"packages/contracts/shared-setup/v2/{platform}-profile-field-coverage-v2.json", contract["authorities"])
            self.assertIn(f"packages/contracts/shared-setup/v2/{platform}-profile-field-coverage-v3.json", contract["authorities"])
        self.assertEqual(contract["status"], "deferred", "A native audit must not promote public availability")


if __name__ == "__main__":
    unittest.main()
