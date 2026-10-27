"""Keep both native suites while scoping the shared test target's app hosts."""
from pathlib import Path
import importlib.util
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / 'apps/apple/HealthMd.xcodeproj'
MAC_DEPENDENCY = '62A1B0082F50A00100000008'
IOS_DEPENDENCY = 'EE11BB000000000000000004'
TEST_TARGET = '62A1B0052F50A00100000005'
spec = importlib.util.spec_from_file_location('native_targets', PROJECT.parent / 'scripts/check-native-test-targets.py')
native_targets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native_targets)


class NativeDependencyTests(unittest.TestCase):
    def test_complete_target_graph_rejects_extra_host_even_without_dependency_edge(self):
        ios = "    Target 'HealthMdTests' in project 'HealthMd'\n    Target 'HealthMd' in project 'HealthMd'\n"
        mac = "    Target 'HealthMdTests' in project 'HealthMd'\n    Target 'HealthMd-macOS' in project 'HealthMd'\n"
        self.assertEqual(['HealthMd', 'HealthMdTests'], native_targets.qualify_targets(ios, 'iOS'))
        self.assertEqual(['HealthMd-macOS', 'HealthMdTests'], native_targets.qualify_targets(mac, 'macOS'))
        self.assertEqual(['HealthMd', 'HealthMdTests'], native_targets.qualify_targets(
            ios.replace("in project 'HealthMd'", "in project 'HealthMd' (no dependencies)"), 'iOS'))
        for platform, invalid in [('iOS', ios + mac), ('macOS', mac + ios),
                                  ('iOS', "    Target 'HealthMd' in project 'HealthMd'\n"),
                                  ('macOS', '')]:
            with self.subTest(platform=platform, invalid=invalid), self.assertRaises(ValueError):
                native_targets.qualify_targets(invalid, platform)
        with self.assertRaises(ValueError):
            native_targets.qualify_targets(ios + "    Target 'HealthMd-macOS' in project 'HealthMd' (no dependencies)\n", 'iOS')

    def block(self, identifier):
        match = re.search(r'^\t\t' + identifier + r' /\*[^\n]+\*/ = \{\n(.*?)^\t\t\};',
                          (PROJECT / 'project.pbxproj').read_text(), re.M | re.S)
        self.assertIsNotNone(match, identifier)
        return match.group(1)

    def test_native_mac_host_uses_the_effective_platform_list(self):
        dependency = self.block(MAC_DEPENDENCY)
        # The plural field scopes the explicit edge. Independent inferred roots
        # require a separate complete-graph check, not just an edge inventory.
        self.assertNotRegex(dependency, r'\bplatformFilter\s*=')
        self.assertRegex(dependency, r'platformFilters\s*=\s*\(\s*macos,?\s*\);')
        self.assertIn('target = 62CC00052F15D70300F9103F', dependency)

    def test_shared_bundle_retains_each_platform_host_configuration(self):
        for identifier, host in [('62A1B0092F50A00100000009', 'Health.md.app/Contents/MacOS/Health.md'),
                                 ('62A1B00A2F50A00100000010', 'Health.md.app/Contents/MacOS/Health.md'),
                                 ('1BAC721C5C094A2F9BA90F1D', 'HealthMd.app/HealthMd')]:
            config = self.block(identifier)
            self.assertIn(f'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/{host}";', config)
            self.assertIn('BUNDLE_LOADER = "$(TEST_HOST)";', config)

    def test_both_hosts_and_the_complete_shared_test_target_remain(self):
        target = self.block(TEST_TARGET)
        self.assertIn(MAC_DEPENDENCY, target)
        self.assertIn(IOS_DEPENDENCY, target)
        ios = self.block(IOS_DEPENDENCY)
        self.assertRegex(ios, r'platformFilter\s*=\s*ios;|platformFilters\s*=\s*\(\s*ios,?\s*\);')
        self.assertIn('target = 624B99EE2F15D70300F9103F', ios)
        for platform in ('iOS', 'macOS'):
            scheme = ET.parse(PROJECT / f'xcshareddata/xcschemes/HealthMd-Tests-{platform}.xcscheme')
            build = scheme.find('./BuildAction')
            if platform == 'iOS':
                self.assertEqual(build.get('buildImplicitDependencies'), 'NO')
                entries = build.findall('./BuildActionEntries/BuildActionEntry')
                self.assertEqual([e.find('BuildableReference').get('BlueprintIdentifier') for e in entries],
                                 ['624B99EE2F15D70300F9103F', TEST_TARGET])
                self.assertTrue(all(e.get('buildForTesting') == 'YES' for e in entries))
            testables = scheme.findall('./TestAction/Testables/TestableReference')
            self.assertEqual(len(testables), 1)
            self.assertEqual(testables[0].get('skipped'), 'NO')
            reference = testables[0].find('BuildableReference')
            self.assertEqual(reference.get('BlueprintIdentifier'), TEST_TARGET)
            self.assertEqual(reference.get('BuildableName'), 'HealthMdTests.xctest')


if __name__ == '__main__':
    unittest.main()
