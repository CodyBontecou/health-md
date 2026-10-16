import {spawn} from "node:child_process";
import {readFile, writeFile, mkdir, rename, realpath} from "node:fs/promises";
import {resolve, relative} from "node:path";
import {pathToFileURL} from "node:url";
import {createHash} from "node:crypto";
import {createRequire} from "node:module";
import assert from "node:assert/strict";
import {TextDecoder} from "node:util";

const root = resolve(import.meta.dirname, "..");
const pause = ms => new Promise(r => setTimeout(r, ms));
const digest = b => createHash("sha256").update(b).digest("hex");
/** Fresh process group ONLY. Parent exit is distinct from descendant cleanup. */
export async function runBounded(argv, {cwd = root, deadlineMs = 120000, cap = 16777216, cleanupMs = 3000, env = process.env} = {}) {
  assert.ok(Array.isArray(argv) && argv.length && argv.every(x => typeof x === "string"));
  assert.ok(deadlineMs > 0 && deadlineMs <= 300000 && cap > 0 && cap <= 16777216);
  const child = spawn(argv[0], argv.slice(1), {cwd, env, detached: true, stdio: ["ignore", "pipe", "pipe"]});
  let total = 0, reason = null, code = null, signal = null, exited = false;
  const chunks = [];
  const observedHash = createHash("sha256");
  const osFaults = {group_query_denied:0, group_query_unverified:0, group_signal_denied:0, group_signal_unverified:0};
  let lastGroupStatus = "not_created";
  const osFault = key => { osFaults[key] = Math.min(1000000,osFaults[key]+1); reason ??= key; };
  const kill = sig => {
    if (child.pid === undefined) return;
    try { process.kill(-child.pid, sig); }
    catch(e) { if(e.code !== "ESRCH") osFault(e.code === "EPERM" ? "group_signal_denied" : "group_signal_unverified"); }
  };
  const groupExists = () => {
    if (child.pid === undefined) { lastGroupStatus="not_created"; return false; }
    try { process.kill(-child.pid, 0); lastGroupStatus="present"; return true; }
    catch(e) {
      if(e.code === "ESRCH") { lastGroupStatus="absent_esrch"; return false; }
      // Permission/unknown failures are NEVER absence. Keep bounded cleanup/reaping active.
      lastGroupStatus="unverified";
      osFault(e.code === "EPERM" ? "group_query_denied" : "group_query_unverified"); return true;
    }
  };
  let abort; const aborted = new Promise(r => { abort = r; });
  let settle;
  const ended = new Promise(r => { settle = r; });
  child.once("error", () => { reason ??= "spawn_failure"; exited = true; settle(); });
  child.once("exit", (c,s) => { code = c; signal = s; exited = true; settle(); });
  const consume = data => {
    observedHash.update(data);
    total += data.length;
    if (total <= cap) chunks.push(data);
    else { reason ??= "output_limit"; kill("SIGTERM"); abort(); }
  };
  child.stdout.on("data", consume); child.stderr.on("data", consume);
  const timer = setTimeout(() => { reason ??= "command_deadline"; kill("SIGTERM"); abort(); }, deadlineMs);
  let escalation = false; let cleanupDeadlineMissed = false;
  try {
    await Promise.race([ended, aborted]); // the single owned deadline timer aborts this wait
    if (!exited) { reason ??= "command_deadline"; kill("SIGTERM"); }
    // A normal parent can leave descendants. First allow finite ordinary exit/drain, then terminate
    // the ENTIRE own group irrespective of whether the parent has already been reaped.
    const natural = Date.now() + 150;
    while (groupExists() && Date.now() < natural && reason === null) await pause(10);
    if (groupExists()) {
      reason ??= "descendant_cleanup_required";
      kill("SIGTERM");
      const grace = Date.now() + 250;
      while (groupExists() && Date.now() < grace) await pause(10);
      if (groupExists()) { escalation = true; kill("SIGKILL"); }
    }
    const until = Date.now() + cleanupMs;
    while ((!exited || groupExists()) && Date.now() < until) await pause(10);
    if (!exited || groupExists()) { cleanupDeadlineMissed = true; reason = "incomplete_cleanup"; }
    // Stream closure after group absence proves no owned descendants retain its pipe descriptors.
    const streamsClosed = child.stdout.destroyed && child.stderr.destroyed;
    if (!streamsClosed) {
      await new Promise(resolve => {
        const closed = () => { clearTimeout(drainTimer); resolve(); };
        const drainTimer = setTimeout(() => { child.removeListener("close", closed); resolve(); }, 250);
        child.once("close", closed);
      });
    }
    if (!child.stdout.destroyed || !child.stderr.destroyed) { cleanupDeadlineMissed = true; reason = "incomplete_cleanup"; }
  } finally {
    clearTimeout(timer);
    if (groupExists()) kill("SIGKILL");
    // Even an incomplete-result path performs a second finite best-effort reap. It cannot revise
    // the previously failed acknowledgment into success, and never kills outside its fresh group.
    const end = Date.now()+1000;
    while ((!exited || groupExists()) && Date.now()<end) await pause(10);
  }
  // Construct terminal evidence AFTER the final owned cleanup effort; no late OS denial can be
  // thrown away by a precomputed return. Exact final ESRCH is distinct from denial/unverified.
  const groupAbsent = !groupExists();
  const physicalCleanup = exited && groupAbsent && child.stdout.destroyed && child.stderr.destroyed;
  if(!physicalCleanup) { cleanupDeadlineMissed=true; reason="incomplete_cleanup"; }
  const retainedRaw = Buffer.concat(chunks);
  let output = "";
  try { output = new TextDecoder("utf-8", {fatal:true, ignoreBOM:true}).decode(retainedRaw); }
  catch { reason ??= "output_invalid_utf8"; }
  if(Buffer.byteLength(output)>cap) { output=""; reason ??= "retained_output_limit"; }
  return {result: reason === null && code === 0 ? "passed" : "failed", code, signal, reason,
    output, observed_output_bytes:total, retained_output_bytes:Buffer.byteLength(output), retained_raw_bytes:retainedRaw.length,
    retained_raw_sha256:digest(retainedRaw), observed_raw_sha256:observedHash.copy().digest("hex"), escalation,
    parent_reaped:exited, group_absent:groupAbsent, cleanup_ack:!cleanupDeadlineMissed && physicalCleanup,
    cleanup_deadline_missed:cleanupDeadlineMissed, late_physical_cleanup_observed:cleanupDeadlineMissed && physicalCleanup,
    group_observation:lastGroupStatus, supervisor_os_faults:Object.freeze({...osFaults})};
}

