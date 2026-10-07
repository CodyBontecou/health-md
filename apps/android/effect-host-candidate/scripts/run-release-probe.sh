#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$*" == '--channel play --target required-local-device --offline --fresh-process' ]] || { echo 'Require exact private Play/offline/fresh-process arguments'; exit 2; }
mkdir -p dist/runtime
node <<'NODE'
const fs = require('node:fs'), assert = require('node:assert/strict'), crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const serial = fs.readFileSync('../AGENTS.md','utf8').match(/\*\*Device serial:\*\* `([^`]+)`/)[1];
const adb = process.env.HOME + '/Library/Android/sdk/platform-tools/adb';
const appId = 'com.healthmd.effecthost.androidcandidate.play', testId = appId + '.test';
const sdkTools = process.env.HOME + '/Library/Android/sdk/build-tools/36.0.0';
const apk = 'app/build/outputs/apk/play/release/app-play-release.apk';
const testApk = 'app/build/outputs/apk/androidTest/play/release/app-play-release-androidTest.apk';
const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const redact = s => String(s ?? '').split(serial).join('[required-target]');
const fixedFailure = (code, action) => Object.assign(new Error(code), {safeCode:code, action});
let runtimeStarted = false, installed = false;
function command(action, executable, args, timeoutMs, outputBytes, log, allowFailure = false) {
  // SIGKILL applies only to this spawned client/tool PID, never to the adb daemon.
  const result = spawnSync(executable, args, {encoding:'utf8', timeout:timeoutMs, maxBuffer:outputBytes, killSignal:'SIGKILL'});
  const combined = redact(result.stdout) + redact(result.stderr);
  if (Buffer.byteLength(combined)>outputBytes) { if(log)fs.writeFileSync('dist/runtime/'+log,'OUTPUT_LIMIT\n'); throw fixedFailure('output_limit',action); }
  if (log) fs.writeFileSync('dist/runtime/' + log, combined);
  if (result.error) throw fixedFailure(result.error.code === 'ETIMEDOUT' ? 'command_timeout' : result.error.code === 'ENOBUFS' ? 'output_limit' : 'command_unavailable', action);
  if (result.status !== 0 && !allowFailure) throw fixedFailure('command_failure', action);
  return result;
}
const target = (action, args, timeoutMs, outputBytes, log, allowFailure = false) => command(action, adb, ['-s',serial,...args], timeoutMs, outputBytes, log, allowFailure);
try {
  assert.equal(process.version,'v24.21.0');
  const state = target('target_preflight',['get-state'],10000,8192,null,true);
  const available = state.status === 0 && state.stdout.trim() === 'device';
  fs.writeFileSync('dist/runtime/target-preflight.json',JSON.stringify({required_target_available:available,runtime_check:available?'ready':'unrun',code:available?'connected':'required_target_unavailable'})+'\n');
  if (!available) throw fixedFailure('required_target_unavailable','target_preflight');
  const sdk = target('target_sdk',['shell','getprop','ro.build.version.sdk'],5000,8192).stdout.trim();
  const abis = target('target_abis',['shell','getprop','ro.product.cpu.abilist'],5000,8192).stdout.trim().split(',');
  assert.ok(/^\d{1,3}$/.test(sdk) && Number(sdk) >= 28);
  assert.ok(abis.some(a=>['arm64-v8a','armeabi-v7a','x86','x86_64'].includes(a)));
  assert.ok(fs.existsSync(apk) && fs.existsSync(testApk));
  const expectedCertificate = fs.readFileSync('.test-signing/public-certificate.sha256','utf8').trim();
  for (const [label,path] of [['app',apk],['test',testApk]]) {
    const signature = command(label+'_signature',sdkTools+'/apksigner',['verify','--print-certs',path],15000,65536,label+'-signature.txt').stdout;
    assert.equal(signature.match(/Signer #1 certificate SHA-256 digest: ([0-9a-f]+)/i)[1].toLowerCase(),expectedCertificate);
  }
  const badging = command('app_badging',sdkTools+'/aapt2',['dump','badging',apk],10000,524288).stdout;
  assert.ok(badging.includes("name='"+appId+"'")); assert.ok(!badging.includes('application-debuggable'));
  assert.ok(badging.includes("minSdkVersion:'28'")); assert.ok(badging.includes("targetSdkVersion:'36'"));
  for(const abi of ['arm64-v8a','armeabi-v7a','x86','x86_64']) assert.ok(badging.includes("'"+abi+"'"));
  const permissions = command('app_permissions',sdkTools+'/aapt2',['dump','permissions',apk],10000,65536).stdout;
  assert.ok(!permissions.includes('android.permission.INTERNET') && !permissions.includes('android.permission.health.'));
  const testBadging = command('test_badging',sdkTools+'/aapt2',['dump','badging',testApk],10000,524288).stdout;
  assert.ok(testBadging.includes("name='"+testId+"'"));
  const artifact = {application_id:appId,apk_sha256:sha(apk),test_apk_sha256:sha(testApk),certificate_sha256:expectedCertificate,signing:'isolated_local_test_only',bundle_sha256:sha('dist/assets/index.android.bundle'),fixture_sha256:sha('fixtures/host-probe-v1.json'),target_sdk:Number(sdk),target_abis:abis};
  const bundle = command('packaged_bundle','/usr/bin/unzip',['-p',apk,'assets/index.android.bundle'],10000,2097152).stdout;
  assert.equal(crypto.createHash('sha256').update(bundle).digest('hex'),artifact.bundle_sha256);
  target('install_app',['install','-r',apk],45000,65536,'app-install.log'); installed = true;
  target('install_test',['install','-r',testApk],45000,65536,'test-install.log');
  for (const [id,digest] of [[appId,artifact.apk_sha256],[testId,artifact.test_apk_sha256]]) {
    const path = target('installed_path',['shell','pm','path',id],5000,8192).stdout.trim();
    assert.ok(/^package:\/data\/app\/[A-Za-z0-9_~+./=-]+\/base\.apk$/.test(path));
    const installedHash = target('installed_hash',['shell','sha256sum',path.slice('package:'.length)],10000,8192).stdout.trim().split(/\s+/)[0];
    assert.equal(installedHash,digest);
  }
  artifact.installed_matches_built = true;
  fs.writeFileSync('dist/runtime/artifacts.json',JSON.stringify(artifact,null,2)+'\n');
  const fixture = JSON.parse(fs.readFileSync('fixtures/host-probe-v1.json'));
  for (let run=1;run<=2;run++) {
    target('fresh_stop',['shell','am','force-stop',appId],5000,8192);
    runtimeStarted = true;
    const text = target('instrumentation_'+run,['shell','am','instrument','-w','-r',testId+'/androidx.test.runner.AndroidJUnitRunner'],45000,2097152,'instrumentation-'+run+'.log').stdout;
    assert.ok(text.includes('OK (1 test)'));
    const rows=text.split('\n').filter(x=>x.startsWith('INSTRUMENTATION_STATUS: healthmd_candidate_result='));
    assert.equal(rows.length,1); assert.ok(Buffer.byteLength(rows[0])<65536);
    const report=JSON.parse(rows[0].slice('INSTRUMENTATION_STATUS: healthmd_candidate_result='.length));
    assert.equal(report.result,'passed'); assert.equal(report.teardown_ack,true); assert.ok(report.teardown_ms<5000);
    assert.equal(report.observations.length,fixture.cases.length);
    for(const expected of fixture.cases) {const actual=report.observations.find(x=>x.case_id===expected.case_id);assert.ok(actual);for(const[k,v]of Object.entries(expected.expected))assert.deepEqual(actual.observed[k],v,expected.case_id+':'+k);}
    fs.writeFileSync('dist/runtime/run-'+run+'-evidence.json',JSON.stringify({proof_class:'host_integration',process:'fresh',artifact,log_sha256:sha('dist/runtime/instrumentation-'+run+'.log'),report},null,2)+'\n');
    console.log(JSON.stringify({result:'passed',proof_class:'host_integration',cases:fixture.cases.length,process:'fresh'}));
  }
} catch (error) {
  // A failed/expired client can leave its private instrumentation running; stop only this app.
  if(installed) spawnSync(adb,['-s',serial,'shell','am','force-stop',appId],{encoding:'utf8',timeout:5000,maxBuffer:8192,killSignal:'SIGKILL'});
  const result={result:'failed',runtime_check:runtimeStarted?'failed':'unrun',code:error.safeCode??'harness_assertion',action:error.action??'artifact_or_fixture_guard'};
  fs.writeFileSync('dist/runtime/failure.json',JSON.stringify(result)+'\n');console.error(JSON.stringify(result));process.exit(error.safeCode==='required_target_unavailable'?3:1);
}
NODE
