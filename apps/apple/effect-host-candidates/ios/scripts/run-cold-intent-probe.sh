#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$*" == "--release --offline --fresh-process" ]] || { echo 'Require --release --offline --fresh-process'; exit 2; }
: "${HEALTHMD_COLD_PHASE:=all}"
if [[ "$HEALTHMD_COLD_PHASE" == all || "$HEALTHMD_COLD_PHASE" == build || "$HEALTHMD_COLD_PHASE" == ingress ]]; then : "${HEALTHMD_PROBE_SIMULATOR_ID:?Set reviewed booted private simulator target}"; fi
export HEALTHMD_COLD_PHASE
# CLI fallback only when XcodeBuildMCP cannot support this exact private workspace/target.
# No boot/reset/settings/global process cleanup. Every subprocess owns a new process group.
node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,writeFile,readFile,rename} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
assert.equal(process.version,'v24.21.0');
const root=process.cwd(),out=resolve(root,'ios/build/cold-intent');
const target=process.env.HEALTHMD_PROBE_SIMULATOR_ID;
const phase=process.env.HEALTHMD_COLD_PHASE;assert.ok(['all','bundle','prepare','build','ingress'].includes(phase),'explicit_phase');
if(['all','build','ingress'].includes(phase))assert.match(target,/^[A-Fa-f0-9-]{36}$/,'reviewed_target_required');
await mkdir(out,{recursive:true});
const overallEnd=performance.now()+900000;
const owned=new Set();let stopping=false;
function signal(child,signal){if(owned.has(child)&&Number.isInteger(child.pid)){try{process.kill(-child.pid,signal);}catch(error){if(error.code!=='ESRCH')throw error;}}}
async function stop(child){signal(child,'SIGTERM');await new Promise(r=>setTimeout(r,2000));signal(child,'SIGKILL');owned.delete(child);}
async function stopAll(){stopping=true;await Promise.all([...owned].map(stop));}
const overallTimer=setTimeout(()=>{void stopAll().finally(()=>process.exit(124));},900000);
for(const name of ['SIGINT','SIGTERM'])process.once(name,()=>{void stopAll().finally(()=>process.exit(130));});
async function run(name,command,args,limit,cap){
  assert.ok(!stopping&&performance.now()<overallEnd,'overall_deadline');
  const log=createWriteStream(resolve(out,name+'.log'),{flags:'w'});
  const child=spawn(command,args,{cwd:root,env:{...process.env,HEALTHMD_COLD_SUPERVISED:'1'},detached:true,stdio:['ignore','pipe','pipe']});
  owned.add(child);let bytes=0,failed,exit;const chunks=[];
  log.on('error',()=>{failed??='log_write_failure';signal(child,'SIGTERM');setTimeout(()=>signal(child,'SIGKILL'),2000).unref();});
  const deadline=setTimeout(()=>{failed??='command_deadline';signal(child,'SIGTERM');setTimeout(()=>signal(child,'SIGKILL'),2000).unref();},Math.min(limit,overallEnd-performance.now()));
  function output(chunk){
    if(failed)return;
    const remaining=cap-bytes;
    if(chunk.length>remaining){if(remaining>0)log.write(chunk.subarray(0,remaining));bytes=cap;failed='output_limit';signal(child,'SIGTERM');setTimeout(()=>signal(child,'SIGKILL'),2000).unref();return;}
    bytes+=chunk.length;chunks.push(chunk);if(!log.write(chunk)){child.stdout.pause();child.stderr.pause();log.once('drain',()=>{child.stdout.resume();child.stderr.resume();});}
  }
  child.stdout.on('data',output);child.stderr.on('data',output);
  try{exit=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});}
  finally{clearTimeout(deadline);await stop(child);await new Promise((resolve,reject)=>log.end(error=>error?reject(error):resolve()));}
  const evidence={name,command,args,limit_ms:limit,overall_limit_ms:900000,output_cap_bytes:cap,output_bytes:bytes,exit,bound_failure:failed??null};
  await writeFile(resolve(out,name+'-supervision.json'),JSON.stringify(evidence,null,2)+'\n');
  assert.ok(!failed&&exit?.code===0,name+':'+(failed??'command_failed'));
  return Buffer.concat(chunks).toString('utf8');
}
try{
if(phase==='build'||phase==='ingress'){
  // Purpose build_sim actually rejected three reviewed private profiles before compilation.
  // Native fallback phases reuse prepared bytes and cannot rebundle or compile Hermes.
  const shaPrepared=async p=>createHash('sha256').update(await readFile(p)).digest('hex');
  const workspace=resolve(out,'ColdHostProbe.xcworkspace');
  const preparedPins={
    'main.jsbundle':'495a516f6cd2d965c72ce5b0f8f8cb0fc8af84c1cc791062168a7f0bbcb2b7ae',
    'metro-source.jsbundle':'004761a7f17afcc5672897c41f397ffdbd93893ee893ea70fc4db2f6f5610a44',
    'ColdHostProbe.xcworkspace/contents.xcworkspacedata':'61259f6fa99ffdde10542da6bab8b0637239cee3c9288d1c9a8578b400866aa4',
    'ColdHostProbe.xcworkspace/xcshareddata/xcschemes/ColdHostProbe.xcscheme':'257d2e654f5125dffb5f4c3087e9fbe43aa78aaa61bb98d88710cf4a15893ba8',
    'prepare-evidence.json':'d9211a6b49b2859257c09012dd05d8f727febe14b9a9a902925f037a0f6fa81f',
    'asset-sha256.json':'e9ccdb9b2ee2893593f5d5cceb2163affe39908e7b683b7be0570f9c1c8bece0',
  };
  for(const[name,digest]of Object.entries(preparedPins))assert.equal(await shaPrepared(resolve(out,name)),digest,'prepared_artifact_drift');
  assert.equal(await shaPrepared(resolve(root,'fixtures/cold-intent-v1.json')),'9bbb60feafff21385987fe01b1605aa5674507d207d689dd1cfac0dede8e9064');
  assert.equal(target,'03AE614E-7BA2-4B5A-8CEA-D3A3BC2404B0','exact_reviewed_target_required');
  assert.equal((await run('sdk-version','xcrun',['--sdk','iphonesimulator','--show-sdk-version'],10000,4096)).trim(),'26.5','reviewed_sdk_required');
  const inventory=JSON.parse(await run('target-inventory','xcrun',['simctl','list','devices','booted','--json'],10000,1048576));
  assert.ok(Object.entries(inventory.devices).some(([runtime,list])=>runtime.endsWith('iOS-26-5')&&list.some(d=>d.udid===target&&d.state==='Booted')),'reviewed_iOS26_5_booted_target_required');
  const args=['-workspace',workspace,'-scheme','ColdHostProbe','-configuration','Release','-sdk','iphonesimulator26.5','-destination','id='+target,'-derivedDataPath',out+'/DerivedData','CODE_SIGNING_ALLOWED=NO','NODE_BINARY='+process.execPath];
  const app=out+'/DerivedData/Build/Products/Release-iphonesimulator/ColdHostProbe.app';
  if(phase==='build')await run('build','xcodebuild',[...args,'build-for-testing'],300000,16777216);
  const id=await run('built-identity','/usr/libexec/PlistBuddy',['-c','Print CFBundleIdentifier',app+'/Info.plist'],10000,4096);
  assert.equal(id.trim(),'com.healthmd.effecthost.ioscandidate.cold');
  assert.equal(await shaPrepared(app+'/main.jsbundle'),preparedPins['main.jsbundle']);
  const artifact={bundle_id:id.trim(),executable:await shaPrepared(app+'/ColdHostProbe'),packaged_hermes_asset:await shaPrepared(app+'/main.jsbundle'),prepared_input_pins:preparedPins,proof_class:'artifact_only'};
  if(phase==='build'){
    await writeFile(out+'/built-artifact.json',JSON.stringify(artifact,null,2)+'\n');
    clearTimeout(overallTimer);console.log('Bounded build-only fallback completed; actual OS ingress remains unrun.');process.exit(0);
  }
  // Ingress requires a separate ROOT grant after artifact review and purpose test_sim attempt.
  const built=JSON.parse(await readFile(out+'/built-artifact.json','utf8'));
  assert.deepEqual(built,artifact,'reviewed_built_artifact_drift');
  await run('ingress','xcodebuild',[...args,'-resultBundlePath',out+'/ActualSiriIngress.xcresult','test-without-building'],300000,16777216);
  clearTimeout(overallTimer);console.log('Actual Siri XCTest fallback completed; independently inspect witnesses and artifact binding.');process.exit(0);
}
if(phase==='all'){
const inventory=JSON.parse(await run('target-inventory','xcrun',['simctl','list','devices','booted','--json'],10000,1048576));
assert.ok(Object.entries(inventory.devices).some(([runtime,list])=>runtime.endsWith('iOS-26-5')&&list.some(d=>d.udid===target&&d.state==='Booted')),'reviewed_iOS26_5_booted_target_required');
}
const sha=async p=>createHash('sha256').update(await readFile(p)).digest('hex');
const prepareInputPins={
  'main.jsbundle':'004761a7f17afcc5672897c41f397ffdbd93893ee893ea70fc4db2f6f5610a44',
  'metro-inputs.json':'4342a2b21b8ed2e48cef35fe37d181c501282a395129cacedb01acd0d337359d',
  'asset-sha256.json':'49fb2224c549b06a92cf00d0a437460b749c329b8baa5b45b4551bb6893a8413',
  'source-inputs.json':'327c6b5184771723046feda49acf26da47e1999d9e784237a17a4480ab426ac5',
  'esbuild-metafile.json':'4131aaa47a2049abaf3fb87b2c56791fa3aadeccdaf8edc89cd7ca52b46d673b',
  'bundle.log':'ac611aa78c9e9e6d1be22caeb8eea61a7634e46830f9e17119f9b210b15a5ae3',
  'bundle-supervision.json':'ebc4198f15006efc1a0f79305fe3d47c667157caa2a8dd0942d9ee66e69ab429',
};
if(phase==='prepare'){
  for(const[name,digest]of Object.entries(prepareInputPins))assert.equal(await sha(resolve(out,name)),digest,'frozen_bundle_drift');
  assert.equal(await sha(resolve(root,'fixtures/cold-intent-v1.json')),'9bbb60feafff21385987fe01b1605aa5674507d207d689dd1cfac0dede8e9064');
  const graph=JSON.parse(await readFile(out+'/metro-inputs.json','utf8'));
  assert.equal(graph.physical_inputs.length,582);assert.equal(new Set(graph.physical_inputs.map(x=>x.path)).size,582);
  assert.equal(graph.virtual_inputs.length,1);assert.equal(graph.virtual_inputs[0].path,'__prelude__');assert.equal(graph.virtual_inputs[0].bytes,248);
  assert.equal(graph.virtual_inputs[0].sha256,'c118cbe823031197e989134a0354275067d0f5c0157dde853f46dac3b132adc9');
  const claims=new Map(graph.physical_inputs.map(x=>[x.path,x.sha256]));
  assert.equal(claims.get('packages/healthmd-core-ts/dist/core/host-interfaces/capabilities.js'),'ae1516fb397db074c95fc14214b3a48f99192daa16f1d7ac00f047d9b1ed94ef');
  assert.ok(!claims.has('packages/healthmd-core-ts/dist/core/host-interfaces/faults.js') || claims.get('packages/healthmd-core-ts/dist/core/host-interfaces/faults.js')==='662d61db6a41fcfa2fcc25c42c51a756bbedb7d1c06371832a191f853995b4a0','optional_faults_claim_drift');
  assert.equal(JSON.parse(await readFile(out+'/source-inputs.json','utf8')).length,67);
  const frozenAsset=JSON.parse(await readFile(out+'/asset-sha256.json','utf8'));
  assert.equal(frozenAsset.physical_react,resolve(root,'node_modules/react'));assert.equal(frozenAsset.physical_effect,resolve(root,'node_modules/effect'));
}else await run('bundle',process.execPath,['scripts/build-cold-intent.mjs'],120000,8388608);
if(phase==='bundle'){clearTimeout(overallTimer);console.log('Bounded bundle-only phase completed; no simulator/native commands run.');process.exit(0);}
const workspace=resolve(out,'ColdHostProbe.xcworkspace');
await mkdir(workspace+'/xcshareddata/xcschemes',{recursive:true});
await writeFile(workspace+'/contents.xcworkspacedata',`<?xml version="1.0"?><Workspace version="1.0"><FileRef location="absolute:${root}/ios/HostProbe.xcodeproj"/><FileRef location="absolute:${root}/ios/Pods/Pods.xcodeproj"/></Workspace>`);
const ref=(id,name,product)=>`<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id}" BuildableName="${product}" BlueprintName="${name}" ReferencedContainer="container:${root}/ios/HostProbe.xcodeproj"/>`;
const appRef=ref('64D8139A69CBD01BBD0A99B0','ColdHostProbe','ColdHostProbe.app'),testRef=ref('AD6522D201900DF3C36DA830','ColdProbeIntentUITests','ColdProbeIntentUITests.xctest');
await writeFile(workspace+'/xcshareddata/xcschemes/ColdHostProbe.xcscheme',`<?xml version="1.0"?><Scheme version="1.3"><BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">${appRef}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="NO"><Testables><TestableReference skipped="NO">${testRef}</TestableReference></Testables></TestAction></Scheme>`);
const compiler=resolve(root,'ios/Pods/hermes-engine/destroot/bin/hermesc');
assert.equal(await sha(compiler),'459d352c9a3cfdbe9289a167d93f7e30700c6ee591dfee3a4d52dc26eb8548cb','hermes_compiler_drift');
await run('hermes',compiler,['-O','-emit-binary','-out',out+'/main.hbc',out+'/main.jsbundle'],30000,1048576);
await rename(out+'/main.jsbundle',out+'/metro-source.jsbundle');await rename(out+'/main.hbc',out+'/main.jsbundle');
const asset=JSON.parse(await readFile(out+'/asset-sha256.json','utf8'));
asset.hermes_compiler=await sha(compiler);asset.packaged_hermes_asset=await sha(out+'/main.jsbundle');await writeFile(out+'/asset-sha256.json',JSON.stringify(asset,null,2)+'\n');
if(phase==='prepare'){
  await writeFile(out+'/prepare-evidence.json',JSON.stringify({result:'passed',proof_class:'prepared_artifact_only',input_pins:prepareInputPins,selected_faults_dependency:'absent_not_used_in_frozen_graph',original_js_sha256:await sha(out+'/metro-source.jsbundle'),packaged_hermes_asset_sha256:asset.packaged_hermes_asset,hermes_compiler_sha256:asset.hermes_compiler,workspace_sha256:await sha(workspace+'/contents.xcworkspacedata'),scheme_sha256:await sha(workspace+'/xcshareddata/xcschemes/ColdHostProbe.xcscheme'),native_build_or_ingress:'unrun'},null,2)+'\n');
  clearTimeout(overallTimer);console.log('Bounded prepare-only phase completed; frozen bundle reused; no simulator/native build/test commands run.');process.exit(0);
}
const args=['-workspace',workspace,'-scheme','ColdHostProbe','-configuration','Release','-sdk','iphonesimulator','-destination','id='+target,'-derivedDataPath',out+'/DerivedData','CODE_SIGNING_ALLOWED=NO','NODE_BINARY='+process.execPath];
await run('build','xcodebuild',[...args,'build-for-testing'],300000,16777216);
const app=out+'/DerivedData/Build/Products/Release-iphonesimulator/ColdHostProbe.app';
const id=await run('built-identity','/usr/libexec/PlistBuddy',['-c','Print CFBundleIdentifier',app+'/Info.plist'],10000,4096);
assert.equal(id.trim(),'com.healthmd.effecthost.ioscandidate.cold');assert.equal(await sha(app+'/main.jsbundle'),asset.packaged_hermes_asset);
await writeFile(out+'/built-artifact.json',JSON.stringify({bundle_id:id.trim(),executable:await sha(app+'/ColdHostProbe'),asset,proof_class:'artifact_only'},null,2)+'\n');
// XCTest installation is not ingress; only actual matched fresh Siri response attachments qualify.
await run('ingress','xcodebuild',[...args,'-resultBundlePath',out+'/ActualSiriIngress.xcresult','test-without-building'],300000,16777216);
console.log('Actual Siri XCTest completed; independently inspect invocation witnesses/artifact binding.');
}catch(error){await stopAll();throw new Error('cold_probe_command_failed');}finally{clearTimeout(overallTimer);}
NODE
