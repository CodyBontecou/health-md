"""Pins reviewed UI provenance boundaries; never treats user data as catalog keys."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'scripts/fixtures/apple-localization-handoffs.json'


def validate(sources, manifest):
    errors = []
    for path, spec in manifest.items():
        for binding in spec.get('required', []):
            if binding not in sources[path]:
                errors.append((path, 'missing', binding))
        for binding in spec.get('forbidden', []):
            if binding in sources[path]:
                errors.append((path, 'unsafe', binding))
    return errors


class AppleLocalizationHandoffTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST.read_text())
        cls.sources = {p: (ROOT / p).read_text() for p in cls.manifest}

    def test_reviewed_controlled_and_verbatim_handoffs(self):
        self.assertEqual(validate(self.sources, self.manifest), [])

    def test_each_required_boundary_detects_a_regression(self):
        for path, spec in self.manifest.items():
            for binding in spec.get('required', []):
                sources = dict(self.sources)
                self.assertIn(binding, sources[path])
                sources[path] = sources[path].replace(binding, 'unlocalized_boundary')
                self.assertTrue(validate(sources, self.manifest), (path, binding))

    def test_localizing_user_values_and_english_verb_fragments_are_rejected(self):
        for path, spec in self.manifest.items():
            for binding in spec.get('forbidden', []):
                sources = dict(self.sources)
                sources[path] += '\n' + binding
                self.assertTrue(validate(sources, self.manifest), (path, binding))

    def test_schedule_copy_cannot_mutate_storage_or_use_raw_unit_label_fragments(self):
        source = (ROOT / 'HealthMd/Shared/Utilities/ScheduleDisplayCopy.swift').read_text()
        for forbidden in ['UserDefaults', 'settings.', '.label(for:', 'setEnabled', 'DateFormatter']:
            self.assertNotIn(forbidden, source)
        for unit in ['day', 'week', 'month']:
            self.assertIn(f'case .{unit}:', source)
        self.assertEqual(source.count('count == 1'), 9)


if __name__ == '__main__':
    unittest.main()
