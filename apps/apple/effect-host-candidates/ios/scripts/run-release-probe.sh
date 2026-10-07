#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$*" == "--offline --fresh-process" ]] || { echo 'Require --offline --fresh-process'; exit 2; }
[[ "$(node --version)" == v24.21.0 ]] || { echo 'Use exact candidate Node'; exit 2; }
mkdir -p ios/build
# Explicit transient target only; never boot, erase or reset a simulator or another app.
: "${HEALTHMD_PROBE_SIMULATOR_ID:?Set the transient ID of the reviewed booted generic simulator}"
node - "$HEALTHMD_PROBE_SIMULATOR_ID" <<'NODE'
const {execFileSync}=require('node:child_process');
const inventory=JSON.parse(execFileSync('xcrun',['simctl','list','devices','booted','--json']));
if (!Object.values(inventory.devices).flat().some((d)=>d.udid===process.argv[2]&&d.state==='Booted')) throw Error('target_not_booted');
NODE
npm run check
npm run build > ios/build/metro-build.log 2>&1
xcodebuild -workspace ios/build/HostProbe.xcworkspace -scheme HostProbe -configuration Release \
  -sdk iphonesimulator -destination "id=$HEALTHMD_PROBE_SIMULATOR_ID" \
  -derivedDataPath ios/build/DerivedData CODE_SIGNING_ALLOWED=NO NODE_BINARY="$(command -v node)" build > ios/build/release-build.log 2>&1
app=ios/build/DerivedData/Build/Products/Release-iphonesimulator/HostProbe.app
[[ -f "$app/main.jsbundle" ]] || { echo 'Packaged offline bundle missing'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")" == com.healthmd.effecthost.ioscandidate ]]
xcrun simctl install "$HEALTHMD_PROBE_SIMULATOR_ID" "$app"
node - "$app" "$HEALTHMD_PROBE_SIMULATOR_ID" > ios/build/artifact-bind.json <<'NODE'
const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
const installed=execFileSync('xcrun',['simctl','get_app_container',process.argv[3],'com.healthmd.effecthost.ioscandidate','app'],{encoding:'utf8'}).trim();
const sha=(p)=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const files={};for(const name of ['HostProbe','main.jsbundle']){files[name]=sha(process.argv[2]+'/'+name);assert.equal(sha(installed+'/'+name),files[name],'installed_artifact_drift');}
console.log(JSON.stringify({bundle_id:'com.healthmd.effecthost.ioscandidate',installed_matches_built:true,files}));
NODE
for run in 1 2; do
  xcrun simctl terminate "$HEALTHMD_PROBE_SIMULATOR_ID" com.healthmd.effecthost.ioscandidate 2>/dev/null || true
  log="$PWD/ios/build/probe-$run.log"
  : > "$log"
  : > "$PWD/ios/build/probe-$run.stderr.log"
  xcrun simctl launch --terminate-running-process --stdout="$log" --stderr="$PWD/ios/build/probe-$run.stderr.log" \
    "$HEALTHMD_PROBE_SIMULATOR_ID" com.healthmd.effecthost.ioscandidate > "ios/build/launch-$run.log"
  for attempt in {1..100}; do
    if [[ -f "$log" ]] && rg -q '^HEALTHMD_CANDIDATE_RESULT ' "$log"; then break; fi
    sleep 0.1
  done
  node - "$log" "$run" <<'NODE'
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const fixture=JSON.parse(fs.readFileSync('fixtures/host-probe-v1.json'));
const rows=fs.readFileSync(process.argv[2],'utf8').split('\n').filter((x)=>x.startsWith('HEALTHMD_CANDIDATE_RESULT '));
assert.equal(rows.length,1,'exactly_one_fresh_native_result');const report=JSON.parse(rows[0].slice('HEALTHMD_CANDIDATE_RESULT '.length));
assert.equal(report.result,'passed');assert.equal(report.observations.length,fixture.cases.length);
for(const expected of fixture.cases){const actual=report.observations.find((x)=>x.case_id===expected.case_id);assert.ok(actual);for(const[k,v]of Object.entries(expected.expected))assert.deepEqual(actual.observed[k],v,expected.case_id+':'+k);}
const sha=(p)=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const artifact=JSON.parse(fs.readFileSync('ios/build/artifact-bind.json'));
for(const [name,digest] of Object.entries(artifact.files))assert.equal(sha('ios/build/DerivedData/Build/Products/Release-iphonesimulator/HostProbe.app/'+name),digest);
const log_hashes={};for(const name of ['probe-'+process.argv[3]+'.log','probe-'+process.argv[3]+'.stderr.log','launch-'+process.argv[3]+'.log'])log_hashes[name]=sha('ios/build/'+name);
fs.writeFileSync('ios/build/run-'+process.argv[3]+'-evidence.json',JSON.stringify({artifact,log_hashes,observations:report.observations},null,2)+'\n');
console.log(JSON.stringify({result:'passed',proof_class:'host_integration',cases:report.observations.length,process:'fresh'}));
NODE
done
