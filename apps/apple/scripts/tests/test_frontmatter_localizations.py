"""Bounded copy/source checks; native XCTest owns actual Foundation/value behavior."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("reviewed_editor_localizations", ROOT / "scripts/validate-metric-selection-localizations.py")
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)
MANIFEST = ROOT / "scripts/fixtures/frontmatter-localization-keys.json"
VIEW = "HealthMd/iOS/Views/FormatCustomizationView.swift"
CONTROLS = "HealthMd/iOS/Components/FormatA11yComponents.swift"
COPY = "HealthMd/Shared/Utilities/FrontmatterFieldPresentation.swift"


class FrontmatterLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog, cls.manifest, cls.sources = validator.load_inputs(MANIFEST)

    def inputs(self):
        return deepcopy(self.catalog), deepcopy(self.manifest), dict(self.sources)

    def test_production_slice_and_source_handoffs(self):
        self.assertEqual(validator.validate(self.catalog, self.manifest, self.sources), [])

    def test_existing_display_dependencies_cover_every_supported_locale(self):
        # French "Nutrition", for example, legitimately equals English. Do not
        # turn shared words into false-positive untranslated-copy reports.
        for key in self.manifest["displayDependencies"]:
            for locale in validator.LOCALES:
                with self.subTest(key=key, locale=locale):
                    leaves = validator.helpers.leaves(self.catalog["strings"][key]["localizations"][locale])
                    self.assertTrue(leaves)
                    for unit in leaves.values():
                        self.assertEqual(unit["state"], "translated")
                        self.assertTrue(unit["value"].strip())

    def test_missing_locale_empty_english_and_unfinished_units_are_rejected(self):
        for locale in validator.LOCALES:
            catalog, manifest, sources = self.inputs()
            del catalog["strings"]["Save Name"]["localizations"][locale]
            self.assertTrue(validator.validate(catalog, manifest, sources))
        for value, state in [("", "translated"), ("Save Name", "translated"), ("Namen speichern", "new")]:
            catalog, manifest, sources = self.inputs()
            catalog["strings"]["Save Name"]["localizations"]["de"]["stringUnit"].update(value=value, state=state)
            self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_rename_and_count_tokens_cannot_be_dropped_duplicated_or_changed(self):
        for key, value in [("Enter a custom name for %@.", "Nom"), ("%@ renamed to %@", "%@"),
                           ("Enabled: %lld of %lld", "%lld / %@"), ("Enabled: %lld of %lld", "%lld / %lld / %lld")]:
            catalog, manifest, sources = self.inputs()
            catalog["strings"][key]["localizations"]["fr"]["stringUnit"]["value"] = value
            self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_positional_rename_tokens_can_reorder_but_not_change_identity(self):
        catalog, manifest, sources = self.inputs()
        unit = catalog["strings"]["%@ renamed to %@"]["localizations"]["de"]["stringUnit"]
        unit["value"] = "%2$@ ist der neue Name für %1$@"
        self.assertEqual(validator.validate(catalog, manifest, sources), [])
        unit["value"] = "%1$@ ist der neue Name für %1$@"
        self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_source_keys_include_dialog_actions_rename_interpolation_and_state_copy(self):
        source = '.action("Save Name")\nText("Enter a custom name for \\($0).")\nString(localized: "Included in frontmatter")'
        self.assertEqual(validator.source_keys(source, self.manifest["keys"]), {"Save Name", "Enter a custom name for %@.", "Included in frontmatter"})

    def test_opaque_keys_values_and_localized_headers_have_enforced_handoffs(self):
        for path, old, new in [
            (VIEW, 'Text(LocalizedStringKey(category.name))', 'Text(category.name)'),
            (VIEW, 'LocalizedStringKey("\\(renameTargetKey ?? "")")', 'LocalizedStringKey(renameTargetKey ?? "")'),
            (VIEW, 'value: FrontmatterFieldPresentation.customValue(value)', 'value: String(localized: String.LocalizationValue(stringLiteral: value))'),
            (CONTROLS, 'Text(verbatim: key)', 'Text(LocalizedStringKey(key))'),
            (CONTROLS, 'Text(verbatim: value)', 'Text(LocalizedStringKey(value))'),
            (CONTROLS, 'Text(verbatim: copy.originalKey)', 'Text(LocalizedStringKey(copy.originalKey))'),
            (CONTROLS, '.accessibilityHint(copy.accessibilityHint)', '.accessibilityHint("Enable field")'),
            (CONTROLS, 'Toggle(isOn: $isEnabled)', 'Toggle(isOn: .constant(false))'),
            (COPY, ' : value', ' : value.trimmingCharacters(in: .whitespacesAndNewlines)'),
        ]:
            with self.subTest(old=old):
                catalog, manifest, sources = self.inputs()
                self.assertIn(old, sources[path])
                sources[path] = sources[path].replace(old, new)
                self.assertTrue(any("binding" in e for e in validator.validate(catalog, manifest, sources)))

    def test_state_copy_requires_localization_not_english_interpolated_verbs(self):
        for key in self.manifest["sources"][COPY]["localizedStringKeys"]:
            if "%" in key:
                continue
            catalog, manifest, sources = self.inputs()
            sources[COPY] = sources[COPY].replace(f'String(localized: "{key}",', f'String(describing: "{key}",')
            self.assertTrue(any("missing String(localized:)" in e for e in validator.validate(catalog, manifest, sources)))

    def test_surrounding_format_markdown_and_template_components_are_outside_scope(self):
        catalog, manifest, sources = self.inputs()
        sources[VIEW] = 'Text(category.name)\n' + sources[VIEW] + '\nText(category.name)'
        sources[CONTROLS] = sources[CONTROLS] + '\nText(LocalizedStringKey(value))'
        self.assertEqual(validator.validate(catalog, manifest, sources), [])
        sources[VIEW] = sources[VIEW].replace('// MARK: - Frontmatter Customization View', '// missing start')
        self.assertTrue(any("source boundary" in e for e in validator.validate(catalog, manifest, sources)))

    def test_technical_keys_and_grouping_identities_are_not_localized(self):
        source = self.sources[VIEW].split('private var fieldCategories:', 1)[1].split('// MARK: - Frontmatter Field Row', 1)[0]
        groups = re.findall(r'\("([^"]+)", \[([^\]]+)\]\)', source)
        actual = [(name, re.findall(r'"([^"]+)"', prefixes)) for name, prefixes in groups]
        self.assertEqual(actual, [
            ("Sleep", ["sleep_"]),
            ("Activity", ["steps", "active_", "basal_", "exercise_", "stand_", "flights_", "walking_running", "cycling", "swimming", "wheelchair"]),
            ("Heart", ["resting_heart", "walking_heart", "average_heart", "heart_rate", "hrv"]),
            ("Vitals", ["respiratory", "blood_oxygen", "body_temperature", "blood_pressure", "blood_glucose"]),
            ("Body", ["weight", "height", "bmi", "body_fat", "lean_body", "waist"]),
            ("Nutrition", ["dietary", "protein", "carbohydrates", "fat", "saturated", "fiber", "sugar", "sodium", "cholesterol", "water", "caffeine"]),
            ("Mindfulness", ["mindful"]),
            ("Mobility", ["walking_speed", "step_length", "double_support", "walking_asymmetry", "stair_", "six_min"]),
            ("Hearing", ["headphone", "environmental"]), ("Workouts", ["workout"]),
        ])
        for binding in ['config.customFields[newFieldKey] = newFieldValue', 'config.placeholderFields.append(newPlaceholderKey)',
                        'config.fields[index].customKey = newKey', 'config.fields[index].customKey = config.fields[index].originalKey']:
            self.assertIn(binding, self.sources[VIEW])


if __name__ == "__main__":
    unittest.main()
