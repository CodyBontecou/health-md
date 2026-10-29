"""Reviewed Individual Tracking localization boundary, portable/no native SDK."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("individual_tracking_copy_guard", ROOT / "scripts/validate-metric-selection-localizations.py")
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)
MANIFEST = ROOT / "scripts/fixtures/individual-tracking-localization-keys.json"
VIEW = "HealthMd/iOS/Views/IndividualTrackingView.swift"
COPY = "HealthMd/Shared/Utilities/IndividualTrackingPresentation.swift"


class IndividualTrackingLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog, cls.manifest, cls.sources = validator.load_inputs(MANIFEST)

    def inputs(self):
        return deepcopy(self.catalog), deepcopy(self.manifest), dict(self.sources)

    def test_production_locales_tokens_and_bindings(self):
        self.assertEqual(validator.validate(self.catalog, self.manifest, self.sources), [])

    def test_missing_or_unfinished_locale_and_english_fallback_rejected(self):
        for locale in validator.LOCALES:
            catalog, manifest, sources = self.inputs()
            del catalog["strings"]["Tracked"]["localizations"][locale]
            self.assertTrue(validator.validate(catalog, manifest, sources))
        for value, state in [("", "translated"), ("Tracked", "translated"), ("Erfasst", "needs_review")]:
            catalog, manifest, sources = self.inputs()
            catalog["strings"]["Tracked"]["localizations"]["de"]["stringUnit"].update(value=value, state=state)
            self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_category_name_and_count_argument_types_and_multiplicity_guarded(self):
        key = "%@, tracked: %lld of %lld"
        for value in ["%@ %lld", "%lld %lld %lld", "%@ %@ %lld %lld", "%@ %d %lld"]:
            catalog, manifest, sources = self.inputs()
            catalog["strings"][key]["localizations"]["de"]["stringUnit"]["value"] = value
            self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_filename_helper_tokens_remain_verbatim(self):
        key = "Supports {date}, {time}, {metric}, and {category}."
        catalog, manifest, sources = self.inputs()
        unit = catalog["strings"][key]["localizations"]["ja"]["stringUnit"]
        unit["value"] = unit["value"].replace("{metric}", "{指標}")
        self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_state_count_expansion_and_display_name_handoffs_are_guarded(self):
        for old in [
            "copy.headerLabel(headerStateTitle)",
            "copy.headerState(isEnabled: settings.globalEnabled, count: settings.totalEnabledCount)",
            "copy.toggleHint(isEnabled: settings.globalEnabled)",
            "copy.bulkValue(tracksAll: tracksAllEnabledMetrics)",
            "copy.bulkHint(hasMetrics: !individualTrackableMetrics.isEmpty, tracksAll: tracksAllEnabledMetrics)",
            "copy.trackedTitle(settings.totalEnabledCount)",
            "copy.categoryLabel(category.displayName, tracked: enabledCount, total: enabledMetricsInCategory.count)",
            "copy.expansionHint(isExpanded: isExpanded)",
            "Text(verbatim: metric.localizedDisplayName)",
            "color: settings.totalEnabledCount == 0 ? Color.warning : Color.accent",
            "copy.metricHint(isTracked: settings.shouldTrackIndividually(metric.id), displayName: metric.localizedDisplayName)",
        ]:
            catalog, manifest, sources = self.inputs()
            self.assertIn(old, sources[VIEW])
            sources[VIEW] = sources[VIEW].replace(old, "unlocalized")
            self.assertTrue(validator.validate(catalog, manifest, sources), old)

    def test_raw_previews_and_string_backed_helpers_cannot_regress(self):
        for old in ["Text(verbatim: entryPreview)", "Text(verbatim: value)", "Text(verbatim: title)",
                    "prompt: Text(verbatim: placeholder)", "Text(LocalizedStringKey(helper))",
                    "Text(LocalizedStringKey(subtitle))", ".accessibilityLabel(LocalizedStringKey(accessibilityLabel))",
                    ".accessibilityHint(LocalizedStringKey(accessibilityHint))"]:
            catalog, manifest, sources = self.inputs()
            self.assertIn(old, sources[VIEW])
            sources[VIEW] = sources[VIEW].replace(old, "unlocalized")
            self.assertTrue(validator.validate(catalog, manifest, sources), old)

    def test_dynamic_copy_must_be_localized_as_complete_sentences(self):
        for key in self.manifest["sources"][COPY]["localizedStringKeys"]:
            catalog, manifest, sources = self.inputs()
            raw_literals = [raw for raw, kind, _ in validator.helpers.scan_source_text(sources[COPY], scan_computed_returns=False)
                            if kind == "String(localized:)" and key in validator.helpers.catalog_key_candidates(raw, [key])]
            self.assertTrue(raw_literals, key)
            for raw in raw_literals:
                sources[COPY] = sources[COPY].replace('String(localized: "' + raw + '"', 'String(describing: "' + raw + '"')
            self.assertTrue(any("missing String(localized:)" in e for e in validator.validate(catalog, manifest, sources)), key)

    def test_protection_and_original_settings_bindings_are_guarded(self):
        for old in ["configurationProtection.protecting($settings.globalEnabled)",
                    "configurationProtection.protecting(Binding(", "configurationProtection.protecting(text)",
                    "configurationProtection.protecting(isOn)", "configurationProtection.performConfigurationChange(action)",
                    "text: $settings.entriesFolder,", "text: $settings.filenameTemplate,", "isOn: $settings.useCategoryFolders,"]:
            catalog, manifest, sources = self.inputs()
            sources[VIEW] = sources[VIEW].replace(old, "unguarded")
            self.assertTrue(validator.validate(catalog, manifest, sources), old)

    def test_preview_generators_do_not_localize_or_rewrite_export_identifiers(self):
        previews = self.sources[VIEW].split("private var folderStructurePreview:", 1)[1].split("// MARK: - Category Row Component", 1)[0]
        for forbidden in ["String(localized:", "NSLocalizedString", ".localizedDisplayName", "category.displayName"]:
            self.assertNotIn(forbidden, previews)
        for raw in ["let folderName = category.rawValue", 'name: "Daily Mood"', 'id: "daily_mood"',
                    "settings.filename(for: sampleMetric, date: Date(), time: Date())",
                    'return "\\(settings.entriesFolder)/"', 'return "\\(settings.entriesFolder)/\\n  No metrics selected"',
                    'dateFormatter.dateFormat = "yyyy-MM-dd"', 'dateFormatter.dateFormat = "HH:mm"',
                    'dateFormatter.dateFormat = "yyyy-MM-dd\'T\'HH:mm:ss"',
                    "type: mindfulness", "metric: daily_mood", "valence: 0.7", "feeling: pleasant", "- happy", "- calm"]:
            self.assertIn(raw, previews)

    def test_selection_consistent_mutation_and_filtering_stay_owned_by_existing_settings(self):
        source = self.sources[VIEW]
        setter = source.split("private func setTracksAllEnabledMetrics", 1)[1].split("private func toggleCategory", 1)[0]
        self.assertLess(setter.index("settings.disableAll()"), setter.index("guard shouldTrack else { return }"))
        self.assertIn("for metric in individualTrackableMetrics {", setter)
        self.assertIn("setIndividuallyTracked(metric.id, true)", setter)
        self.assertIn("HealthMetrics.availableInCurrentBuild.filter { metricSelection.isMetricEnabled($0.id) }", source)
        self.assertIn("guard !individualTrackableMetrics.isEmpty else { return false }", source)
        self.assertIn("enabledTrackableMetricCount == individualTrackableMetrics.count", source)
        self.assertIn("categoryMetrics.filter { metricSelection.isMetricEnabled($0.id) }", source)
        self.assertIn("set: { setIndividuallyTracked(metric.id, $0) }", source)


if __name__ == "__main__":
    unittest.main()
