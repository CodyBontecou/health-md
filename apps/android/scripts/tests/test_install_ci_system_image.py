import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'install-ci-system-image.sh'


class SystemImageInstallTests(unittest.TestCase):
    def install(self, outcomes, metadata='valid', payload='complete'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / 'sdk with spaces'
            sdk.mkdir()
            (sdk / 'unrelated').write_text('preserve')
            (root / 'outcomes').write_text('\n'.join(outcomes))
            manager = root / 'sdkmanager'
            manager.write_text(r'''#!/usr/bin/env python3
import os, pathlib, sys
assert sys.argv[1:] == ['--install', 'system-images;android-35;google_apis;x86_64']
root=pathlib.Path(os.environ['IMAGE_FIXTURE_ROOT'])
calls=root/'calls'
n=len(calls.read_text().splitlines()) if calls.exists() else 0
with calls.open('a') as output: output.write('install\n')
value=(root/'outcomes').read_text().splitlines()[n]
if value.startswith('corrupt'):
 print('Warning: Error on ZipFile unknown archive.', file=sys.stderr)
 sys.exit(0 if value=='corrupt-zero' else 17)
if value=='error':
 print('License not accepted', file=sys.stderr);sys.exit(23)
image=pathlib.Path(os.environ['ANDROID_SDK_ROOT'])/'system-images/android-35/google_apis/x86_64'
image.mkdir(parents=True,exist_ok=True)
metadata=os.environ['IMAGE_FIXTURE_METADATA']
(image/'source.properties').write_text('AndroidVersion.ApiLevel='+('34' if metadata=='api' else '35')+'\nSystemImage.Abi='+('arm64-v8a' if metadata=='abi' else 'x86_64')+'\nSystemImage.TagId='+('google_apis_playstore' if metadata=='tag' else 'google_apis')+'\n')
for name in ['system.img','ramdisk.img','kernel-ranchu']:
 if name!=os.environ['IMAGE_FIXTURE_PAYLOAD']: (image/name).write_bytes(b'fixture')
''')
            manager.chmod(0o755)
            result = subprocess.run(['bash', str(SCRIPT)], text=True, capture_output=True,
                                    env=dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                                             ANDROID_SDK_ROOT=str(sdk), IMAGE_FIXTURE_ROOT=str(root),
                                             IMAGE_FIXTURE_METADATA=metadata, IMAGE_FIXTURE_PAYLOAD=payload), timeout=10)
            calls = len((root / 'calls').read_text().splitlines())
            self.assertEqual('preserve', (sdk / 'unrelated').read_text())
            return result, calls

    def test_success_checks_identity_and_payloads_once(self):
        result, calls = self.install(['success'])
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(1, calls)

    def test_corrupt_archive_retries_once_including_zero_exit_warning(self):
        for first in ['corrupt', 'corrupt-zero']:
            result, calls = self.install([first, 'success'])
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(2, calls)

    def test_second_corrupt_archive_is_not_hidden(self):
        result, calls = self.install(['corrupt', 'corrupt'])
        self.assertEqual(17, result.returncode)
        self.assertEqual(2, calls)

    def test_other_errors_do_not_retry(self):
        result, calls = self.install(['error'])
        self.assertEqual(23, result.returncode)
        self.assertEqual(1, calls)

    def test_wrong_api_abi_or_tag_is_rejected_without_retry(self):
        for metadata in ['api', 'abi', 'tag']:
            result, calls = self.install(['success'], metadata=metadata)
            self.assertNotEqual(0, result.returncode)
            self.assertEqual(1, calls)

    def test_missing_image_ramdisk_or_kernel_is_rejected(self):
        for payload in ['system.img', 'ramdisk.img', 'kernel-ranchu']:
            result, calls = self.install(['success'], payload=payload)
            self.assertNotEqual(0, result.returncode)
            self.assertEqual(1, calls)


if __name__ == '__main__':
    unittest.main()
