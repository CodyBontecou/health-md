"""Whole catalog boundary plus small negative controls (portable, no Apple SDK)."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('apple_catalog_coverage', ROOT / 'scripts/validate-apple-localizations.py')
assert SPEC and SPEC.loader
coverage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(coverage)


def fixture(key='Count %lld', value='Anzahl %lld'):
    return {'sourceLanguage': 'en', 'strings': {key: {'localizations': {
        locale: {'stringUnit': {'state': 'translated', 'value': value}} for locale in coverage.LOCALES
    }}}}


class AppleLocalizationCoverageTests(unittest.TestCase):
    def test_entire_production_catalog_has_complete_target_locales_and_tokens(self):
        self.assertEqual(coverage.validate(coverage.merger.load_json(coverage.CATALOG.read_text()), coverage.merger.load_json(coverage.EXEMPTIONS.read_text())), [])

    def test_missing_any_supported_locale_fails(self):
        for locale in coverage.LOCALES:
            data = fixture()
            del data['strings']['Count %lld']['localizations'][locale]
            self.assertTrue(any('missing localization' in e for e in coverage.validate(data, {})))

    def test_empty_unfinished_or_wrong_argument_fails(self):
        for value, state in [('', 'translated'), ('Anzahl %lld', 'new'), ('%d', 'translated'), ('%lld %lld', 'translated')]:
            data = fixture()
            data['strings']['Count %lld']['localizations']['de']['stringUnit'].update(value=value, state=state)
            self.assertTrue(coverage.validate(data, {}))

    def test_positional_reordering_and_symbolic_english_reference_are_supported(self):
        data = fixture('report_count', 'Wert %1$lld: %2$@')
        data['strings']['report_count']['localizations']['en'] = {'stringUnit': {'state': 'translated', 'value': '%lld records: %@'}}
        self.assertEqual(coverage.validate(data, {}), [])
        data['strings']['report_count']['localizations']['de']['stringUnit']['value'] = '%1$@: %2$lld'
        self.assertTrue(coverage.validate(data, {}))

    def test_exemptions_cannot_hide_prose_or_stale_keys(self):
        data = fixture()
        self.assertTrue(coverage.validate(data, {'Count %lld': 'Please ignore this UI'}))
        self.assertTrue(coverage.validate(data, {'Missing': 'Not in catalog'}))
        self.assertTrue(coverage.validate(data, {'': ''}))
        self.assertEqual(coverage.validate({'sourceLanguage': 'en', 'strings': {': %@': {}}}, {': %@': 'Punctuation only'}), [])

    def test_brace_and_app_shortcut_parameters_are_verbatim(self):
        data = fixture('Export ${date} to {folder}', 'Export ${date} nach {folder}')
        self.assertEqual(coverage.validate(data, {}), [])
        data['strings']['Export ${date} to {folder}']['localizations']['de']['stringUnit']['value'] = 'Export {date} nach {Ordner}'
        self.assertTrue(coverage.validate(data, {}))

    def test_all_variation_leaves_are_checked(self):
        data = fixture()
        data['strings']['Count %lld']['localizations']['de'] = {'variations': {'plural': {
            'one': {'stringUnit': {'state': 'translated', 'value': 'Anzahl %lld'}},
            'other': {'stringUnit': {'state': 'new', 'value': 'Anzahl %lld'}}
        }}}
        self.assertTrue(coverage.validate(data, {}))
        data['strings']['Count %lld']['localizations']['de']['variations']['plural']['other']['stringUnit']['state'] = 'translated'
        self.assertEqual(coverage.validate(data, {}), [])


if __name__ == '__main__':
    unittest.main()
