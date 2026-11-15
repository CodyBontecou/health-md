"""Opt-in host regressions of actual native pending/retry store code; no app/device I/O.

Swift SDK model seams are inert data carriers. Kotlin copies the production pending data class
byte-for-byte for compilation beside the actual retry helper and actual date serializers.
No persistence, selection, acknowledgement or retry implementation is duplicated in the harness.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from test_native_boundary import ROOT

HERE = Path(__file__).resolve().parent


@unittest.skipUnless(os.environ.get('HEALTHMD_TEST_NATIVE_BOUNDARY') == '1', 'explicit host native diagnostic')
class NativePendingStoreTests(unittest.TestCase):
    def command(self, args):
        result = subprocess.run(args, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_swift(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-pending-swift-') as tmp:
            tmp = Path(tmp)
            sources = sorted((ROOT / 'apps/apple/HealthMd/Shared/ReceiverCoverage').glob('*.swift')) + [
                ROOT / 'apps/apple/HealthMd/Shared/Models/PendingExportRequest.swift',
                HERE / 'native-tests/PendingStoreStubs.swift', HERE / 'native-tests/PendingStore.swift']
            binary = tmp / 'tests'
            self.command(['swiftc', '-swift-version', '6', '-default-isolation', 'MainActor', '-parse-as-library',
                          '-module-cache-path', str(tmp / 'modules'), *map(str, sources), '-o', str(binary)])
            self.assertIn('passed', self.command([str(binary)]))

    def test_swift_runtime(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-runtime-swift-') as tmp:
            tmp = Path(tmp)
            sources = sorted((ROOT / 'apps/apple/HealthMd/Shared/ReceiverCoverage').glob('*.swift')) + [
                ROOT / 'apps/apple/HealthMd/Shared/Managers/ReceiverCoverageRuntime.swift',
                HERE / 'native-tests/RuntimeStubs.swift', HERE / 'native-tests/Runtime.swift']
            binary = tmp / 'tests'
            self.command(['swiftc', '-swift-version', '6', '-default-isolation', 'MainActor', '-parse-as-library',
                          '-module-cache-path', str(tmp / 'modules'), *map(str, sources), '-o', str(binary)])
            self.assertIn('passed', self.command([str(binary)]))

    def test_kotlin_runtime(self):
        compiler = os.environ.get('HEALTHMD_KOTLIN_COMPILER_CLASSPATH')
        stdlib = os.environ.get('HEALTHMD_KOTLIN_STDLIB')
        dependencies = os.environ.get('HEALTHMD_KOTLIN_TRANSPORT_CLASSPATH')
        if not (compiler and stdlib and dependencies):
            self.skipTest('Kotlin compiler/dependency classpath unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-runtime-kotlin-') as tmp:
            tmp = Path(tmp)
            sources = sorted((ROOT / 'apps/android/app/src/main/java/com/healthmd/data/receivercoverage').glob('*.kt')) + [
                ROOT / 'apps/android/app/src/main/java/com/healthmd/data/scheduler/ReceiverCoverageRuntime.kt',
                HERE / 'native-tests/AndroidRuntime.kt', HERE / 'native-tests/LegacyReceiverBoundary.kt',
                ROOT / 'apps/android/app/src/main/java/com/healthmd/data/scheduler/ScheduledExportPendingRequests.kt',
                ROOT / 'apps/android/app/src/main/java/com/healthmd/data/scheduler/ScheduledExportCancellationCoordinator.kt',
                ROOT / 'apps/android/app/src/main/java/com/healthmd/domain/model/Serializers.kt']
            model_source = (ROOT / 'apps/android/app/src/main/java/com/healthmd/domain/model/ExportSettings.kt').read_text()
            start = model_source.index('@Serializable\ndata class PendingScheduledExportRequest(')
            end = model_source.index('\n}', start) + 2
            model = tmp / 'Model.kt'
            model.write_text((HERE / 'native-tests/PendingModel.kt.template').read_text().replace('/*MODEL*/', model_source[start:end]))
            pin = tmp / 'Pin.kt'
            pin.write_bytes((HERE / 'native-tests/PendingPin.kt.template').read_bytes())
            sources += [model, pin]
            for name in ['AndroidContext','AndroidCredentials','AndroidEntitlements','AndroidClinic']:
                path = tmp / (name + '.kt')
                path.write_bytes((HERE / ('native-tests/' + name + '.kt.template')).read_bytes())
                sources.append(path)
            jar = tmp / 'tests.jar'
            self.command(['java', '-cp', compiler, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib',
                          '-no-reflect', '-classpath', stdlib + os.pathsep + dependencies,
                          *map(str, sources), '-d', str(jar)])
            self.assertIn('passed', self.command(['java', '-cp', os.pathsep.join([str(jar),stdlib,dependencies]), 'AndroidRuntimeKt']))

    def test_kotlin(self):
        compiler = os.environ.get('HEALTHMD_KOTLIN_COMPILER_CLASSPATH')
        stdlib = os.environ.get('HEALTHMD_KOTLIN_STDLIB')
        dependencies = os.environ.get('HEALTHMD_KOTLIN_TRANSPORT_CLASSPATH')
        if not (compiler and stdlib and dependencies):
            self.skipTest('Kotlin cached compiler/dependency classpath unavailable')
        source = (ROOT / 'apps/android/app/src/main/java/com/healthmd/domain/model/ExportSettings.kt').read_text()
        start = source.index('@Serializable\ndata class PendingScheduledExportRequest(')
        first = source.index(') {', start) + 2
        depth = 0
        for end in range(first, len(source)):
            if source[end] == '{':
                depth += 1
            if source[end] == '}':
                depth -= 1
                if depth == 0:
                    break
        model = source[start:end + 1]
        with tempfile.TemporaryDirectory(prefix='healthmd-170-pending-kotlin-') as tmp:
            tmp = Path(tmp)
            (tmp / 'Model.kt').write_text((HERE / 'native-tests/PendingModel.kt.template').read_text().replace('/*MODEL*/', model))
            jar = tmp / 'tests.jar'
            sources = sorted((ROOT / 'apps/android/app/src/main/java/com/healthmd/data/receivercoverage').glob('*.kt')) + [tmp / 'Model.kt', HERE / 'native-tests/PendingPin.kt.template', HERE / 'native-tests/Pending.kt',
                       ROOT / 'apps/android/app/src/main/java/com/healthmd/data/scheduler/ScheduledExportPendingRequests.kt',
                       ROOT / 'apps/android/app/src/main/java/com/healthmd/domain/model/Serializers.kt']
            # The template suffix deliberately avoids app/transport test wildcard discovery.
            pin = tmp / 'Pin.kt'; pin.write_bytes((HERE / 'native-tests/PendingPin.kt.template').read_bytes()); sources = [pin if p.name == 'PendingPin.kt.template' else p for p in sources]
            self.command(['java', '-cp', compiler, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib',
                          '-no-reflect', '-classpath', stdlib + os.pathsep + dependencies,
                          *map(str, sources), '-d', str(jar)])
            output = self.command(['java', '-cp', os.pathsep.join([str(jar), stdlib, dependencies]), 'PendingKt'])
            self.assertIn('passed', output)


if __name__ == '__main__':
    unittest.main()
