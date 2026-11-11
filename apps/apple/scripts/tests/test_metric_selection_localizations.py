"""Portable regression boundary for #200's Health Metrics localization slice."""
from __future__ import annotations

from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "validate-metric-selection-localizations.py"
SPEC = importlib.util.spec_from_file_location("metric_selection_localizations", PATH)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class MetricSelectionLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog, cls.manifest, cls.sources = validator.load_inputs()

    def inputs(self) -> tuple[dict, dict, dict[str, str]]:
        return deepcopy(self.catalog), deepcopy(self.manifest), dict(self.sources)

    def test_production_catalog_and_localized_adapter_bindings(self) -> None:
        self.assertEqual(validator.validate(self.catalog, self.manifest, self.sources), [])

    def test_missing_locale_is_rejected_for_every_supported_locale(self) -> None:
        key = "Permission pending"
        for locale in validator.LOCALES:
            with self.subTest(locale=locale):
                catalog, manifest, sources = self.inputs()
                del catalog["strings"][key]["localizations"][locale]
                self.assertIn(f"{locale}: missing localization for {key!r}", validator.validate(catalog, manifest, sources))

    def test_missing_catalog_key_is_rejected(self) -> None:
        catalog, manifest, sources = self.inputs()
        del catalog["strings"]["Permission pending"]
        self.assertEqual(len(validator.validate(catalog, manifest, sources)), 9)

    def test_empty_untranslated_and_unfinished_units_are_rejected(self) -> None:
        for value, state in [("", "translated"), ("Permission pending", "translated"), ("Berechtigung ausstehend", "needs_review")]:
            with self.subTest(value=value, state=state):
                catalog, manifest, sources = self.inputs()
                unit = catalog["strings"]["Permission pending"]["localizations"]["de"]["stringUnit"]
                unit.update(value=value, state=state)
                self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_dropped_changed_duplicated_and_extra_tokens_are_rejected(self) -> None:
        for value in ["Autorisierung ausstehend", "%lld, Autorisierung ausstehend", "%@ %@, Autorisierung ausstehend", "%@ %s, Autorisierung ausstehend"]:
            with self.subTest(value=value):
                catalog, manifest, sources = self.inputs()
                catalog["strings"]["%@, pending Apple permission"]["localizations"]["de"]["stringUnit"]["value"] = value
                self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_positional_reordering_preserves_argument_identity_and_type(self) -> None:
        key = "Apple's vision prescription selector did not complete (%@, code %lld)."
        catalog, manifest, sources = self.inputs()
        unit = catalog["strings"][key]["localizations"]["de"]["stringUnit"]
        unit["value"] = "Fehlercode %2$lld aus %1$@."
        self.assertEqual(validator.validate(catalog, manifest, sources), [])
        unit["value"] = "Fehlercode %1$lld aus %2$@."
        self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_source_link_covers_ternary_computed_and_interpolated_keys(self) -> None:
        source = '''
        Button(requested ? String(localized: "Change Medication Access") : String(localized: "Choose Medications…"))
        return String(localized: "Medication access selected")
        Text("\\(category.displayName), pending Apple permission")
        '''
        self.assertEqual(validator.source_keys(source, self.manifest["keys"]), {
            "Change Medication Access", "Choose Medications…", "Medication access selected", "%@, pending Apple permission",
        })

    def test_key_removed_from_source_requires_explicit_retention_reason(self) -> None:
        catalog, manifest, sources = self.inputs()
        path = "HealthMd/iOS/Views/MetricSelectionView.swift"
        sources[path] = sources[path].replace('Text("No matching metrics")', 'Text("Nothing found")')
        self.assertTrue(any("no longer linked to source: 'No matching metrics'" in e for e in validator.validate(catalog, manifest, sources)))

    def test_raw_metric_names_details_category_labels_and_english_verbs_are_rejected(self) -> None:
        path = "HealthMd/iOS/Views/MetricSelectionView.swift"
        for old, new in [
            ("name: metric.localizedDisplayName,", "name: metric.name,"),
            ("detail: metric.localizedSelectionDetail,", "detail: metric.selectionDetail,"),
            ("$0.localizedDisplayName.localizedCaseInsensitiveContains(trimmedSearch)", "$0.name.localizedCaseInsensitiveContains(trimmedSearch)"),
            (r'\(category.displayName),', r'\(category.rawValue),'),
            ('String(localized: "Change access")', '"Change access"'),
            ('String(localized: "Change Medication Access")', '"Change Medication Access"'),
            ('String(localized: "Disable all standard metrics")', '"Disable all standard metrics"'),
            ('String(localized: "Medication access selected")', '"Medication access selected"'),
            ('String(localized: "Double tap to disable")', r'"Double tap to \(isEnabled ? "disable" : "enable")"'),
        ]:
            with self.subTest(new=new):
                catalog, manifest, sources = self.inputs()
                self.assertIn(old, sources[path])
                sources[path] = sources[path].replace(old, new)
                self.assertTrue(any("binding" in e for e in validator.validate(catalog, manifest, sources)))

    def test_computed_permission_copy_requires_explicit_localization_not_just_catalog_presence(self) -> None:
        path = "HealthMd/iOS/Views/MetricSelectionView.swift"
        for key in self.manifest["sources"][path]["localizedStringKeys"]:
            # The typed error interpolation is covered by the source resolver test;
            # all literal permission/status branches are mutation-tested here.
            if "%" in key:
                continue
            with self.subTest(key=key):
                catalog, manifest, sources = self.inputs()
                localized = f'String(localized: "{key}")'
                self.assertIn(localized, sources[path])
                sources[path] = sources[path].replace(localized, f'"{key}"')
                self.assertTrue(any("missing String(localized:) binding" in e for e in validator.validate(catalog, manifest, sources)))

    def test_shared_metric_control_states_and_category_hints_cannot_regress_to_english(self) -> None:
        path = "HealthMd/iOS/Components/ReadingA11yComponents.swift"
        for text in ["Enabled", "Expanded", "Double tap to expand this category"]:
            with self.subTest(text=text):
                catalog, manifest, sources = self.inputs()
                sources[path] = sources[path].replace(f'String(localized: "{text}")', f'"{text}"')
                self.assertTrue(any("binding" in e for e in validator.validate(catalog, manifest, sources)))

    def test_source_scope_does_not_expand_into_unrelated_settings_rows(self) -> None:
        catalog, manifest, sources = self.inputs()
        path = "HealthMd/iOS/Components/ReadingA11yComponents.swift"
        sources[path] = sources[path].split("// MARK: - Settings rows", 1)[0] + '// MARK: - Settings rows\nText("Unrelated copy")'
        self.assertEqual(validator.validate(catalog, manifest, sources), [])

    def test_locale_inventory_and_retention_cannot_silently_drop_coverage(self) -> None:
        catalog, manifest, sources = self.inputs()
        manifest["locales"].remove("ja")
        self.assertTrue(validator.validate(catalog, manifest, sources))
        catalog, manifest, sources = self.inputs()
        manifest["retainedKeys"]["Permission pending"] = ""
        self.assertTrue(validator.validate(catalog, manifest, sources))


if __name__ == "__main__":
    unittest.main()
