"""The early-boot helper returns immediately and never hides a real boot error."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "start-ci-ios-simulator.sh"


class EarlyBootTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copy(SCRIPT, self.root)
        for helper in ("apple_nightly_ui.py", "validate_ios_ui_xctestrun.py"):
            shutil.copy(SCRIPT.parent / helper, self.root)
        select = self.root / "select-ios-simulator.sh"
        select.write_text("#!/bin/sh\nprintf '%s\\n' 'platform=iOS Simulator,id=11111111-1111-1111-1111-111111111111'\n")
        select.chmod(0o755)
        tool = self.root / "xcrun"
        tool.write_text("#!" + sys.executable + "\n" + '''import json,os,sys
from pathlib import Path
with Path(os.environ['CALLS']).open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1:3]==['simctl','boot']: sys.exit(int(os.environ.get('BOOT_EXIT','0')))
if sys.argv[1:3]==['simctl','list']:
    print(json.dumps({'devices':{'runtime':[{'udid':'11111111-1111-1111-1111-111111111111','state':os.environ.get('DEVICE_STATE','Shutdown')}]}}))
else: sys.exit('Unexpected blocking or install command')
''')
        tool.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.root}:{os.environ['PATH']}", CALLS=str(self.root / "calls"))

    def run_boot(self):
        return subprocess.run(["bash", str(self.root / SCRIPT.name)], env=self.env,
                              capture_output=True, text=True)

    def test_start_only_does_not_wait_for_boot_or_install_before_compilation(self):
        result = self.run_boot()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "platform=iOS Simulator,id=11111111-1111-1111-1111-111111111111")
        import json
        calls = [json.loads(x) for x in (self.root / "calls").read_text().splitlines()]
        self.assertEqual(calls[-1], ["simctl", "boot", "11111111-1111-1111-1111-111111111111"])
        self.assertFalse(any('bootstatus' in c or 'install' in c for c in calls))

    def test_already_booted_is_safe_but_shutdown_failure_is_not(self):
        self.env.update(BOOT_EXIT="1", DEVICE_STATE="Booted")
        self.assertEqual(self.run_boot().returncode, 0)
        self.env["DEVICE_STATE"] = "Shutdown"
        self.assertNotEqual(self.run_boot().returncode, 0)


if __name__ == "__main__": unittest.main()
