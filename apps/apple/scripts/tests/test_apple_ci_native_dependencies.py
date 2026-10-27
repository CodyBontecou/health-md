"""Preserve both complete native suites with independent platform hosts."""
from pathlib import Path
import importlib.util
import json
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / 'apps/apple/HealthMd.xcodeproj'
spec = importlib.util.spec_from_file_location('native_targets', PROJECT.parent / 'scripts/check-native-test-targets.py')
native_targets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native_targets)


def read_project(text):
    """Parse the project's OpenStep dictionaries without a macOS-only tool."""
    lexer = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', re.S)
    tokens = []
    offset = 0
    while offset < len(text):
        match = lexer.match(text, offset)
        if match is None:
            raise ValueError('Unsupported project syntax')
        token = match.group()
        if token.startswith('/*') and not token.endswith('*/'):
            raise ValueError('Unterminated project comment')
        offset = match.end()
        if not token.isspace() and not token.startswith(('//', '/*')):
            tokens.append(token)
    position = 0

    def take(expected=None):
        nonlocal position
        if position >= len(tokens):
            raise ValueError('Incomplete project')
        token = tokens[position]
        position += 1
        if expected is not None and token != expected:
            raise ValueError('Unexpected project delimiter')
        return token

    def value():
        token = take()
        if token == '{':
            result = {}
            while position < len(tokens) and tokens[position] != '}':
                key = take()
                if key.startswith('"'):
                    key = json.loads(key)
                if key in result:
                    raise ValueError('Duplicate project key')
                take('=')
                result[key] = value()
                take(';')
            take('}')
            return result
        if token == '(':
            result = []
            while position < len(tokens) and tokens[position] != ')':
                result.append(value())
                if position < len(tokens) and tokens[position] == ',':
                    take(',')
                elif position >= len(tokens) or tokens[position] != ')':
                    raise ValueError('Missing project list delimiter')
            take(')')
            return result
        if token in '{}()=;,':
            raise ValueError('Unexpected project value')
        return json.loads(token) if token.startswith('"') else token

    result = value()
    if position != len(tokens) or not isinstance(result, dict):
        raise ValueError('Unexpected trailing project content')
    return result


class ProjectParserTests(unittest.TestCase):
    def test_nested_comments_strings_and_lists(self):
        self.assertEqual({'name': 'a / b', 'group': {'members': ['one', 'two']}, 'empty': []},
                         read_project('// header\n{ name = "a / b"; group = { members = (one, /* comment */ two,); }; empty = (); }'))

    def test_malformed_or_duplicate_content_is_rejected(self):
        for text in ['{', '{ a = b; a = c; }', '{} extra', '{ a = (one two); }', '{ a = b }', '{} /*', '{} /* unclosed comment']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                read_project(text)


class NativeDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = read_project((PROJECT / 'project.pbxproj').read_text())
        cls.objects = cls.project['objects']
        cls.targets = {v.get('name'): (k, v) for k, v in cls.objects.items()
                       if v.get('isa') == 'PBXNativeTarget'}

    def test_complete_graph_rejects_independent_cross_platform_roots(self):
        for platform, target, host, forbidden in [
            ('iOS', 'HealthMdTests-iOS', 'HealthMd', ['HealthMd-macOS', 'HealthMdTests', 'healthmd', 'healthmd-mcp']),
            ('macOS', 'HealthMdTests', 'HealthMd-macOS', ['HealthMd', 'HealthMdTests-iOS']),
        ]:
            text = ''.join(f"    Target '{name}' in project 'HealthMd'\n" for name in [target, host])
            self.assertEqual(sorted([target, host]), native_targets.qualify_targets(text, platform))
            self.assertEqual(sorted([target, host]), native_targets.qualify_targets(
                text.replace("in project 'HealthMd'", "in project 'HealthMd' (no dependencies)"), platform))
            for extra in forbidden:
                with self.subTest(platform=platform, extra=extra), self.assertRaises(ValueError):
                    native_targets.qualify_targets(text + f"    Target '{extra}' in project 'HealthMd' (no dependencies)\n", platform)
            with self.assertRaises(ValueError):
                native_targets.qualify_targets(f"    Target '{host}' in project 'HealthMd'\n", platform)

    def test_platform_targets_share_complete_sources_resources_and_packages(self):
        _, mac = self.targets['HealthMdTests']
        _, ios = self.targets['HealthMdTests-iOS']
        self.assertEqual(mac['fileSystemSynchronizedGroups'], ios['fileSystemSynchronizedGroups'])
        self.assertEqual(['62A1B0032F50A00100000003'], ios['fileSystemSynchronizedGroups'])
        group = self.objects[ios['fileSystemSynchronizedGroups'][0]]
        self.assertEqual('HealthMdTests', group['path'])
        self.assertFalse(group.get('exceptions'))
        for a, b in zip(mac['buildPhases'], ios['buildPhases']):
            left, right = self.objects[a], self.objects[b]
            self.assertEqual(left['isa'], right['isa'])
            self.assertEqual({k: v for k, v in left.items() if k != 'files'},
                             {k: v for k, v in right.items() if k != 'files'})
            def files(phase):
                result = []
                for f in phase['files']:
                    value = dict(self.objects[f])
                    if 'productRef' in value:
                        value['productRef'] = self.objects[value['productRef']]
                    result.append(value)
                return result
            self.assertEqual(files(left), files(right))
        self.assertEqual(len(mac['buildPhases']), len(ios['buildPhases']))
        self.assertEqual([self.objects[p] for p in mac['packageProductDependencies']],
                         [self.objects[p] for p in ios['packageProductDependencies']])
        self.assertEqual(self.objects[mac['productReference']], self.objects[ios['productReference']])

    def test_each_configuration_and_scheme_uses_only_its_platform_host(self):
        attrs = self.objects[self.project['rootObject']]['attributes']['TargetAttributes']
        for platform, name, host, configs, supported in [
            ('macOS', 'HealthMdTests', 'HealthMd-macOS', {'Debug', 'Release'}, 'macosx'),
            ('iOS', 'HealthMdTests-iOS', 'HealthMd', {'Debug', 'Release', 'Debug-iOS', 'Release-iOS'}, 'iphoneos iphonesimulator'),
        ]:
            identifier, target = self.targets[name]
            host_id, _ = self.targets[host]
            self.assertEqual(host_id, attrs[identifier]['TestTargetID'])
            self.assertEqual([host_id], [self.objects[d]['target'] for d in target['dependencies']])
            configurations = [self.objects[c] for c in self.objects[target['buildConfigurationList']]['buildConfigurations']]
            self.assertEqual(configs, {c['name'] for c in configurations})
            self.assertEqual(len(configs), len(configurations))
            for config in configurations:
                settings = config['buildSettings']
                self.assertEqual(supported, settings['SUPPORTED_PLATFORMS'])
                self.assertEqual('$(TEST_HOST)', settings['BUNDLE_LOADER'])
                expected = 'HealthMd.app/HealthMd' if platform == 'iOS' else 'Health.md.app/Contents/MacOS/Health.md'
                self.assertEqual('$(BUILT_PRODUCTS_DIR)/' + expected, settings['TEST_HOST'])
                if platform == 'iOS':
                    self.assertEqual('HealthMdTests', settings['PRODUCT_NAME'])
                    self.assertEqual('HealthMdTests', settings['PRODUCT_MODULE_NAME'])
                    # Debug and Release preserve their original, different profiles.
                    original = self.objects['1BAC721C5C094A2F9BA90F1D' if config['name'].startswith('Debug') else '8446E2E4B31C479FB9583F8D']['buildSettings']
                    changes = {'PRODUCT_NAME', 'PRODUCT_MODULE_NAME', 'SUPPORTED_PLATFORMS', 'TEST_HOST', 'BUNDLE_LOADER', 'SWIFT_INCLUDE_PATHS'}
                    self.assertEqual({k: v for k, v in original.items() if k not in changes},
                                     {k: v for k, v in settings.items() if k not in changes})
            scheme = ET.parse(PROJECT / f'xcshareddata/xcschemes/HealthMd-Tests-{platform}.xcscheme')
            refs = scheme.findall('./TestAction/Testables/TestableReference')
            self.assertEqual(1, len(refs))
            self.assertEqual('NO', refs[0].get('skipped'))
            reference = refs[0].find('BuildableReference')
            self.assertEqual(identifier, reference.get('BlueprintIdentifier'))
            self.assertEqual(name, reference.get('BlueprintName'))
            self.assertEqual('HealthMdTests.xctest', reference.get('BuildableName'))
            if platform == 'iOS':
                self.assertEqual('NO', scheme.find('./BuildAction').get('buildImplicitDependencies'))
                entries = scheme.findall('./BuildAction/BuildActionEntries/BuildActionEntry')
                self.assertEqual([host_id, identifier], [e.find('BuildableReference').get('BlueprintIdentifier') for e in entries])
                self.assertTrue(all(e.get('buildForTesting') == 'YES' for e in entries))

    def test_legacy_ios_filter_maps_only_the_exact_test_target(self):
        for supplied, expected in [('', ''), ('HealthMdTests', 'HealthMdTests-iOS'),
                                   ('HealthMdTests/Class/testMethod', 'HealthMdTests-iOS/Class/testMethod'),
                                   ('HealthMdTests-iOS/Class', 'HealthMdTests-iOS/Class'),
                                   ('HealthMdTestsOther/Class', 'HealthMdTestsOther/Class')]:
            for platform in ['ios', 'macos']:
                result = subprocess.check_output(['make', '-n', '-C', str(PROJECT.parent),
                                                  f'test-{platform}', f'TEST_FILTER={supplied}'], text=True)
                wanted = expected if platform == 'ios' else supplied
                if wanted:
                    self.assertIn('-only-testing:' + wanted + ' ', result)
                else:
                    self.assertNotIn('-only-testing:', result)


if __name__ == '__main__':
    unittest.main()
