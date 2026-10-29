"""Portable Daily Note Injection copy boundary; no platform SDK or device required."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("reviewed_daily_note_copy", ROOT / "scripts/validate-metric-selection-localizations.py")
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)
MANIFEST = ROOT / "scripts/fixtures/daily-note-localization-keys.json"
VIEW = "HealthMd/iOS/Views/DailyNoteInjectionView.swift"
COPY = "HealthMd/Shared/Utilities/DailyNoteInjectionPresentation.swift"


class DailyNoteLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog, cls.manifest, cls.sources = validator.load_inputs(MANIFEST)

    def inputs(self):
        return deepcopy(self.catalog), deepcopy(self.manifest), dict(self.sources)

    def test_production_locale_token_and_source_bindings(self):
        self.assertEqual(validator.validate(self.catalog, self.manifest, self.sources), [])

    def test_display_dependencies_and_english_plural_source_are_complete(self):
        for key in self.manifest["displayDependencies"]:
            for locale in validator.LOCALES:
                units = validator.helpers.leaves(self.catalog["strings"][key]["localizations"][locale])
                self.assertTrue(units)
                self.assertTrue(all(u["state"] == "translated" and u["value"].strip() for u in units.values()))
        for key in self.manifest["pluralKeys"]:
            for locale in ["en"] + validator.LOCALES:
                plural = self.catalog["strings"][key]["localizations"][locale]["variations"]["plural"]
                self.assertEqual(set(plural), validator.helpers.EXPECTED_PLURAL_BRANCHES[locale])
                for branch in plural.values():
                    self.assertEqual(branch["stringUnit"]["state"], "translated")
                    self.assertEqual(validator.helpers.token_signature(branch["stringUnit"]["value"]), validator.helpers.token_signature(key))

    def test_missing_empty_unfinished_and_english_fallbacks_are_rejected(self):
        for locale in validator.LOCALES:
            catalog, manifest, sources = self.inputs()
            del catalog["strings"]["Preview Path"]["localizations"][locale]
            self.assertTrue(validator.validate(catalog, manifest, sources))
        for value, state in [("", "translated"), ("Preview Path", "translated"), ("Pfadvorschau", "needs_review")]:
            catalog, manifest, sources = self.inputs()
            catalog["strings"]["Preview Path"]["localizations"]["de"]["stringUnit"].update(value=value, state=state)
            self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_plural_branches_and_every_branch_token_are_guarded(self):
        for key in self.manifest["pluralKeys"]:
            catalog, manifest, sources = self.inputs()
            del catalog["strings"][key]["localizations"]["de"]["variations"]["plural"]["one"]
            self.assertTrue(validator.validate(catalog, manifest, sources))
            catalog, manifest, sources = self.inputs()
            catalog["strings"][key]["localizations"]["ja"]["variations"]["plural"]["other"]["stringUnit"]["value"] = "%@ 個"
            self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_warning_argument_cannot_be_removed_duplicated_or_changed(self):
        key = "With Folder set to Daily, notes are written to Daily/… at the vault root, not %@/Daily/…."
        for value in ["Pfad", "%lld/Daily/…", "%@/%@/Daily/…"]:
            catalog, manifest, sources = self.inputs()
            catalog["strings"][key]["localizations"]["de"]["stringUnit"]["value"] = value
            self.assertTrue(any("token mismatch" in e for e in validator.validate(catalog, manifest, sources)))

    def test_paths_placeholders_and_warning_are_not_reinterpreted_as_localization_keys(self):
        for path, old, new in [
            (VIEW, 'Text(verbatim: settings.previewPath(for: Date()))', 'Text(LocalizedStringKey(settings.previewPath(for: Date())))'),
            (VIEW, 'prompt: Text(verbatim: placeholder)', 'prompt: Text(LocalizedStringKey(placeholder))'),
            (VIEW, 'Text(verbatim: message)', 'Text(LocalizedStringKey(message))'),
            (VIEW, 'Text(verbatim: title)', 'Text(LocalizedStringKey(title))'),
            (VIEW, 'DailyNoteInjectionPresentation.vaultRootWarning(healthSubfolder, locale: locale)', 'healthSubfolder'),
            (COPY, 'not \\(healthSubfolder)/Daily/….', 'not \\(healthSubfolder.trimmingCharacters(in: .whitespacesAndNewlines))/Daily/….'),
        ]:
            with self.subTest(old=old):
                catalog, manifest, sources = self.inputs()
                self.assertIn(old, sources[path])
                sources[path] = sources[path].replace(old, new)
                self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_state_count_and_string_backed_accessibility_handoffs_are_guarded(self):
        for old, new in [
            ('.accessibilityValue(copy.statusTitle)', '.accessibilityValue("Enabled")'),
            ('.accessibilityLabel(copy.headerLabel)', '.accessibilityLabel("Daily Note Injection")'),
            ('.accessibilityHint(copy.toggleHint)', '.accessibilityHint("Enable")'),
            ('title: copy.metricsTitle,', 'title: "2 Metrics",'),
            ('.accessibilityValue(copy.metricsAccessibilityValue)', '.accessibilityValue("2 metrics enabled")'),
            ('.accessibilityHint(LocalizedStringKey(accessibilityHint))', '.accessibilityHint(accessibilityHint)'),
            ('.accessibilityLabel(LocalizedStringKey(accessibilityLabel))', '.accessibilityLabel(accessibilityLabel)'),
        ]:
            catalog, manifest, sources = self.inputs()
            self.assertIn(old, sources[VIEW])
            sources[VIEW] = sources[VIEW].replace(old, new)
            self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_warning_rendering_is_verbatim_but_static_callout_copy_stays_localizable(self):
        info = self.sources[VIEW].split("private func infoRow", 1)[1].split("// MARK: - Card Helpers", 1)[0]
        self.assertIn("Text(verbatim: message)", info)
        self.assertNotIn("Text(LocalizedStringKey(message))", info)
        callout = self.sources[VIEW].split("private func calloutCard", 1)[1].split("private var rowDivider", 1)[0]
        self.assertIn("Text(LocalizedStringKey(message))", callout)

    def test_configuration_protection_and_settings_bindings_are_preserved(self):
        for old, new in [
            ('configurationProtection.protecting($settings.enabled)', '$settings.enabled'),
            ('configurationProtection.protecting(isOn)', 'isOn'),
            ('configurationProtection.protecting(text)', 'text'),
            ('text: $settings.filenamePattern,', 'text: .constant("{date}"),'),
            ('isOn: $settings.dailyNotesOnly,', 'isOn: .constant(true),'),
        ]:
            catalog, manifest, sources = self.inputs()
            self.assertIn(old, sources[VIEW])
            sources[VIEW] = sources[VIEW].replace(old, new)
            self.assertTrue(validator.validate(catalog, manifest, sources))

    def test_count_and_state_copy_must_use_localization_calls(self):
        for key in ["No metrics enabled", "Double tap to enable daily note injection", "Double tap to disable daily note injection"]:
            catalog, manifest, sources = self.inputs()
            sources[COPY] = sources[COPY].replace(f'String(localized: "{key}",', f'String(describing: "{key}",')
            self.assertTrue(any("missing String(localized:)" in e for e in validator.validate(catalog, manifest, sources)))


if __name__ == "__main__":
    unittest.main()