// Independently fixed lifetime expectations, NOT native WorkManager evidence; execute only after review.
const childIgnoringTerm = "process.on('SIGTERM',()=>{});process.stdout.write('CHILD_TERM_HANDLER_READY\\n');setInterval(()=>{},1000)";
const spawnOwned = "const{spawn}=require('node:child_process');const child=spawn(process.execPath,['-e',"+JSON.stringify(childIgnoringTerm)+"],{stdio:'inherit'});";
export const supervisorFaultCases = Object.freeze([
  {id:"normal_parent_child_exit", stimulus:[process.execPath,"-e","const{spawn}=require('node:child_process');const c=spawn(process.execPath,['-e','setTimeout(()=>process.exit(0),20)'],{stdio:'inherit'});c.on('exit',()=>process.exit(0));"], options:{deadlineMs:1000}, expected:{result:"passed",reason:null,escalation:false,parent_reaped:true,group_absent:true,cleanup_ack:true}},
  {id:"deadline_child_ignores_term", stimulus:[process.execPath,"-e",spawnOwned+"process.on('SIGTERM',()=>{});process.stdout.write('PARENT_TERM_HANDLER_READY\\n');setInterval(()=>{},1000)"], options:{deadlineMs:500}, requiredReadiness:["PARENT_TERM_HANDLER_READY","CHILD_TERM_HANDLER_READY"], expected:{result:"failed",reason:"command_deadline",escalation:true,parent_reaped:true,group_absent:true,cleanup_ack:true}},
  {id:"parent_fast_term_child_ignores_term", stimulus:[process.execPath,"-e",spawnOwned+"process.on('SIGTERM',()=>process.exit(0));process.stdout.write('PARENT_TERM_HANDLER_READY\\n');setInterval(()=>{},1000)"], options:{deadlineMs:500}, requiredReadiness:["PARENT_TERM_HANDLER_READY","CHILD_TERM_HANDLER_READY"], expected:{result:"failed",reason:"command_deadline",escalation:true,parent_reaped:true,group_absent:true,cleanup_ack:true}},
  {id:"combined_output_overflow", stimulus:[process.execPath,"-e","process.stdout.write('x'.repeat(8192));process.stderr.write('y'.repeat(8192));setInterval(()=>{},1000)"], options:{deadlineMs:1000,cap:4096}, expected:{result:"failed",reason:"output_limit",parent_reaped:true,group_absent:true,cleanup_ack:true}},
  {id:"cleanup_ack_timeout", stimulus:[process.execPath,"-e",spawnOwned+"process.on('SIGTERM',()=>{});process.stdout.write('PARENT_TERM_HANDLER_READY\\n');setInterval(()=>{},1000)"], options:{deadlineMs:500,cleanupMs:0}, requiredReadiness:["PARENT_TERM_HANDLER_READY","CHILD_TERM_HANDLER_READY"], expected:{result:"failed",reason:"incomplete_cleanup",cleanup_ack:false}},
]);
// ROOT's two independent literals were archived before changing UTF8 handling. Unexecuted.
export const supervisorUtf8Cases = Object.freeze([
  {id:"invalid_incomplete_utf8",stimulus:[process.execPath,"-e","process.stdout.write(Buffer.concat([Buffer.alloc(4095,120),Buffer.from([0xf0])]))"],options:{deadlineMs:1000,cap:4096},expected:{result:"failed",reason:"output_invalid_utf8",observed_output_bytes:4096,retained_output_bytes:0,cleanup_ack:true,group_absent:true}},
  {id:"split_valid_utf8",stimulus:[process.execPath,"-e","process.stdout.write(Buffer.from([0xf0,0x9f]));setTimeout(()=>process.stdout.write(Buffer.from([0x98,0x80])),20)"],options:{deadlineMs:1000,cap:4},expected:{result:"passed",reason:null,output:"😀",observed_output_bytes:4,retained_output_bytes:4,cleanup_ack:true,group_absent:true}},
]);

