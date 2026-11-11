"""Opt-in hermetic tests of actual native HTTP clients/parsers; no socket/app/device I/O.

Uses the same host compiler configuration as test_native_boundary.py, plus
HEALTHMD_KOTLIN_TRANSPORT_CLASSPATH containing OkHttp/Okio, coroutines and kotlinx JSON/core jars.
No dependencies are downloaded. All compiler outputs live in auto-removed temporary directories.
"""
import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from test_native_boundary import BASE, ROOT, prepare

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('receiver_reference', HERE / 'reference.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)
REQUEST = reference.Request('occurrence-1', BASE['scope'], BASE['zone'],
                            ('2026-03-06', '2026-03-07', '2026-03-08'), '2026-03-09')
VALID = dict(REQUEST.wire(), schema='healthmd.receiver_coverage.response',
             completed_dates=['2026-03-06', '2026-03-08'])


def cases():
    compact = json.dumps(VALID, separators=(',', ':'))
    values = [('partial', compact), ('empty', json.dumps(VALID | dict(completed_dates=[]))),
              ('current', json.dumps(VALID | dict(completed_dates=list(REQUEST.candidates)))),
              ('escaped_key', compact.replace('scope_id', 'scope_\\u0069d'))]
    for key, value in [('schema', 'unsupported'), ('schema_version', True), ('schema_version', 2),
                       ('schema_version', '1'), ('request_id', 'other'), ('scope_id', 'foreign'),
                       ('calendar_timezone', 'UTC'), ('start', '2026-03-05'), ('end_exclusive', '2026-03-10'),
                       ('completed_dates', ['2026-03-09']), ('completed_dates', ['2026-03-10']),
                       ('completed_dates', ['2026-02-29']), ('completed_dates', ['2026-03-05']),
                       ('completed_dates', ['2026-03-06', '2026-03-06']),
                       ('completed_dates', ['2026-03-08', '2026-03-06']), ('completed_dates', [None]),
                       ('completed_dates', ['2026-3-06']), ('completed_dates', {}), ('completed_dates', None),
                       ('completed_dates', ['2026-03-06'] * 31), ('completed_dates', ['0000-03-06'])]:
        values.append((f'field_{len(values)}', json.dumps(VALID | {key: value})))
    for key in VALID:
        values.append(('missing_' + key, json.dumps({k: v for k, v in VALID.items() if k != key})))
        values.append(('duplicate_' + key, compact[:-1] + ',' + json.dumps(key) + ':' + json.dumps(VALID[key]) + '}'))
    values += [('extra', json.dumps(VALID | dict(extra='private error body'))),
               ('escaped_duplicate', compact[:-1] + ',"scope_\\u0069d":"scope-1"}'),
               ('trailing', compact + 'false'), ('trailing_comma', compact[:-1] + ',}'),
               ('decimal_version', compact.replace('"schema_version":1', '"schema_version":1.0')),
               ('exponent_version', compact.replace('"schema_version":1', '"schema_version":1e0')),
               ('double_version', compact.replace('"schema_version":1', '"schema_version":10')),
               ('null', 'null'), ('array', '[' + compact + ']'), ('nested', '{"completed_dates":[[[[]]]]}'),
               ('unescaped_control', compact.replace('scope-1', 'scope-1\n')),
               ('bad_escape', compact.replace('scope-1', 'scope-\\q')),
               ('surrogate', compact.replace('scope-1', 'scope-\\ud800')),
               ('invalid_utf8', compact.encode().replace(b'scope-1', b'scope-\xff')),
               ('cap_exact', compact + ' ' * (65536 - len(compact.encode()))),
               ('cap_over', compact + ' ' * (65537 - len(compact.encode())))]
    result = []
    for name, payload in values:
        body = payload if isinstance(payload, bytes) else payload.encode()
        try:
            dates = sorted(reference.completed_dates(REQUEST, body.decode('utf-8')))
        except (ValueError, UnicodeError, TypeError):
            dates = None
        result.append((name, body, dates))
    return result


@unittest.skipUnless(os.environ.get('HEALTHMD_TEST_NATIVE_BOUNDARY') == '1', 'explicit host native diagnostic')
class NativeTransportTests(unittest.TestCase):
    def run_command(self, command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def fixtures(self, directory):
        vectors = directory / 'cases.tsv'
        vectors.write_text(''.join(name + '\t' + ('valid' if dates is not None else 'invalid') + '\t' +
                                  base64.b64encode(body).decode() + '\n' for name, body, dates in cases()))
        valid = directory / 'valid.json'
        valid.write_text(json.dumps(VALID))
        return [str(vectors), str(valid)]

    def verify(self, output):
        actual = dict(line.split('\t', 1) for line in output.strip().splitlines())
        self.assertEqual(actual.pop('transport'), 'ok')
        for name, _, dates in cases():
            value = actual.pop(name)
            if dates is None:
                self.assertEqual(value, 'invalid', name)
            else:
                evidence = json.loads(base64.b64decode(value))
                self.assertEqual(evidence, VALID | dict(completed_dates=dates), name)
                self.assertEqual(base64.b64decode(value).decode(), json.dumps(evidence, sort_keys=True, separators=(',', ':')), name)
        self.assertEqual(actual, {})

    def test_swift(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-http-swift-') as tmp:
            directory = Path(tmp)
            main = directory / 'Transport.swift'
            main.write_text((HERE / 'native-tests/Transport.swift').read_text().replace('/*PREPARE*/', prepare(BASE)))
            binary = directory / 'tests'
            source = ROOT / 'apps/apple/HealthMd/Shared/ReceiverCoverage'
            self.run_command(['swiftc', '-swift-version', '6', '-default-isolation', 'MainActor', '-module-cache-path', str(directory / 'modules'),
                              '-parse-as-library', *map(str, sorted(source.glob('*.swift'))), str(main), '-o', str(binary)])
            self.verify(self.run_command([str(binary)] + self.fixtures(directory)))

    def test_kotlin(self):
        dependencies = os.environ.get('HEALTHMD_KOTLIN_TRANSPORT_CLASSPATH')
        compiler = os.environ.get('HEALTHMD_KOTLIN_COMPILER_CLASSPATH')
        stdlib = os.environ.get('HEALTHMD_KOTLIN_STDLIB')
        if not dependencies:
            self.skipTest('Kotlin HTTP/parser dependency classpath unavailable')
        if compiler and stdlib:
            command = ['java', '-cp', compiler, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                       '-no-stdlib', '-no-reflect', '-classpath', stdlib + os.pathsep + dependencies]
        elif shutil.which('kotlinc') and shutil.which('kotlin'):
            command = ['kotlinc', '-classpath', dependencies]
        else:
            self.skipTest('Kotlin compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-http-kotlin-') as tmp:
            directory = Path(tmp)
            main = directory / 'Transport.kt'
            main.write_text((HERE / 'native-tests/Transport.kt').read_text().replace('/*PREPARE*/', prepare(BASE, True)))
            jar = directory / 'tests.jar'
            source = ROOT / 'apps/android/app/src/main/java/com/healthmd/data/receivercoverage'
            self.run_command(command + [*map(str, sorted(source.glob('*.kt'))), str(main), '-d', str(jar)])
            if compiler and stdlib:
                runner = ['java', '-cp', os.pathsep.join([str(jar), stdlib, dependencies]), 'TransportKt']
            else:
                runner = ['kotlin', '-classpath', str(jar) + os.pathsep + dependencies, 'TransportKt']
            self.verify(self.run_command(runner + self.fixtures(directory)))


if __name__ == '__main__':
    unittest.main()
