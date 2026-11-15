"""Keep both native suites while scoping the shared test target's app hosts."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / 'apps/apple/HealthMd.xcodeproj'
MAC_DEPENDENCY = '62A1B0082F50A00100000008'
IOS_DEPENDENCY = 'EE11BB000000000000000004'
TEST_TARGET = '62A1B0052F50A00100000005'


class NativeDependencyTests(unittest.TestCase):
    def block(self, identifier):
        match = re.search(r'^\t\t' + identifier + r' /\*[^\n]+\*/ = \{\n(.*?)^\t\t\};',
                          (PROJECT / 'project.pbxproj').read_text(), re.M | re.S)
        self.assertIsNotNone(match, identifier)
        return match.group(1)

    def test_native_mac_host_uses_the_effective_platform_list(self):
        dependency = self.block(MAC_DEPENDENCY)
        # Xcode's observed iOS build plan ignored the singular macos filter,
        # building the Mac app and its CLI helpers as well as the iOS host.
        self.assertNotRegex(dependency, r'\bplatformFilter\s*=')
        self.assertRegex(dependency, r'platformFilters\s*=\s*\(\s*macos,?\s*\);')
        self.assertIn('target = 62CC00052F15D70300F9103F', dependency)

    def test_both_hosts_and_the_complete_shared_test_target_remain(self):
        target = self.block(TEST_TARGET)
        self.assertIn(MAC_DEPENDENCY, target)
        self.assertIn(IOS_DEPENDENCY, target)
        ios = self.block(IOS_DEPENDENCY)
        self.assertRegex(ios, r'platformFilter\s*=\s*ios;|platformFilters\s*=\s*\(\s*ios,?\s*\);')
        self.assertIn('target = 624B99EE2F15D70300F9103F', ios)
        for platform in ('iOS', 'macOS'):
            scheme = ET.parse(PROJECT / f'xcshareddata/xcschemes/HealthMd-Tests-{platform}.xcscheme')
            testables = scheme.findall('./TestAction/Testables/TestableReference')
            self.assertEqual(len(testables), 1)
            self.assertEqual(testables[0].get('skipped'), 'NO')
            reference = testables[0].find('BuildableReference')
            self.assertEqual(reference.get('BlueprintIdentifier'), TEST_TARGET)
            self.assertEqual(reference.get('BuildableName'), 'HealthMdTests.xctest')


if __name__ == '__main__':
    unittest.main()
