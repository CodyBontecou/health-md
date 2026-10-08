"""Negative controls for the inventoried successor interoperability fixtures."""
import copy
import json
from pathlib import Path
import unittest

import validate

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'packages/contracts/render-input/v2/fixtures'


class SleepAttributionValidationTests(unittest.TestCase):
    def setUp(self):
        self.handoff = json.loads((FIXTURES / 'native-android-v6-handoff.json').read_text())
        self.plan = json.loads((FIXTURES / 'core-android-v6-artifact-plan.json').read_text())

    def check(self):
        validate.validate_sleep_successor_pair(ROOT, self.handoff, self.plan)

    def test_manifest_inventories_prerelease_fixtures(self):
        manifest = json.loads((ROOT / "packages/contracts/manifest.json").read_text())
        entries = [entry for entry in manifest["contracts"] if entry["id"] == "healthmd.sleep_attribution"]
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["status"], "deferred")
        self.assertEqual({Path(item["path"]).name for item in entries[0]["fixtures"]},
                         {"native-android-v6-handoff.json", "core-android-v6-artifact-plan.json"})
        validate.validate_manifest(ROOT)

    def test_native_handoff_and_core_plan(self):
        self.check()

    def test_mixed_authority_is_rejected(self):
        mutations = [
            ('render_configuration', 'calendar_time_zone', 'UTC'),
            ('semantic_configuration', 'calendar_time_zone', 'Invalid/Timezone'),
            ('render_configuration', 'registry_sha256', '0' * 64),
            ('render_configuration', 'profile', 'apple_health_data_v11'),
            ('render_configuration', 'session_id', 'other-session'),
            ('render_configuration', 'profile_revision', 2),
            ('semantic_configuration', 'semantic_input_version', 1),
            ('expected_semantic_result', 'state', 'processing'),
        ]
        original = copy.deepcopy(self.handoff)
        for section, key, value in mutations:
            with self.subTest(section=section, key=key):
                self.handoff = copy.deepcopy(original)
                self.handoff[section][key] = value
                with self.assertRaises(validate.ContractValidationError):
                    self.check()

    def test_missing_and_conflicting_sleep_authority(self):
        original = copy.deepcopy(self.handoff)
        for key, value in [('schema_profile', 'apple-v11'), ('calendar_timezone', 'UTC'),
                           ('sleep_day_attribution', 'night_begins'),
                           ('sleep_owner_day_rule', 'session_start_date'),
                           ('sleep_interval_clipping', 'noon')]:
            for remove in (True, False):
                with self.subTest(key=key, remove=remove):
                    self.handoff = copy.deepcopy(original)
                    authority = self.handoff['expected_semantic_result']['sleep_capture_context']
                    if remove:
                        del authority[key]
                    else:
                        authority[key] = value
                    with self.assertRaises(validate.ContractValidationError):
                        self.check()

    def test_batch_sequence_and_session(self):
        for section in ('semantic_batches', 'render_batches'):
            for key, value in [('session_id', 'other'), ('batch_index', 1), ('final_batch', False)]:
                with self.subTest(section=section, key=key):
                    original = copy.deepcopy(self.handoff)
                    self.handoff[section][0][key] = value
                    with self.assertRaises(validate.ContractValidationError):
                        self.check()
                    self.handoff = original

    def test_plan_identity_and_content(self):
        original = copy.deepcopy(self.plan)
        for key, value in [('request_id', 'other'), ('session_id', 'other'),
                           ('profile', 'apple_health_data_v11'), ('total_byte_count', 0)]:
            with self.subTest(key=key):
                self.plan = copy.deepcopy(original)
                self.plan[key] = value
                with self.assertRaises(validate.ContractValidationError):
                    self.check()
        for key, value in [('artifact_id', '0' * 64), ('sha256', '0' * 64),
                           ('byte_count', 0), ('content_base64', 'invalid!'),
                           ('relative_path', '../escape.md')]:
            with self.subTest(item_key=key):
                self.plan = copy.deepcopy(original)
                self.plan['items'][0][key] = value
                with self.assertRaises(validate.ContractValidationError):
                    self.check()

    def test_case_colliding_paths(self):
        item = copy.deepcopy(self.plan['items'][0])
        item['relative_path'] = item['relative_path'].upper()
        self.plan['items'].append(item)
        with self.assertRaises(validate.ContractValidationError):
            self.check()


class SleepRollupValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = ROOT / 'packages/contracts/rollup-summary/v11/fixtures'
        self.payload = json.loads((self.directory / 'range-v11.json').read_text())

    def test_real_core_artifacts_and_manifest(self):
        for artifact in self.directory.iterdir():
            validate.validate_sleep_rollup_fixture(ROOT, artifact)
        validate.validate_manifest(ROOT)

    def test_invalid_source_or_sleep_authority_is_rejected(self):
        original = copy.deepcopy(self.payload)
        for key, value in [('schema_version', 9), ('source_schema_version', 8),
                           ('rollup_rules_version', 8), ('source_schema_profile', 'apple-v8'),
                           ('schema_profile', 'apple-v11'), ('calendar_timezone', 'Invalid/Timezone')]:
            with self.subTest(key=key):
                changed = copy.deepcopy(original)
                changed[key] = value
                with self.assertRaises(validate.ContractValidationError):
                    validate.validate_sleep_rollup_authority(changed, 'negative synthetic range')
        for key in original['time_context']:
            changed = copy.deepcopy(original)
            del changed['time_context'][key]
            with self.subTest(missing=key), self.assertRaises(validate.ContractValidationError):
                validate.validate_sleep_rollup_authority(changed, 'negative incomplete range')
        for key, value in [('calendar_timezone', 'UTC'), ('sleep_day_attribution', 'night_begins'),
                           ('sleep_interval_clipping', 'noon'), ('timestamp_timezone', 'America/New_York')]:
            changed = copy.deepcopy(original)
            changed['time_context'][key] = value
            with self.subTest(conflict=key), self.assertRaises(validate.ContractValidationError):
                validate.validate_sleep_rollup_authority(changed, 'negative conflicting range')


if __name__ == '__main__':
    unittest.main()