export async function buildColdWorker() {
  assert.equal(process.version, "v24.21.0");
  const require = createRequire(resolve(root, "package.json"));
  const core = resolve(root, "../../../packages/healthmd-core-ts/dist/core/host-interfaces/capabilities.js");
  // This remains an execution precondition; ROOT separately grants/reconciles the complete current
  //43/26 cohort before this script is ever run. No stale34/20/40/24 cohort admission from this pin.
  assert.equal(digest(await readFile(core)), "ae1516fb397db074c95fc14214b3a48f99192daa16f1d7ac00f047d9b1ed94ef", "accepted_selected_capability_drift");
  const fixture = await readFile(resolve(root,"fixtures/cold-worker-v1.json"));
  assert.equal(digest(fixture),"f2a67c17977e3eb615c581bccb73a817d417a57f272ede30a1d7ebb38db00bd2");
  assert.equal(require("react/package.json").version,"19.2.3");
  assert.equal(require("effect/package.json").version,"4.0.1");
  const {build} = await import("esbuild");
  const outputRoot = resolve(root, "dist/cold-worker"); await mkdir(resolve(outputRoot,"assets"), {recursive:true});
  const bundle = await build({entryPoints:[resolve(root,"src/cold-worker-probe.ts")], outfile:resolve(outputRoot,"registration.js"),
    bundle:true, format:"cjs", platform:"neutral", target:"es2022", external:["react","react-native"], metafile:true,
    plugins:[{name:"owned-physical-effect",setup(b){
      b.onResolve({filter:/^healthmd-candidate-capabilities$/},()=>({path:core}));
      b.onResolve({filter:/^effect(?:\/|$)/},({path})=>({path:require.resolve(path)}));
    }}]});
  const inputs=[];
  for (const path of Object.keys(bundle.metafile.inputs).sort()) {
    const actual=await realpath(resolve(path));
    if(path.includes("node_modules/effect/")) assert.ok(actual.startsWith(await realpath(resolve(root,"node_modules/effect"))+"/"),"duplicate_effect");
    inputs.push({path:relative(root,actual),sha256:digest(await readFile(actual))});
  }
  await writeFile(resolve(outputRoot,"entry.js"),'require("./registration.js");\n');
  const {default:Metro}=await import("metro");
  const config=await Metro.loadConfig({cwd:root,config:resolve(root,"metro.config.cjs")});
  const base=require("metro/private/DeltaBundler/Serializers/baseJSBundle").default;
  const stringify=require("metro/private/lib/bundleToString").default;
  const preludePath=require.resolve("metro/private/lib/getPreludeCode");
  const prependPath=require.resolve("metro/private/lib/getPrependedScripts");
  assert.equal(digest(await readFile(preludePath)),"9f1d9bdc49529b24329164ea7c83e985dcc45ebc587528f5bd99cbbd5ee0e10a","prelude_generator_drift");
  assert.equal(digest(await readFile(prependPath)),"087a6f30ca2d8411d98de75feaabf27d34ec09266932dc8cadfd1bfeba8cd633","prepend_generator_drift");
  const preludeGenerator=require(preludePath).default;
  config.serializer.customSerializer=async(entry,prepend,graph,options)=>{
    const metro=[], virtual=[];
    assert.equal(options.dev,false,"release_prelude_required");
    assert.equal(config.transformer.globalPrefix,"","unexpected_global_prefix");
    const preludeOptions={isDev:false,globalPrefix:config.transformer.globalPrefix,
      requireCycleIgnorePatterns:config.resolver.requireCycleIgnorePatterns,
      unstable_forceFullRefreshPatterns:config.resolver.unstable_forceFullRefreshPatterns};
    let preludeCount=0;
    async function record(module,role) {
      const path=module.path;
      const outputs=module.output.map(o=>({type:o.type,code_sha256:digest(Buffer.from(o.data.code)),code_bytes:Buffer.byteLength(o.data.code)}));
      if(path==="__prelude__") {
        assert.equal(role,"prepend");assert.equal(++preludeCount,1);
        assert.equal(module.dependencies.size,0);assert.equal(module.output.length,1);
        assert.equal(module.output[0].type,"js/script/virtual");
        const expected=Buffer.from(preludeGenerator(preludeOptions));
        assert.deepEqual(module.getSource(),expected);assert.equal(module.output[0].data.code,expected.toString("utf8"));
        virtual.push({path,role,generator:relative(root,preludePath),generator_sha256:digest(await readFile(preludePath)),
          prepend_generator:relative(root,prependPath),prepend_generator_sha256:digest(await readFile(prependPath)),
          options:{isDev:false,globalPrefix:"",requireCycleIgnorePatterns:preludeOptions.requireCycleIgnorePatterns.map(x=>x.toString()),unstable_forceFullRefreshPatterns:preludeOptions.unstable_forceFullRefreshPatterns.map(x=>x.toString())},
          source_sha256:digest(expected),source_bytes:expected.length,outputs});return;
      }
      assert.ok(!module.output.some(o=>o.type.endsWith("/virtual")),"unadmitted_virtual_metro_input");
      const actual=await realpath(path);assert.ok(actual.startsWith(root+"/"),"external_metro_input");
      assert.ok(!actual.includes("/src/HostProbe.tsx")&&!actual.endsWith("/dist/probe.js"),"old_autorun_input");
      if(actual.includes("/node_modules/react/"))assert.ok(actual.startsWith(await realpath(resolve(root,"node_modules/react"))+"/"),"duplicate_react");
      const raw=await readFile(actual);assert.deepEqual(module.getSource(),raw,"metro_source_drift");
      metro.push({path:relative(root,actual),role,sha256:digest(raw),bytes:raw.length,outputs});
    }
    for(const module of prepend)await record(module,"prepend");
    assert.equal(preludeCount,1,"missing_admitted_prelude");
    for(const module of [...graph.dependencies.values()].sort((a,b)=>a.path.localeCompare(b.path)))await record(module,"graph");
    const code=stringify(base(entry,prepend,graph,options)).code;
    await writeFile(resolve(outputRoot,"metro-inputs.json"),JSON.stringify({physical:metro,virtual,bundle_utf8_bytes:Buffer.byteLength(code),bundle_sha256:digest(Buffer.from(code))},null,2)+"\n");
    return code;
  };
  await Metro.runBuild(config,{entry:"dist/cold-worker/entry.js",out:resolve(outputRoot,"assets/cold-worker.android.bundle"),dev:false,minify:true,platform:"android"});
  await rename(resolve(outputRoot,"assets/cold-worker.android.bundle.js"),resolve(outputRoot,"assets/cold-worker.android.bundle"));
  await writeFile(resolve(outputRoot,"assets/cold-worker-v1.json"),fixture);
  await writeFile(resolve(outputRoot,"inputs.json"),JSON.stringify({inputs,metafile:bundle.metafile},null,2)+"\n");
}
if(process.argv[1]!==undefined && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  assert.deepEqual(process.argv.slice(2),["--bundle-only"]);
  await buildColdWorker();
}
