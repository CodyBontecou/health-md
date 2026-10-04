#!/usr/bin/env python3
"""Replay synthetic UI readiness frames through the real Wear smoke runner; no device access."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]

FAKE_ADB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["FAKE_WEAR_ROOT"])
state_file = root / "state.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {"rtl_dumps": 0, "rtl_launches": 0}
args = sys.argv[1:]
if args == ["get-state"]:
    print("device")
elif args[:1] == ["logcat"] or args[:1] == ["install"]:
    pass
elif args[:1] == ["pull"]:
    name = pathlib.Path(args[1]).stem
    texts = {
        "setup": ["Open Health.md on your phone to finish setup.", "Sync Health Data"],
        "fresh": ["Health.md", "Steps", "8,420"],
        "fresh_offline_relaunch": ["8,420"],
        "fresh_scrolled": ["Sleep"],
        "rotary_scrolled": ["Blood Oxygen", "Last phone sync; not real-time"],
        "partial": ["Health Connect access is needed on your phone.", "Steps", "8,420"],
        "stale": ["Updated 5 hours ago"],
        "expired": ["Data is more than 24 hours old."],
        "unavailable": ["Health Connect is unavailable on your phone."],
        "version_mismatch": ["Update Health.md on your phone and watch."],
        "version_mismatch_relaunch": ["Update Health.md on your phone and watch."],
        "version_recovered": ["8,420"],
        "large_font": ["Health.md"],
        "restored_english": ["Health.md"],
    }
    package = "com.healthmd.android"
    if name == "rtl":
        state["rtl_dumps"] += 1
        texts[name] = ["الصحة"]
        scenario = os.environ["FAKE_WEAR_SCENARIO"]
        if scenario == "overlay" and state["rtl_launches"] == 1:
            package = "com.android.systemui"
            texts[name] = ["Charging"]
        elif scenario != "missing" and state["rtl_dumps"] > 1:
            texts[name].append("الخطوات")
    nodes = "".join('<node package="' + package + '" text="' + text + '"/>' for text in texts[name])
    pathlib.Path(args[2]).write_text("<hierarchy>" + nodes + "</hierarchy>")
elif args[:1] == ["shell"]:
    shell = args[1:]
    if shell == ["getprop", "sys.boot_completed"]:
        print("1")
    elif shell[:3] == ["am", "start", "-W"]:
        if state.get("locale") == "ar":
            state["rtl_launches"] += 1
        print("Status: ok\nActivity: com.healthmd.android/com.healthmd.wear.MainActivity")
    elif shell[:3] == ["dumpsys", "input"]:
        print("Sources: ROTARY_ENCODER")
    elif shell[:3] == ["dumpsys", "package", "com.healthmd.android"]:
        print("versionCode=1 minSdk=30 targetSdk=35\nversionName=1.0.0\ncom.healthmd.android.wear.diagnostics")
        print("DailyActivityTileService RecoveryTileService DailyActivityComplicationService RecoveryComplicationService StepsComplicationService MoveComplicationService ExerciseComplicationService SleepComplicationService RestingHeartRateComplicationService AverageHeartRateComplicationService HrvComplicationService BloodOxygenComplicationService")
    elif shell[:2] == ["content", "query"]:
        print("Row: 0 cache_file_present=true")
    elif shell[:4] == ["cmd", "locale", "set-app-locales", "com.healthmd.android"]:
        state["locale"] = shell[-1]
    elif shell[:2] == ["dumpsys", "window"]:
        pass
    elif shell[:2] in (["input", "keyevent"], ["input", "swipe"], ["input", "rotaryencoder"], ["am", "force-stop"], ["settings", "put"], ["uiautomator", "dump"]):
        pass
    elif shell[:1] == ["run-as"]:
        pass
    elif len(shell) == 1 and shell[0].startswith("run-as com.healthmd.android sh -c"):
        sys.stdin.read()
    else:
        raise SystemExit("Unexpected fake adb command: " + repr(args))
else:
    raise SystemExit("Unexpected fake adb command: " + repr(args))
state_file.write_text(json.dumps(state))
'''


class WearSmokeReadinessTest(unittest.TestCase):
    def replay(self, scenario: str) -> tuple[subprocess.CompletedProcess[str], dict]:
        with tempfile.TemporaryDirectory(prefix="healthmd-wear-readiness-") as directory:
            root = Path(directory)
            adb = root / "adb"
            adb.write_text(FAKE_ADB)
            adb.chmod(0o755)
            aapt = root / "aapt"
            aapt.write_text("#!/bin/sh\nprintf \"package: name='com.healthmd.android' versionCode='1' versionName='1.0.0'\\nsdkVersion:'30'\\ntargetSdkVersion:'35'\\n\"\n")
            aapt.chmod(0o755)
            sleep = root / "sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            apk = root / "synthetic.apk"
            apk.touch()
            env = os.environ | {
                "ADB": str(adb), "AAPT": str(aapt), "FAKE_WEAR_ROOT": str(root),
                "FAKE_WEAR_SCENARIO": scenario, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                "WEAR_EMULATOR_EVIDENCE_ROOT": "", "EXPECTED_PACKAGE": "com.healthmd.android",
            }
            result = subprocess.run(
                ["bash", str(SCRIPTS / "run-wear-emulator-smoke.sh"), str(apk)],
                env=env, capture_output=True, text=True, timeout=30,
            )
            state = json.loads((root / "state.json").read_text())
            return result, state

    def test_arabic_header_does_not_claim_the_cached_metric_is_ready(self) -> None:
        result, state = self.replay("loading")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(2, state["rtl_dumps"])
        self.assertEqual(1, state["rtl_launches"], "Polling app-owned loading frames must not restart cache loading")
        self.assertIn("Wear emulator dashboard/state/component smoke passed", result.stdout)

    def test_missing_arabic_metric_still_fails_despite_a_ready_header(self) -> None:
        result, state = self.replay("missing")
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(10, state["rtl_dumps"], "Missing metric must exhaust the bounded readiness check")
        self.assertNotIn("smoke passed", result.stdout)

    def test_system_overlay_still_gets_a_bounded_relaunch(self) -> None:
        result, state = self.replay("overlay")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(2, state["rtl_launches"])
        self.assertEqual(2, state["rtl_dumps"])


if __name__ == "__main__":
    unittest.main()
