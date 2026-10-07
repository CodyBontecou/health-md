#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$*" == "--offline --fresh-process" ]] || { echo 'Require --offline --fresh-process'; exit 2; }
[[ "$(node --version)" == v24.21.0 ]] || { echo 'Use exact candidate Node'; exit 2; }
mkdir -p macos/build
npm run check > macos/build/check.log 2>&1
npm run build > macos/build/metro-build.log 2>&1
xcodebuild -workspace macos/build/HostProbe.xcworkspace -scheme HostProbe -configuration Release \
  -sdk macosx -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/DerivedData \
  CODE_SIGNING_ALLOWED=NO NODE_BINARY="$(command -v node)" build > macos/build/release-build.log 2>&1
app=macos/build/DerivedData/Build/Products/Release/HostProbe.app
[[ -f "$app/Contents/Resources/main.jsbundle" ]] || { echo 'Packaged offline bundle missing'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == com.healthmd.effecthost.maccandidate ]]
node --input-type=module - "$app" <<'NODE'
import {spawn} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const app=process.argv[2];
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const artifact={};for(const name of ['Contents/MacOS/HostProbe','Contents/Resources/main.jsbundle'])artifact[name]=sha(app+'/'+name);
const child=spawn(app+'/Contents/MacOS/HostProbe',[],{env:{...process.env,HEALTHMD_CANDIDATE_OFFLINE:'1'},stdio:['ignore','pipe','pipe']});
let stdout='',stderr='';
const report=await new Promise((resolve,reject)=>{
 const timer=setTimeout(()=>{child.kill('SIGTERM');reject(Error('candidate_timeout'));},30000);
 child.stdout.on('data',chunk=>{stdout+=chunk;if(stdout.length>131072){clearTimeout(timer);child.kill('SIGTERM');reject(Error('report_limit'));}
 const row=stdout.split('\n').find(x=>x.startsWith('HEALTHMD_CANDIDATE_RESULT '));
 if(row){clearTimeout(timer);child.kill('SIGTERM');resolve(JSON.parse(row.slice('HEALTHMD_CANDIDATE_RESULT '.length)));}});
 child.stderr.on('data',chunk=>{stderr+=chunk;if(stderr.length>1048576){clearTimeout(timer);child.kill('SIGTERM');reject(Error('diagnostic_limit'));}});
 child.on('error',reject);child.on('exit',()=>{if(!stdout.includes('HEALTHMD_CANDIDATE_RESULT ')){clearTimeout(timer);reject(Error('candidate_early_exit'));}});
});
writeFileSync('macos/build/probe-1.log',stdout);writeFileSync('macos/build/probe-1.stderr.log',stderr);
assert.equal(report.result,'passed');
const fixture=JSON.parse(readFileSync('fixtures/host-probe-v1.json'));
assert.equal(report.observations.length,fixture.cases.length);
for(const expected of fixture.cases){const actual=report.observations.find(x=>x.case_id===expected.case_id);assert.ok(actual);for(const[k,v]of Object.entries(expected.expected))assert.deepEqual(actual.observed[k],v,expected.case_id+':'+k);}
writeFileSync('macos/build/run-1-evidence.json',JSON.stringify({artifact,log_hashes:{stdout:sha('macos/build/probe-1.log'),stderr:sha('macos/build/probe-1.stderr.log')},observations:report.observations},null,2)+'\n');
console.log(JSON.stringify({result:'passed',proof_class:'host_integration',cases:report.observations.length,process:'fresh'}));
NODE
xcodebuild -workspace macos/build/HostProbe.xcworkspace -scheme HostProbe -configuration Release \
  -sdk macosx -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/DerivedData \
  CODE_SIGNING_ALLOWED=NO NODE_BINARY="$(command -v node)" test > macos/build/xctest.log 2>&1
