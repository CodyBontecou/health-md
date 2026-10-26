#!/bin/bash
# Diagnostic only: stop at first failed contract, never retry it into green.
set -euo pipefail
repo_root="$PWD"
cd apps/android
out=build/reports/pr189-native-focus
mkdir -p "$out"
git rev-parse HEAD > "$out/source.txt"
adb -s emulator-5554 shell getprop ro.build.version.sdk >> "$out/source.txt"
adb -s emulator-5554 shell getprop ro.build.fingerprint >> "$out/source.txt"
adb -s emulator-5554 shell wm size >> "$out/source.txt"
git diff -- app/src/androidTest/java/com/healthmd/presentation/accessibility/NativeInputReadinessTest.kt > "$out/instrumentation.patch"
for round in $(seq 1 12); do
  # Remove only this owned AVD run's prior reports; require fresh evidence each round.
  python3 - <<'PY'
from pathlib import Path
import shutil
for name in ['app/build/outputs/androidTest-results/connected', 'app/build/reports/androidTests/connected']:
    path = Path(name)
    if path.exists(): shutil.rmtree(path)
PY
  if timeout --signal=TERM --kill-after=30s 300s ./scripts/run-ci-gradle.sh \
    --no-daemon --max-workers=2 --init-script "$repo_root/.github/scripts/pr189-modal-focus.init.gradle" \
    -Pandroid.testInstrumentationRunnerArguments.healthmd.ciInputDiagnostics=true \
    -Pandroid.testInstrumentationRunnerArguments.class=com.healthmd.presentation.accessibility.NativeInputReadinessTest \
    :app:connectedPlayDebugAndroidTest --stacktrace 2>&1 | tee "$out/round-$round.log"; then
    status=0
  else
    status=$?
  fi
  echo "round=$round command_exit=$status" >> "$out/outcomes.txt"
  if python3 - "$round" "$status" > "$out/evidence-$round.log" 2>&1 <<'PY'
from pathlib import Path
import shutil,sys,xml.etree.ElementTree as E
round,status=sys.argv[1],int(sys.argv[2]);source=Path('app/build/outputs/androidTest-results/connected')
dest=Path('build/reports/pr189-native-focus')/('round-'+round)
if source.exists():shutil.copytree(source,dest)
rows=[E.parse(p).getroot() for p in dest.rglob('TEST-*.xml')]
with (dest.parent/'outcomes.txt').open('a') as log:log.write(f'round={round} exit={status} tests={sum(int(r.get("tests",0)) for r in rows)}\n')
if status==0:
 assert len(rows)==1 and int(rows[0].get('tests',0))==4,'Require every preflight test to execute'
 assert int(rows[0].get('failures',0))==0 and int(rows[0].get('errors',0))==0
PY
  then
    evidence_status=0
  else
    evidence_status=$?
  fi
  echo "round=$round evidence_exit=$evidence_status" >> "$out/outcomes.txt"
  # A broken evidence file must never replace the original test/timeout exit.
  if [[ "$status" != 0 ]]; then exit "$status"; fi
  if [[ "$evidence_status" != 0 ]]; then exit "$evidence_status"; fi
done
