from pathlib import Path
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['apps/apple/HealthMd', 'apps/android/app/src/main/java', 'apps/android/app/src/play/java']
CLEANUP = 'apps/apple/HealthMd/Shared/Utilities/RetiredAnalyticsCleanup.swift'
CLAIMS = 'apps/apple/HealthMd/iOS/Views/MyselfClaimView.swift'

class RemovedAnalyticsTests(unittest.TestCase):
    def test_analytics_retirement_preserves_scheduling_identifier_disclosures(self):
        schema = (ROOT / 'apps/apple/worker/receipt-verifier/migrations/0001_init.sql').read_text()
        self.assertRegex(schema, r'CREATE TABLE devices[\s\S]+apns_token\s+TEXT NOT NULL')
        manifest = plistlib.loads((ROOT / 'apps/apple/HealthMd/PrivacyInfo.xcprivacy').read_bytes())
        declarations = {row['NSPrivacyCollectedDataType']: row for row in manifest['NSPrivacyCollectedDataTypes']}
        device = declarations['NSPrivacyCollectedDataTypeDeviceID']
        self.assertIn('NSPrivacyCollectedDataTypePurposeAppFunctionality', device['NSPrivacyCollectedDataTypePurposes'])
        self.assertTrue(device['NSPrivacyCollectedDataTypeLinked'])
        self.assertFalse(device['NSPrivacyCollectedDataTypeTracking'])
        candidate = json.loads((ROOT / 'docs/launch/paid-access/app-privacy-candidate.json').read_text())
        self.assertNotIn('DEVICE_ID', candidate['analyticsTypesToRemoveAfterRetirement'])
        scheduling_id = next(row for row in candidate['candidateDeclarations'] if row['dataType'] == 'DEVICE_ID')
        self.assertIn('APP_FUNCTIONALITY', scheduling_id['purposes'])
        self.assertTrue(scheduling_id['linkedToIdentity'])
        self.assertFalse(scheduling_id['tracking'])

    def test_no_collection_or_override_path_in_application_sources(self):
        forbidden = re.compile(r'PricingAnalyticsClient|OnboardingAnalyticsClient|Cloudflare(?:Pricing|Onboarding)AnalyticsTransport|AppleAdsAttributionCollector|AAAttribution|PlayInstallReferrerSource|/v1/events|PRICING_ANALYTICS_ENDPOINT_URL|ONBOARDING_ANALYTICS_ENDPOINT_URL')
        for source in SOURCES:
            for path in (ROOT / source).rglob('*'):
                if path.suffix in ('.swift', '.kt'):
                    self.assertIsNone(forbidden.search(path.read_text()), str(path.relative_to(ROOT)))
        if CLAIMS:
            text = (ROOT / CLAIMS).read_text()
            self.assertIn('static let isEnabled = false', text)
            self.assertNotIn('static let isEnabled = true', text)

    @unittest.skipUnless(shutil.which('xcrun'), 'Swift host toolchain required')
    def test_upgrade_erases_analytics_and_preserves_functional_state(self):
        source = ROOT / CLEANUP
        keys = re.findall(r'"((?:pricing|onboarding|analytics)\.[^"\n]+)"', source.read_text())
        self.assertTrue(any('queue' in k for k in keys))
        self.assertTrue(any('install_id' in k for k in keys))
        main = r'''import Foundation
let defaults = UserDefaults(suiteName: "RetiredAnalyticsCleanup.test.\(UUID().uuidString)")!
let keys = KEYS
for key in keys { defaults.set(Data("old queue or id".utf8), forKey: key) }
for key in ["hasUnlocked", "hasCompletedOnboarding", "schedule.installation.id", "user.content"] {
    defaults.set("preserve", forKey: key)
}
RetiredAnalyticsCleanup.run(defaults: defaults)
RetiredAnalyticsCleanup.run(defaults: defaults)
for key in keys { precondition(defaults.object(forKey: key) == nil, key) }
for key in ["hasUnlocked", "hasCompletedOnboarding", "schedule.installation.id", "user.content"] {
    precondition(defaults.string(forKey: key) == "preserve", key)
    defaults.removeObject(forKey: key)
}
print("upgrade cleanup preserves functional state")
'''.replace('KEYS', '[' + ','.join('"'+k+'"' for k in keys) + ']')
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / 'main.swift').write_text(main)
            compile_result = subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(tmp / 'module-cache'), str(source), str(tmp / 'main.swift'), '-o', str(tmp / 'cleanup')], capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(tmp / 'cleanup')], check=True, capture_output=True, text=True)
            self.assertIn('preserves functional state', result.stdout)

if __name__ == '__main__':
    unittest.main()
