#!/bin/sh
set -eu
# Deliberately no implicit build, install, target discovery/substitution, kill, grant or settings route.
# ROOT first reviews source/supervisor faults and later grants exact prepared APK/cohort/target window.
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
exec node --input-type=module - "$@" <<'JS'
import assert from "node:assert/strict";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {resolve} from "node:path";
import {performance} from "node:perf_hooks";
import {createHash} from "node:crypto";
import {runBounded,supervisorFaultCases,supervisorUtf8Cases} from "./scripts/build-cold-worker.mjs";
assert.equal(process.version,"v24.21.0");
const argv=process.argv.slice(2);
const hash=b=>createHash("sha256").update(b).digest("hex");
// Closed ancillary scheduler diagnostics, never direct Worker execution or exclusive dispatch proof.
const schedulerPackage="com.healthmd.effecthost.androidcandidate.cold.play";
const schedulerService="androidx.work.impl.background.systemjob.SystemJobService";
const schedulerNamespace="androidx.work.systemjobscheduler";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const boundedInt=(x,min=0)=>Number.isSafeInteger(x)&&x>=min&&x<=2147483647;
const refuse=code=>{throw new Error(code);};
function schedulerBinding(job,expected) {
  const keys=["work_id","job_id","generation","service_package","service_class","namespace","user_id"];
  if(job===null||typeof job!=="object"||Array.isArray(job)||Object.keys(job).join()!==keys.join())refuse("scheduler_binding_invalid");
  if(typeof job.work_id!=="string"||!uuid.test(job.work_id)||job.work_id!==expected.work_id||
    !boundedInt(job.job_id)||job.generation!==0||job.service_package!==schedulerPackage||
    job.service_class!==schedulerService||job.namespace!==schedulerNamespace||
    !boundedInt(expected.api,34)||!boundedInt(expected.user_id)||job.user_id!==expected.user_id)refuse("scheduler_binding_invalid");
  return job;
}
function schedulerWitness(input,expected) {
  const keys=["job_id","generation","service_package","service_class","namespace","setup_pid","observed_absent_after_setup","pid_before_state","state_exit","state_stdout","pid_after_state","control_broadcasts_before_witness","work_id","api","user_id"];
  if(input===null||typeof input!=="object"||Array.isArray(input)||Object.keys(input).join()!==keys.join())refuse("scheduler_binding_invalid");
  const job=schedulerBinding({work_id:input.work_id,job_id:input.job_id,generation:input.generation,
    service_package:input.service_package,service_class:input.service_class,namespace:input.namespace,user_id:input.user_id},expected);
  if(input.api!==expected.api||input.control_broadcasts_before_witness!==0)refuse("scheduler_binding_invalid");
  if(!boundedInt(input.setup_pid,1)||input.observed_absent_after_setup!==true||
    !boundedInt(input.pid_before_state,1)||input.pid_after_state!==input.pid_before_state||
    input.pid_before_state===input.setup_pid||input.state_exit!==0||typeof input.state_stdout!=="string"||
    Buffer.byteLength(input.state_stdout)>128||!/^[a-z-]+(?:[ \t\r\n]+[a-z-]+)*[ \t\r\n]*$/.test(input.state_stdout))refuse("scheduler_witness_unobserved");
  const tokens=input.state_stdout.trim().split(/\s+/);
  if(new Set(tokens).size!==tokens.length||!tokens.every(x=>["active","pending","ready","waiting","user-stopped","backing-up","no-component"].includes(x))||!tokens.includes("active"))refuse("scheduler_witness_unobserved");
  return {scheduler_active:true,same_fresh_pid:true,own_job_workspec_binding:true,control_broadcasts_before_witness:0,
    exclusive_worker_dispatch_proven:false,host_proof_from_literal:false};
}
const schedulerLiteralContract={
  "positive": {
    "case_id": "own_system_job_active_before_control",
    "stimulus": {
      "job_id": 17,
      "generation": 0,
      "service_package": "com.healthmd.effecthost.androidcandidate.cold.play",
      "service_class": "androidx.work.impl.background.systemjob.SystemJobService",
      "namespace": "androidx.work.systemjobscheduler",
      "setup_pid": 101,
      "observed_absent_after_setup": true,
      "pid_before_state": 202,
      "state_exit": 0,
      "state_stdout": "active ready\n\n",
      "pid_after_state": 202,
      "control_broadcasts_before_witness": 0,
      "work_id": "00000000-0000-4000-8000-000000000001",
      "api": 37,
      "user_id": 0
    },
    "expected": {
      "scheduler_active": true,
      "same_fresh_pid": true,
      "own_job_workspec_binding": true,
      "control_broadcasts_before_witness": 0,
      "exclusive_worker_dispatch_proven": false,
      "host_proof_from_literal": false
    }
  },
  "negatives": [
    {
      "change": {
        "state_stdout": "pending ready\n"
      },
      "expected_code": "scheduler_witness_unobserved"
    },
    {
      "change": {
        "state_stdout": "waiting\n"
      },
      "expected_code": "scheduler_witness_unobserved"
    },
    {
      "change": {
        "state_exit": 1
      },
      "expected_code": "scheduler_witness_unobserved"
    },
    {
      "change": {
        "pid_after_state": 203
      },
      "expected_code": "scheduler_witness_unobserved"
    },
    {
      "change": {
        "service_class": "foreign.Service"
      },
      "expected_code": "scheduler_binding_invalid"
    },
    {
      "change": {
        "work_id": "00000000-0000-4000-8000-000000000002"
      },
      "expected_code": "scheduler_binding_invalid"
    },
    {
      "change": {
        "namespace": null,
        "api": 36
      },
      "expected_code": "scheduler_binding_invalid"
    },
    {
      "change": {
        "state_stdout": "inactive ready\n"
      },
      "expected_code": "scheduler_witness_unobserved"
    },
    {
      "change": {
        "control_broadcasts_before_witness": 1
      },
      "expected_code": "scheduler_binding_invalid"
    },
    {
      "change": {
        "pid_before_state": 101,
        "pid_after_state": 101
      },
      "expected_code": "scheduler_witness_unobserved"
    }
  ]
};
if(argv.length===1&&argv[0]==="--scheduler-witness-selftest") {
  const input=schedulerLiteralContract.positive.stimulus;
  const expected={work_id:input.work_id,api:input.api,user_id:input.user_id};
  const results=[];
  try {
    assert.deepEqual(schedulerWitness(input,expected),schedulerLiteralContract.positive.expected);
    results.push({case_id:schedulerLiteralContract.positive.case_id,result:"passed",host_proof:false});
    for(const [n,item] of schedulerLiteralContract.negatives.entries()) {
      let code=null;try{schedulerWitness({...input,...item.change},expected);}catch(e){code=e.message;}
      results.push({case_id:"scheduler_negative_"+n,result:code===item.expected_code?"passed":"failed",expected:item.expected_code,observed:code,host_proof:false});
      assert.equal(code,item.expected_code);
    }
    console.log(JSON.stringify({result:"passed",proof:"literal_helpers_only_no_native_actions",results}));
  } catch {console.log(JSON.stringify({result:"partial",code:"scheduler_literal_incomplete",results}));throw new Error("scheduler_literal_incomplete");}
} else if(argv.length===1 && argv[0]==="--supervisor-selftest") {
  const results=[];
  try {
  for(const f of [...supervisorFaultCases,...supervisorUtf8Cases]) {
    const r=await runBounded(f.stimulus,f.options);
    // Preserve first failure and cleanup facts before any expected-result assertion.
    results.push({case_id:f.id,result:"partial",observed:r});
    for(const marker of f.requiredReadiness??[])assert.ok(r.output.split(/\r?\n/).includes(marker),f.id+":fault_readiness_unverified");
    for(const[k,v]of Object.entries(f.expected))assert.equal(r[k],v,f.id+":"+k);
    results[results.length-1].result="passed";
  }
  console.log(JSON.stringify({schema:"healthmd.candidate_supervisor_faults",version:1,results}));
  } catch {
    console.log(JSON.stringify({schema:"healthmd.candidate_supervisor_faults",version:1,result:"partial",code:"supervisor_fault_incomplete",results}));
    throw new Error("supervisor_fault_incomplete");
  }
} else {
  assert.deepEqual(argv,["--channel","play","--release","--offline","--fresh-process","--target","required-local-device"]);
  // Read-only root-issued preflight binds already-prepared native products and exactly approved target.
  // No install/bundle/build here. ROOT must separately approve those bounded native actions.
  const clearancePath=process.env.HEALTHMD_COLD_WORKER_CLEARANCE;
  assert.ok(clearancePath!==undefined,"missing_root_execution_clearance");
  const clearance=JSON.parse(await readFile(clearancePath,"utf8"));
  assert.equal(clearance.task,"NATIVE-ANDROID-COLD-WORKER-PROBE");
  assert.equal(clearance.execution,"approved_prepared_runtime_only");
  assert.ok(typeof clearance.serial==="string"&&/^[A-Za-z0-9._-]{1,80}$/.test(clearance.serial));
  const app="com.healthmd.effecthost.androidcandidate.cold.play";
  const component=app+"/com.healthmd.effecthostcandidate.ColdProbeControlReceiver";
  const adb=resolve(process.env.ANDROID_HOME??"", "platform-tools/adb");
  assert.ok(adb.startsWith("/"));
  const out=resolve("dist/cold-worker/runtime");await mkdir(out,{recursive:true});
  assert.ok(Array.isArray(clearance.prepared_artifacts)&&clearance.prepared_artifacts.length>=2);
  for(const p of clearance.prepared_artifacts)assert.equal(hash(await readFile(resolve(p.path))),p.sha256,"prepared_artifact_drift");
  const fixture=await readFile("fixtures/cold-worker-v1.json");assert.equal(hash(fixture),"f2a67c17977e3eb615c581bccb73a817d417a57f272ede30a1d7ebb38db00bd2");
  const cases=JSON.parse(fixture).cases;
  const started=Date.now();const monotonicStarted=performance.now();let bytes=0;const commands=[];const schedulerAttempts=[];let controlBroadcasts=0;
  async function commandRecord(args,limit=120000) {
    assert.ok(Date.now()-started<900000,"overall_deadline");
    const r=await runBounded([adb,"-s",clearance.serial,...args],{deadlineMs:Math.min(limit,900000-(Date.now()-started)),cap:16777216-bytes});
    bytes+=r.observed_output_bytes;commands.push({argv:args,...r});assert.ok(bytes<=16777216,"combined_output_limit");
    return r;
  }
  async function command(args,limit=120000) {
    const r=await commandRecord(args,limit);assert.equal(r.result,"passed",r.reason??"command_failed");assert.equal(r.cleanup_ack,true);return r.output;
  }
  const boot=async()=>{const b=(await command(["shell","settings","get","global","boot_count"])).trim();assert.match(b,/^(0|[1-9][0-9]*)$/);return b;};
  const pid=async()=>{
    // pidof exits1 when absent, so wrap fixed shell command with a successful empty result.
    const p=(await command(["shell","sh","-c","pidof "+app+" || true"])).trim();
    assert.match(p,/^$|^[1-9][0-9]*$/,"multiple_or_invalid_processes");return p;
  };
  async function control(commandName,work,controller) {
    controlBroadcasts++;
    const response=await command(["shell","am","broadcast","--receiver-foreground","-n",component,"-a",app+".CONTROL","--es","command",commandName,"--es","work_id",work,"--es","controller_nonce",controller],5000);
    const match=response.match(/data="(\{[^\r\n]+\})"/);
    assert.ok(match,"control_response_missing");
    const value=JSON.parse(match[1]);
    assert.deepEqual(Object.keys(value),["schema","version","code","work_id","process_nonce","snapshot"]);
    assert.equal(value.schema,"healthmd.candidate_cold_worker_control");assert.equal(value.version,1);return value;
  }
  const ackKeys=["schema","version","run_nonce","process_nonce","work_id","invocation_id","case_id","sequence","generation","pid","phase","code","ack","acquired","released","active","unresolved_inspections","logical_total_acquired","logical_total_released"];
  function validateAck(a) {
    assert.ok(a!==null&&typeof a==="object");assert.deepEqual(Object.keys(a),ackKeys);
    assert.equal(a.schema,"healthmd.candidate_cold_worker_ack");assert.equal(a.version,1);
    for(const k of ["run_nonce","process_nonce","work_id","invocation_id"])assert.match(a[k],/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    assert.ok(Number.isInteger(a.sequence)&&a.sequence>=0&&a.sequence<=4);assert.equal(a.case_id,cases[a.sequence].case_id);
    assert.ok(Number.isInteger(a.generation)&&a.generation>=1&&a.generation<=5);
    assert.ok(Number.isInteger(a.pid)&&a.pid>0&&a.pid<=2147483647);
    for(const k of ["ack","acquired","released","active","unresolved_inspections","logical_total_acquired","logical_total_released"])assert.ok(a[k]===0||a[k]===1);
    assert.ok(["inspection_started","release_pending","completed","incomplete"].includes(a.phase));
    assert.ok(["ready","schema_invalid","expired","duplicate_request","stopped","engine_failure","cleanup_unverified"].includes(a.code));
    assert.equal(a.active,a.acquired-a.released);assert.ok(a.logical_total_released<=a.logical_total_acquired);
    if(a.phase==="completed"){assert.equal(a.ack,1);assert.equal(a.active,0);assert.equal(a.unresolved_inspections,0);}else assert.equal(a.ack,0);
  }
  const observations=[];let preservedRun=null;
  try {
    for(const expected of cases) {
      const before=await boot();
      // No running private candidate before setup; no force-stop/kill workaround permitted.
      assert.equal(await pid(),"","private_candidate_not_cold_before_setup");
      const setupText=await command(["shell","am","instrument","-w","-r","-e","class","com.healthmd.effecthostcandidate.ColdProbeWorkerRuntimeTest#enqueueOnly","-e","case_sequence",String(expected.sequence),...(preservedRun===null?[]:["-e","preserved_run_nonce",preservedRun]),app+".test/androidx.test.runner.AndroidJUnitRunner"]);
      const match=setupText.match(/INSTRUMENTATION_STATUS: cold_setup=(\{[^\r\n]+\})/);assert.ok(match,"setup_missing");
      const setup=JSON.parse(match[1]);
      assert.deepEqual(Object.keys(setup),["schema","version","case_id","sequence","run_nonce","controller_nonce","setup_pid","boot_count","submitted_elapsed_ms","work_ids","api","user_id","job_descriptors"]);
      assert.equal(setup.schema,"healthmd.candidate_cold_worker_setup");assert.equal(setup.version,1);
      assert.equal(setup.case_id,expected.case_id);assert.equal(setup.sequence,expected.sequence);
      assert.ok(boundedInt(setup.api,34)&&boundedInt(setup.user_id)&&boundedInt(setup.setup_pid,1),"scheduler_binding_invalid");
      assert.equal(setup.api,clearance.api,"scheduler_binding_invalid");assert.equal(setup.user_id,clearance.user_id,"scheduler_binding_invalid");
      for(const key of ["run_nonce","controller_nonce"])assert.ok(typeof setup[key]==="string"&&uuid.test(setup[key]),"scheduler_binding_invalid");
      assert.ok(Array.isArray(setup.work_ids)&&Array.isArray(setup.job_descriptors),"scheduler_binding_invalid");
      assert.equal(setup.job_descriptors.length,setup.work_ids.length,"scheduler_binding_invalid");
      assert.equal(new Set(setup.work_ids).size,setup.work_ids.length,"scheduler_binding_invalid");
      const jobs=setup.job_descriptors.map((job,n)=>schedulerBinding(job,{work_id:setup.work_ids[n],api:setup.api,user_id:setup.user_id}));
      assert.equal(new Set(jobs.map(x=>x.job_id)).size,jobs.length,"scheduler_binding_invalid");
      controlBroadcasts=0;
      assert.equal(String(setup.boot_count),before);assert.ok(setup.work_ids.length===(expected.sequence===4?2:1));
      assert.equal(await pid(),"","setup_process_still_running_no_cold_witness");
      const deadline=Date.now()+60000;let activePid="";
      while(Date.now()<deadline) {activePid=await pid();if(activePid!=="")break;await new Promise(r=>setTimeout(r,50));}
      assert.ok(activePid!==""&&activePid!==String(setup.setup_pid),"fresh_os_process_missing");
      let schedulerObservation={active_observed:false,limit:"fast_case_active_unobserved_no_exclusive_dispatch_claim"};
      if(expected.sequence===3) {
        const job=jobs[0];let witness=null;
        while(Date.now()<deadline) {
          const beforePid=await pid();
          const state=await commandRecord(["shell","cmd","jobscheduler","get-job-state","-u",String(setup.user_id),"-n",schedulerNamespace,schedulerPackage,String(job.job_id)],5000);
          assert.equal(state.cleanup_ack,true,"scheduler_witness_unobserved");
          assert.equal(state.reason,null,"scheduler_witness_unobserved");
          const afterPid=await pid();
          const input={job_id:job.job_id,generation:job.generation,service_package:job.service_package,
            service_class:job.service_class,namespace:job.namespace,setup_pid:setup.setup_pid,observed_absent_after_setup:true,
            pid_before_state:beforePid===""?null:Number(beforePid),state_exit:state.result==="passed"&&state.cleanup_ack?state.code:null,
            state_stdout:state.output,pid_after_state:afterPid===""?null:Number(afterPid),control_broadcasts_before_witness:controlBroadcasts,
            work_id:job.work_id,api:setup.api,user_id:setup.user_id};
          const attempt={case_id:expected.case_id,host_monotonic_elapsed_ms:performance.now()-monotonicStarted,input,result:"partial",code:"scheduler_witness_unobserved"};schedulerAttempts.push(attempt);
          try {
            const candidate=schedulerWitness(input,{work_id:setup.work_ids[0],api:setup.api,user_id:setup.user_id});
            assert.equal(String(input.pid_before_state),activePid,"scheduler_witness_unobserved");
            witness=candidate;
            attempt.result="passed";attempt.code=null;break;
          } catch(e) {if(e.message==="scheduler_binding_invalid")throw new Error("scheduler_binding_invalid");}
          await new Promise(r=>setTimeout(r,50));
        }
        assert.ok(witness!==null,"scheduler_witness_unobserved");
        schedulerObservation={active_observed:true,witness,limit:"bounded_PID_OS_active_correlation_not_exclusive_Greedy_vs_SystemJobService_dispatch"};
      }
      let last=null;let releasePending=false;let nativeInvocation=null;let nonce=null;let cancelSent=false;
      const ackDeadline=Date.now()+Math.min(30000,900000-(Date.now()-started));
      while(Date.now()<ackDeadline) {
        assert.equal(await pid(),activePid,"worker_process_lost");
        const r=await control("read_ack",setup.work_ids[0],setup.controller_nonce);
        if(r.code==="ack_snapshot") {
          const a=r.snapshot;validateAck(a);assert.equal(a.work_id,setup.work_ids[0]);assert.equal(a.run_nonce,setup.run_nonce);
          assert.equal(a.case_id,expected.case_id);assert.equal(a.sequence,expected.sequence);assert.equal(String(a.pid),activePid);
          if(nativeInvocation===null){nativeInvocation=a.invocation_id;nonce=a.process_nonce;}
          assert.equal(a.invocation_id,nativeInvocation);assert.equal(a.process_nonce,nonce);
          if(a.phase==="release_pending"){releasePending=true;assert.equal(a.ack,0);}
          if(expected.sequence===3&&a.phase==="inspection_started"&&!cancelSent){
            const cancel=await control("cancel",a.work_id,setup.controller_nonce);assert.equal(cancel.code,"cancel_dispatched");assert.equal(cancel.process_nonce,nonce);cancelSent=true;
          }
          if(a.phase==="completed"){last=a;break;}
          assert.notEqual(a.phase,"incomplete","cleanup_unverified");
        } else assert.equal(r.code,"control_unavailable");
        await new Promise(r=>setTimeout(r,20));
      }
      assert.ok(last!==null,"native_ack_timeout");
      const want=expected.sequence===4?expected.expected.first:expected.expected;
      assert.equal(last.code,want.private_code);assert.equal(last.ack,1);
      for(const k of ["acquired","released","active","unresolved_inspections"])assert.equal(last[k],want[k]);
      if(expected.sequence===3){assert.ok(cancelSent&&releasePending);}
      if(expected.sequence===4){
        const second=await control("read_ack",setup.work_ids[1],setup.controller_nonce);
        assert.equal(second.code,"ack_snapshot");validateAck(second.snapshot);assert.equal(second.snapshot.code,"duplicate_request");
        assert.equal(second.snapshot.acquired,0);assert.equal(second.snapshot.released,0);assert.equal(second.snapshot.ack,1);
        assert.equal(second.snapshot.logical_total_acquired,1);assert.equal(second.snapshot.logical_total_released,1);
        assert.notEqual(second.snapshot.invocation_id,nativeInvocation);
      }
      assert.equal(await boot(),before,"boot_changed_test_incomplete");
      observations.push({case_id:expected.case_id,result:"passed",setup,ack:last,release_pending:releasePending,scheduler:schedulerObservation});
      await writeFile(resolve(out,"case-"+expected.sequence+".json"),JSON.stringify(observations[observations.length-1])+"\n");
      preservedRun=setup.run_nonce;
      // Optional private cached-process preparation is DISABLED unless ROOT grants this exact route.
      // Never treat am kill as native cleanup acknowledgment or as the next OS Worker execution.
      if(clearance.background_preparation === "approved_exact_own_cold_play_background_am_kill") {
        const all=[];
        for(const work of setup.work_ids) {
          const r=await control("read_ack",work,setup.controller_nonce);assert.equal(r.code,"ack_snapshot");
          validateAck(r.snapshot);assert.equal(r.snapshot.phase,"completed");assert.equal(r.snapshot.ack,1);
          assert.equal(r.snapshot.process_nonce,nonce);assert.equal(String(r.snapshot.pid),activePid);
          assert.equal(r.snapshot.acquired,r.snapshot.released);assert.equal(r.snapshot.active,0);assert.equal(r.snapshot.unresolved_inspections,0);
          all.push(r.snapshot);
        }
        assert.equal(await pid(),activePid);
        const packages=await command(["shell","cmd","package","list","packages","-U",app]);
        const row=packages.split(/\r?\n/).find(x=>x.startsWith("package:"+app+" uid:"));assert.ok(row);
        const uidMatch=row.match(/^package:com\.healthmd\.effecthost\.androidcandidate\.cold\.play uid:([1-9][0-9]*)$/);assert.ok(uidMatch);
        const uid=uidMatch[1];assert.equal(uid,String(clearance.private_candidate_uid),"own_uid_drift");
        const process=await command(["shell","ps","-p",activePid,"-o","PID,UID,NAME"]);
        assert.ok(process.split(/\r?\n/).some(x=>x.trim().split(/\s+/).join(" ")===activePid+" "+uid+" "+app),"own_process_attribution_missing");
        // Exact actual command spelling/format and cached-state behavior require later target preflight.
        // Unrecognized/service/receiver/top/foreground output never enables preparation.
        const state=await command(["shell","am","get-uid-state",uid]);
        assert.ok(new RegExp("^"+uid+": (CACHED_EMPTY|CACHED_ACTIVITY|CACHED_RECENT|CEM|CAC|CRE)\\s*$").test(state),"not_verified_cached_background");
        assert.equal(await pid(),activePid);
        await command(["shell","am","kill",app],5000); // exact isolated private package only; never force-stop
        const until=Date.now()+5000;
        while(Date.now()<until && await pid()!=="")await new Promise(r=>setTimeout(r,50));
        assert.equal(await pid(),"","own_background_preparation_unacknowledged");
        observations[observations.length-1].preparation={code:"own_cached_process_absent",uid,prior_pid:activePid,all_ticket_acks:all};
      }
    }
    await writeFile(resolve(out,"report.json"),JSON.stringify({result:"passed",observations,commands,schedulerAttempts},null,2)+"\n");
  } catch(e) {
    await writeFile(resolve(out,"report.json"),JSON.stringify({result:"partial",code:"probe_incomplete",observations,commands,schedulerAttempts},null,2)+"\n");
    throw new Error("probe_incomplete");
  }
}
JS
