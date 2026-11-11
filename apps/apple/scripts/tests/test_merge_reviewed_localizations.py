from pathlib import Path
import importlib.util
import json
import unittest

SPEC = importlib.util.spec_from_file_location('reviewed_catalog_merge', Path(__file__).resolve().parents[1] / 'merge-reviewed-localizations.py')
assert SPEC and SPEC.loader
merger = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(merger)


class ReviewedCatalogMergeTests(unittest.TestCase):
    def setUp(self):
        self.original = '{"sourceLanguage":"en","strings":{\n"Count %lld": {"comment":"keep metadata","localizations":{"en":{"stringUnit":{"state":"translated","value":"Count %lld"}}}},\n"Untouched": {"comment": "keep exact formatting"}\n},"version":"1.0"}'

    def test_adds_missing_units_and_new_keys_without_reformatting_untouched_entries(self):
        result = merger.merge(self.original, {'de': {'Count %lld': 'Anzahl %lld', 'New %@': 'Neu %@'}})
        before, after = json.loads(self.original), json.loads(result)
        self.assertEqual(after['strings']['Count %lld']['localizations']['en'], before['strings']['Count %lld']['localizations']['en'])
        self.assertEqual(after['strings']['Count %lld']['comment'], 'keep metadata')
        self.assertIn('"Untouched": {"comment": "keep exact formatting"}', result)
        self.assertEqual(after['sourceLanguage'], 'en')
        self.assertEqual(after['version'], '1.0')
        self.assertEqual(after['strings']['New %@']['localizations']['de']['stringUnit']['value'], 'Neu %@')

    def test_idempotent_same_unit_and_rejects_overwrites(self):
        once = merger.merge(self.original, {'de': {'Count %lld': 'Anzahl %lld'}})
        self.assertEqual(merger.merge(once, {'de': {'Count %lld': 'Anzahl %lld'}}), once)
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            merger.merge(once, {'de': {'Count %lld': 'Geändert %lld'}})

    def test_rejects_missing_duplicate_wrong_type_and_unsigned_tokens(self):
        for source, value in [('Count %lld', 'Anzahl'), ('Count %lld', '%d'), ('Count %lld', '%lld %lld'),
                              ('Port %u', 'Port %d'), ('%@ %lld', '%2$@ %1$lld'),
                              ('Export ${date}', 'Export {date}'), ('{date}_{metric}', '{date}_{Metrik}')]:
            with self.subTest(source=source, value=value), self.assertRaisesRegex(ValueError, 'placeholder mismatch'):
                merger.merge(self.original, {'de': {source: value}})

    def test_positional_reordering_and_escaped_percent_do_not_change_argument_identity(self):
        self.assertEqual(merger.token_signature('%@ %% %lld'), merger.token_signature('%2$lld %% %1$@'))
        self.assertEqual(merger.token_signature('%@, %lld percent complete'), merger.token_signature('%1$@：%2$lld%%'))

    def test_rejects_unknown_locale_empty_values_and_duplicate_input_keys(self):
        for maps in [{'xx': {'Hi': 'Hallo'}}, {'de': {'Hi': ''}}, {'de': {'Hi': 3}}]:
            with self.assertRaises(ValueError):
                merger.merge(self.original, maps)
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            merger.load_json('{"Hi":"a","Hi":"b"}')

    def test_handles_escaped_multiline_keys_and_multiple_new_entries(self):
        key = 'A "quoted"\nkey %@'
        raw = json.dumps({'strings': {key: {'comment': 'safe'}}, 'sourceLanguage': 'en'})
        result = merger.merge(raw, {'de': {key: 'Ein %@', 'Second': 'Zweite'}, 'fr': {key: 'Un %@', 'Third': 'Troisième'}})
        data = json.loads(result)['strings']
        self.assertEqual(set(data), {key, 'Second', 'Third'})
        self.assertEqual(set(data[key]['localizations']), {'de', 'fr'})
        self.assertEqual(data[key]['comment'], 'safe')

    def test_empty_catalog_insertion_and_last_entry_update_do_not_overlap(self):
        for original in ['{"strings":{}}', '{"strings":{"First":{}}}']:
            result = merger.merge(original, {'de': {'First': 'Erste', 'Second': 'Zweite'}})
            self.assertEqual(set(json.loads(result)['strings']), {'First', 'Second'})


if __name__ == '__main__':
    unittest.main()
