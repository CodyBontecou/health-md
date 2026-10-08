import assert from "node:assert/strict";
import {test} from "node:test";
import {readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import * as Effect from "effect/Effect";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Scope from "effect/Scope";
import * as Exit from "effect/Exit";
import {createPersonalRecordCodec} from "../src/contracts/personal-slice.js";
import {createSessionProjector,sessionFailure,type SessionFailure,type SessionCode,type TrustedSessionBinding,type ProjectionPhase,type EligibleOriginalSource,type OriginalLifetime,type OriginalIssuer,type OwnedOriginal,type OwnedSessionProjection,type OriginalView,type SessionSourceDescriptor,type SourceDescriptorCapability,type SessionProjector} from "../src/usage-desktop/session-projection.js";
import {usageDesktopSessionProjectionFixture} from "./usage-desktop-session-projection-vectors.js";
interface Action {readonly at:string;readonly op:string;readonly ordinal:number}
interface Stimulus {readonly request:unknown;readonly original_fields_json:string;readonly trusted_clock_profile:string;readonly trusted_app_class:string;readonly actions:readonly Action[];readonly trusted_descriptor:unknown}
interface Counts {source_allocations:number;source_release_attempts:number;source_release_ACKs:number;source_reads:number;original_materializations:number;codec_decodes:number;codec_encodes:number;title_observations:number;publication_returns:number;property_traps:number;descriptor_calls:number}
function counters():Counts{return {source_allocations:0,source_release_attempts:0,source_release_ACKs:0,source_reads:0,original_materializations:0,codec_decodes:0,codec_encodes:0,title_observations:0,publication_returns:0,property_traps:0,descriptor_calls:0};}
function errorCode<A>(exit:Exit.Exit<A,SessionFailure>):SessionCode|null{if(Exit.isSuccess(exit))return null;const fail=exit.cause.reasons.find(r=>r._tag==="Fail");return fail?._tag==="Fail"?fail.error.code:null;}
function canonical(input:unknown):string{if(input===null||typeof input!=="object")return JSON.stringify(input);if(Array.isArray(input))return '['+input.map(canonical).join(',')+']';return '{'+Object.entries(input).sort(([a],[b])=>a<b?-1:a>b?1:0).map(([k,v])=>JSON.stringify(k)+':'+canonical(v)).join(',')+'}';}
function object(input:unknown):Record<string,unknown>{assert.ok(input!==null&&typeof input==="object"&&!Array.isArray(input));return Object.fromEntries(Object.entries(input));}
function string(input:unknown):string{assert.equal(typeof input,"string");if(typeof input!=="string")throw new Error("invalid inert fixture");return input;}
function appClass(input:unknown):"browser"|"non_browser"|"unknown"{assert.ok(input==="browser"||input==="non_browser"||input==="unknown");if(input!=="browser"&&input!=="non_browser"&&input!=="unknown")throw new Error("invalid inert fixture");return input;}
/** A checked host-side construction; missing-ref union is intentionally rejected by candidate. */
function fixtureDescriptor(input:unknown):SessionSourceDescriptor {
 const o=object(input),r=object(o.source_evidence_ref),fields:SessionSourceDescriptor["admitted_fields"]=["record","original_end","clock_basis","native_algorithm","local_start_text","source_utc_offset"];
 const source_evidence_ref:SessionSourceDescriptor["source_evidence_ref"]=r.state==="known"?{state:"known",value:string(r.value)}:{state:"unknown",reason:"not_reported"};
 const forbidden:SessionSourceDescriptor["forbidden_detail_present"]=Array.isArray(o.forbidden_detail_present)?o.forbidden_detail_present.filter((v):v is "browser_title"|"browser_url"|"browser_history"|"input_telemetry"|"nonbrowser_title"|"archive_auxiliary"=>v==="browser_title"||v==="browser_url"||v==="browser_history"||v==="input_telemetry"||v==="nonbrowser_title"||v==="archive_auxiliary"):[];
 return {dataset_id:string(o.dataset_id),source_id:string(o.source_id),source_revision:string(o.source_revision),source_evidence_ref,app_identity:string(o.app_identity),authoritative_app_class:appClass(o.authoritative_app_class),declared_projection_app_class:appClass(o.declared_projection_app_class),admitted_fields:fields,forbidden_detail_present:forbidden};
}
interface PreservationInput {readonly delivered_projection_json:string;readonly captured_source_reference:unknown;readonly retained_projection_at_reference:string;readonly observed_owned_canonical_record:unknown;readonly observed_status_reference:unknown}
/** Synthetic host trace only: no product archive port and no success-flag shortcut. */
function observePreservation(input:PreservationInput){
 const retained=new Map<string,string>();const captured=object(input.captured_source_reference);retained.set(string(captured.value),input.retained_projection_at_reference);
 const actual=object(input.observed_status_reference);let lookups=0,comparisons=0;const lookup=(key:string)=>{lookups++;return retained.get(key);};const lookedUp=lookup(string(actual.value));
 const delivered=object(JSON.parse(input.delivered_projection_json));
 const hasRecord=input.observed_owned_canonical_record!==null;
 let recordMatches=true;if(hasRecord){comparisons++;recordMatches=canonical(input.observed_owned_canonical_record)===canonical(delivered.record);}
 return {original_bits_preserved:canonical(captured)===canonical(actual)&&lookedUp===input.delivered_projection_json&&recordMatches,archive_read_calls:0,product_raw_evidence_returns:0,source_reference_lookup_count:lookups,canonical_record_comparisons:comparisons};
}

function run(stimulus:Stimulus):Effect.Effect<Readonly<Record<string,unknown>>,SessionFailure>{
 return Effect.scoped(Effect.gen(function*():Effect.gen.Return<Readonly<Record<string,unknown>>,SessionFailure,Scope.Scope>{
  const scope=yield* Scope.make();yield* Effect.addFinalizer(()=>Scope.close(scope,Exit.succeed(undefined)));
  const c=counters(),signal=yield* Deferred.make<void>();let denied=false,originalReadLive=false,admittedMaterializations=0,auxObserved=0,normalRawMaterializations=0,authorityCalls=0;
  const retainedProjection=stimulus.original_fields_json,capturedReference=fixtureDescriptor(stimulus.trusted_descriptor).source_evidence_ref;
  let deliveredProjection:string|null=null;
  const saved:{read:Effect.Effect<string|null,SessionFailure>|null}={read:null};const reached=new Set<number>();const phases=new Map<string,number>();
  const action=(at:string)=>{const ordinal=(phases.get(at)??0)+1;phases.set(at,ordinal);const i=stimulus.actions.findIndex(a=>a.at===at&&a.ordinal===ordinal);if(i<0)return undefined;reached.add(i);return stimulus.actions[i]!.op;};
  const suspend:Effect.Effect<never>=Deferred.succeed(signal,undefined).pipe(Effect.andThen(Effect.never));
  const proxy=()=>new Proxy({},{get(){c.property_traps++;throw "SYNTHETIC_SECRET";},ownKeys(){c.property_traps++;throw "SYNTHETIC_SECRET";},getPrototypeOf(){c.property_traps++;throw "SYNTHETIC_SECRET";}});
  const binding:TrustedSessionBinding={dataset_id:"synthetic-dataset-a",source_id:"synthetic-source-a",source_revision:"synthetic-source-contract1",purpose:"synthetic_local_collection",clock_profile:stimulus.trusted_clock_profile==="native-evidence-v1"?"native-evidence-v1":"synthetic-v1"};
  const current={check:(_binding:TrustedSessionBinding,phase:ProjectionPhase):Effect.Effect<void,SessionFailure>=>Effect.gen(function*(){
   authorityCalls++;const op=action('current.'+phase);if(denied)return yield* Effect.fail(sessionFailure("scope_not_authorized"));
   if(op==="revoke_destination_return_source_permitted"){denied=true;return;}
   if(op==="deny"||op==="revoke_destination"||op==="accept_delete"||op==="restore_backup_and_regrant_after_delete"||op==="revoke"){denied=true;return yield* Effect.fail(sessionFailure("scope_not_authorized"));}
  })};
  const descriptor:SourceDescriptorCapability={describe:()=>Effect.sync(()=>{c.descriptor_calls++;action("source.metadata");return fixtureDescriptor(stimulus.trusted_descriptor);})};
  const codecActual=createPersonalRecordCodec({authorize:()=>({permitted:!denied,authority_binding:"synthetic-authority",frontier_binding:"synthetic-current-frontier",app_class:appClass(stimulus.trusted_app_class),title_permitted:false})});
  const codec={decode:(input:unknown)=>{c.codec_decodes++;return codecActual.decode(input);},encode:(input:unknown)=>{c.codec_encodes++;return codecActual.encode(input);}};
  const owned=new WeakSet<object>();
  const originalView:OriginalView={read:(ticket:unknown)=>{
   const lazy:Effect.Effect<string|null,SessionFailure>=Effect.suspend(()=>{
    if(!originalReadLive)return Effect.succeed(null);c.source_reads++;const op=action("source.read");const actual=op==="foreign_ticket_Proxy"?proxy():ticket;
    if(actual===null||(typeof actual!=="object"&&typeof actual!=="function")||!owned.has(actual))return Effect.succeed(null);
    if(op==="provider_defect")return Effect.die("SYNTHETIC_SECRET");
    if(op==="revoke_then_return"){denied=true;return Effect.succeed(null);}
    c.original_materializations++;const raw:unknown=JSON.parse(stimulus.original_fields_json),fields=object(raw);const auxiliaries=["categories","comment"].filter(k=>Object.hasOwn(fields,k));auxObserved+=auxiliaries.length;
    if(auxiliaries.length){normalRawMaterializations++;}else {admittedMaterializations++;}
    deliveredProjection=stimulus.original_fields_json;return Effect.succeed(deliveredProjection);
   });saved.read=lazy;return lazy;
  }};
  const source:EligibleOriginalSource={withOriginal:<A>(life:OriginalLifetime,issuer:OriginalIssuer,use:(ticket:OwnedOriginal,view:OriginalView)=>Effect.Effect<A,SessionFailure>):Effect.Effect<A,SessionFailure>=>
   Effect.uninterruptibleMask(restore=>Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,SessionFailure,Scope.Scope>{
    let phase:Fiber.Fiber<A,SessionFailure>|null=null,stop=false;const cleanupErrors=new WeakSet<object>();
    const watcher=yield* Effect.forkChild(restore(life.closed.pipe(Effect.andThen(Effect.suspend(()=>{stop=true;const running=phase;return running===null?Effect.void:Fiber.interrupt(running);})))),{startImmediately:true});
    const body=Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,SessionFailure,Scope.Scope>{
     if(action("source.prepare")==="suspend_then_external_interrupt")return yield* suspend;
     if(!life.isLive()||stop)return yield* Effect.fail(sessionFailure("owned_handoff_closed"));
     const ticket=yield* Effect.acquireRelease(Effect.sync(()=>{const t=issuer.commit();assert.ok(t);owned.add(t);c.source_allocations++;return t;}),()=>Effect.sync(()=>{c.source_release_attempts++;if(action("source.cleanup")==="fail_fixed"){const e=sessionFailure("cleanup_failed");cleanupErrors.add(e);throw e;}c.source_release_ACKs++;}));
     if(action("source.registered_wait")==="suspend_then_external_interrupt")return yield* suspend;
     if(!life.isLive()||stop)return yield* Effect.fail(sessionFailure("owned_handoff_closed"));
     originalReadLive=true;return yield* use(ticket,originalView).pipe(Effect.ensuring(Effect.sync(()=>{originalReadLive=false;})));
    }));
    const started=yield* Effect.forkChild(restore(body),{startImmediately:true});phase=started;if(stop)yield* Fiber.interrupt(started);
    const wait=yield* Effect.exit(restore(Fiber.await(started)));yield* Fiber.interrupt(watcher);yield* Fiber.interrupt(started);const ended=yield* Fiber.await(started);yield* Fiber.await(watcher);
    if(Exit.isFailure(ended)&&ended.cause.reasons.some(r=>r._tag==="Fail"?r.error.code==="cleanup_failed":r._tag==="Die"&&r.defect!==null&&(typeof r.defect==="object"||typeof r.defect==="function")&&cleanupErrors.has(r.defect)))return yield* Effect.fail(sessionFailure("cleanup_failed"));
    if(Exit.isFailure(wait))return yield* Effect.failCause(wait.cause);if(!life.isLive())return yield* Effect.fail(sessionFailure("owned_handoff_closed"));if(Exit.isFailure(ended))return yield* Effect.failCause(ended.cause);return ended.value;
   })))};
  const factory:Effect.Effect<SessionProjector,SessionFailure>=Scope.provide(scope)(createSessionProjector({binding,current,source,descriptor,codec}));
  const projector=yield* factory;let request=stimulus.request;const requestOp=action("request");if(requestOp==="throwing_Proxy")request=proxy();
  if(action("controller.before_project")==="close_original")yield* Scope.close(scope,Exit.succeed(undefined));
  const main=yield* Effect.forkChild(projector.project(request),{startImmediately:true});
  const controller=yield* Effect.forkChild(Deferred.await(signal).pipe(Effect.andThen(Fiber.interrupt(main))),{startImmediately:true});
  const exit=yield* Fiber.await(main);yield* Fiber.interrupt(controller);
  let metadata:unknown=null,statusWrapper:unknown=null,recordJson:string|null=null,probe:unknown=undefined,preserved=false;
  if(Exit.isSuccess(exit)){c.publication_returns++;const entry=yield* projector.view.read(exit.value);assert.ok(entry);metadata=entry.metadata;statusWrapper=entry.status;recordJson=entry.record===null?null:canonical(entry.record);assert.ok(deliveredProjection!==null);preserved=observePreservation({delivered_projection_json:deliveredProjection,captured_source_reference:capturedReference,retained_projection_at_reference:retainedProjection,observed_owned_canonical_record:entry.record,observed_status_reference:entry.status.source_evidence_ref}).original_bits_preserved;
   const op=action("after_project");
   if(op==="foreign_projection_Proxy"){const before=authorityCalls;const observed=yield* projector.view.read(proxy());probe={read_result:observed,extra_current_calls:authorityCalls-before,extra_property_traps:c.property_traps};}
   if(op==="close_then_read"){yield* Scope.close(scope,Exit.succeed(undefined));const before=authorityCalls;const observed=yield* projector.view.read(exit.value);probe={read_result:observed,extra_current_calls:authorityCalls-before};}
   if(op==="read_success_revoke_reexecute"){const lazy=projector.view.read(exit.value);const first=yield* lazy;assert.ok(first);denied=true;const second=yield* Effect.exit(lazy);probe={first_read_record_json:first.record===null?null:canonical(first.record),second_read_failure:errorCode(second),second_text_materializations:Exit.isSuccess(second)&&second.value!==null?1:0};}
   if(op==="saved_original_read_after_callback"){const before=authorityCalls;assert.ok(saved.read);const observed=yield* saved.read;probe={read_result:observed,extra_current_calls:authorityCalls-before};}
  }
  assert.equal(reached.size,stimulus.actions.length,"all actual declared phases must be reached");
  const code=errorCode(exit),status=typeof metadata==="object"&&metadata!==null&&"status"in metadata?metadata.status:null;
  const result:Record<string,unknown>={kind:Exit.isSuccess(exit)?"owned_projection":code===null?"interruption":"fixed_failure",failure:code,metadata,record_json:recordJson,original_evidence_json:null,counts:c,native_date_algorithm_qualified:false,native_capture_qualified:false,automatic_clock_inconsistent:status==="clock_inconsistent",original_bits_preserved:preserved,return_after_cleanup_ACK:Exit.isSuccess(exit)&&c.source_release_ACKs===1,status_wrapper:statusWrapper,archive_read_calls:0,normal_raw_evidence_materializations:normalRawMaterializations,admitted_projection_materializations:admittedMaterializations,auxiliary_value_observations:auxObserved,auxiliary_value_materializations:auxObserved};
  if(probe!==undefined)result.probe=probe;return result;
 }));
}
for(const scene of usageDesktopSessionProjectionFixture.cases){test(`source-backed desktop session: ${scene.case_id}`,async()=>{
 const observed=await Effect.runPromise(run(scene.stimulus));for(const [key,expected]of Object.entries(scene.expected))assert.deepEqual(observed[key],expected,`${scene.case_id}: ${key}`);
});}
test("immutable independently accepted desktop45 corpus raw pin",async()=>{const raw=await readFile(new URL("../../tests/usage-desktop-session-projection-vectors.ts",import.meta.url));assert.equal(createHash("sha256").update(raw).digest("hex"),"cfdb305851a67d2963f0223b9f54e19a6fa0e2ded41c03813fb306d9a9740b12");assert.equal(usageDesktopSessionProjectionFixture.cases.length,45);});

interface ConcurrentInput {readonly calls:readonly {readonly label:string;readonly stimulus:Stimulus}[];readonly same_factory:boolean;readonly controller_schedule:readonly string[]}
function runConcurrent(input:ConcurrentInput):Effect.Effect<Readonly<Record<string,unknown>>,SessionFailure>{
 return Effect.scoped(Effect.gen(function*():Effect.gen.Return<Readonly<Record<string,unknown>>,SessionFailure,Scope.Scope>{
  assert.equal(input.same_factory,true);const scope=yield* Scope.make();yield* Effect.addFinalizer(()=>Scope.close(scope,Exit.succeed(undefined)));
  const entered=yield* Deferred.make<void>(),resume=yield* Deferred.make<void>(),cleanupEntered=yield* Deferred.make<void>(),cleanupResume=yield* Deferred.make<void>();
  const states=new Map<string,{input:Stimulus;c:Counts;trusted:number;delivered:string|null;retained:string;reference:unknown;actions:Set<number>}>(input.calls.map(call=>[call.label,{input:call.stimulus,c:counters(),trusted:0,delivered:null,retained:call.stimulus.original_fields_json,reference:fixtureDescriptor(call.stimulus.trusted_descriptor).source_evidence_ref,actions:new Set<number>()}]));
  // Each source invocation captures its own input and counter state before suspension.
  let activeLabel=string(input.calls[0]?.label);let activeCallbacks=0,maxCallbacks=0,activeLeases=0,maxLeases=0,sourceEntries=0,externalInterrupt=false;
  const state=()=>{const result=states.get(activeLabel);assert.ok(result);return result;};
  const action=(st:ReturnType<typeof state>,at:string)=>{const i=st.input.actions.findIndex(a=>a.at===at&&a.ordinal===1);if(i<0)return undefined;st.actions.add(i);return st.input.actions[i]!.op;};
  const binding:TrustedSessionBinding={dataset_id:"synthetic-dataset-a",source_id:"synthetic-source-a",source_revision:"synthetic-source-contract1",purpose:"synthetic_local_collection",clock_profile:"synthetic-v1"};
  const current={check:():Effect.Effect<void,SessionFailure>=>Effect.sync(()=>{state().trusted++;})};
  const descriptor:SourceDescriptorCapability={describe:()=>Effect.sync(()=>{const st=state();st.trusted++;st.c.descriptor_calls++;return fixtureDescriptor(st.input.trusted_descriptor);})};
  const actualCodec=createPersonalRecordCodec({authorize:()=>({permitted:true,authority_binding:"synthetic-authority",frontier_binding:"synthetic-current-frontier",app_class:"non_browser",title_permitted:false})});
  const codec={decode:(raw:unknown)=>{state().c.codec_decodes++;return actualCodec.decode(raw);},encode:(record:unknown)=>{state().c.codec_encodes++;return actualCodec.encode(record);}};
  const waitOn=(ready:Deferred.Deferred<void>,release:Deferred.Deferred<void>)=>Effect.scoped(Effect.gen(function*(){
   const waiter=yield* Effect.forkChild(Deferred.await(release),{startImmediately:true});assert.equal(waiter.pollUnsafe(),undefined);
   // This child has only the actual Deferred await; readiness follows its registered suspension.
   yield* Deferred.succeed(ready,undefined);yield* Fiber.join(waiter);
  }));
  const owned=new WeakSet<object>();
  const source:EligibleOriginalSource={withOriginal:<A>(life:OriginalLifetime,issuer:OriginalIssuer,use:(ticket:OwnedOriginal,view:OriginalView)=>Effect.Effect<A,SessionFailure>):Effect.Effect<A,SessionFailure>=>Effect.suspend(()=>{
   const st=state();st.trusted++;sourceEntries++;activeCallbacks++;maxCallbacks=Math.max(maxCallbacks,activeCallbacks);
   return Effect.uninterruptibleMask(restore=>Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,SessionFailure,Scope.Scope>{
    let running:Fiber.Fiber<A,SessionFailure>|null=null,stop=false,callbackLive=false;const cleanupErrors=new WeakSet<object>();
    const watcher=yield* Effect.forkChild(restore(life.closed.pipe(Effect.andThen(Effect.suspend(()=>{stop=true;return running===null?Effect.void:Fiber.interrupt(running);})))),{startImmediately:true});
    const body=Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,SessionFailure,Scope.Scope>{
     const prepare=action(st,"source.prepare");
     if(prepare==="unknown_Fail"){const unknownFailure:SessionFailure={code:"cleanup_failed"};return yield* Effect.fail(unknownFailure);}
     if(prepare==="unknown_Die")return yield* Effect.die("SYNTHETIC_SECRET_UNREGISTERED_SOURCE");
     if(prepare==="hold_on_owned_latch")yield* waitOn(entered,resume);
     if(stop||!life.isLive())return yield* Effect.fail(sessionFailure("owned_handoff_closed"));
     const ticket=yield* Effect.acquireRelease(Effect.sync(()=>{const t=issuer.commit();assert.ok(t);owned.add(t);st.c.source_allocations++;activeLeases++;maxLeases=Math.max(maxLeases,activeLeases);return t;}),()=>Effect.gen(function*(){
      st.c.source_release_attempts++;const op=action(st,"source.cleanup");
      if(op==="hold_ACK_on_owned_latch")yield* waitOn(cleanupEntered,cleanupResume);
      activeLeases--;if(op==="fail_fixed_after_actual_release_attempt"){const fail=sessionFailure("cleanup_failed");cleanupErrors.add(fail);return yield* Effect.die(fail);}st.c.source_release_ACKs++;
     }));
     const wait=action(st,"source.registered_wait");
     if(wait==="hold_on_owned_latch")yield* waitOn(entered,resume);
     if(wait==="hold_until_external_interrupt")yield* waitOn(entered,resume);
     if(stop||!life.isLive())return yield* Effect.fail(sessionFailure("owned_handoff_closed"));
     const view:OriginalView={read:(t:unknown)=>Effect.suspend(()=>{
      if(!callbackLive)return Effect.succeed(null);st.c.source_reads++;
      if(t===null||(typeof t!=="object"&&typeof t!=="function")||!owned.has(t))return Effect.succeed(null);
      st.c.original_materializations++;st.delivered=st.input.original_fields_json;return Effect.succeed(st.delivered);
     })};callbackLive=true;return yield* use(ticket,view).pipe(Effect.ensuring(Effect.sync(()=>{callbackLive=false;})));
    }));
    const child=yield* Effect.forkChild(restore(body),{startImmediately:true});running=child;if(stop)yield* Fiber.interrupt(child);
    const waited=yield* Effect.exit(restore(Fiber.await(child)));yield* Fiber.interrupt(watcher);yield* Fiber.interrupt(child);const ended=yield* Fiber.await(child);yield* Fiber.await(watcher);
    if(Exit.isFailure(ended)&&ended.cause.reasons.some(reason=>(reason._tag==="Fail"&&cleanupErrors.has(reason.error))||(reason._tag==="Die"&&reason.defect!==null&&typeof reason.defect==="object"&&cleanupErrors.has(reason.defect))))return yield* Effect.fail(sessionFailure("cleanup_failed"));
    if(Exit.isFailure(waited))return yield* Effect.failCause(waited.cause);if(!life.isLive())return yield* Effect.fail(sessionFailure("owned_handoff_closed"));if(Exit.isFailure(ended))return yield* Effect.failCause(ended.cause);return ended.value;
   }))).pipe(Effect.ensuring(Effect.sync(()=>{activeCallbacks--;})));
  })};
  const projector=yield* Scope.provide(scope)(createSessionProjector({binding,current,source,descriptor,codec}));
  const results=new Map<string,Readonly<Record<string,unknown>>>();let secret=false;
  const observe=(label:string,exit:Exit.Exit<OwnedSessionProjection,SessionFailure>)=>Effect.gen(function*(){
   const st=states.get(label);assert.ok(st);activeLabel=label;let metadata:unknown=null,status:unknown=null,recordJson:string|null=null,preserved=false;
   if(Exit.isSuccess(exit)){st.c.publication_returns++;const entry=yield* projector.view.read(exit.value);assert.ok(entry);metadata=entry.metadata;status=entry.status;recordJson=entry.record===null?null:canonical(entry.record);assert.ok(st.delivered!==null);preserved=observePreservation({delivered_projection_json:st.delivered,captured_source_reference:st.reference,retained_projection_at_reference:st.retained,observed_owned_canonical_record:entry.record,observed_status_reference:entry.status.source_evidence_ref}).original_bits_preserved;}
   if(Exit.isFailure(exit))secret ||= JSON.stringify(exit.cause).includes("SYNTHETIC_SECRET");
   const code=errorCode(exit);results.set(label,{kind:Exit.isSuccess(exit)?"owned_projection":code===null?"interruption":"fixed_failure",failure:code,metadata,record_json:recordJson,original_evidence_json:null,counts:st.c,native_date_algorithm_qualified:false,native_capture_qualified:false,automatic_clock_inconsistent:false,original_bits_preserved:preserved,return_after_cleanup_ACK:Exit.isSuccess(exit)&&st.c.source_release_ACKs===1,status_wrapper:status,archive_read_calls:0,normal_raw_evidence_materializations:0,admitted_projection_materializations:st.c.original_materializations,auxiliary_value_observations:0,auxiliary_value_materializations:0});
  });
  const first=input.calls[0];assert.ok(first);const later=(i:number)=>Effect.gen(function*(){const call=input.calls[i];assert.ok(call);activeLabel=call.label;const exit=yield* Effect.exit(projector.project(call.stimulus.request));yield* observe(call.label,exit);});
  const hold=first.stimulus.actions.some(a=>a.op==="hold_on_owned_latch"||a.op==="hold_until_external_interrupt");let beforeResume=false,AterminalBeforeACK=false,interruptTerminalBeforeACK=false,ACKbeforeRelease=0;
  if(!hold){yield* later(0);for(let i=1;i<input.calls.length;i++)yield* later(i);}
  else{
   activeLabel=first.label;const A=yield* Effect.forkChild(projector.project(first.stimulus.request),{startImmediately:true});yield* Deferred.await(entered);assert.equal(A.pollUnsafe(),undefined);
   if(first.stimulus.actions.some(a=>a.op==="hold_until_external_interrupt")){
    externalInterrupt=true;const controller=yield* Effect.forkChild(Fiber.interrupt(A),{startImmediately:true});
    if(first.stimulus.actions.some(a=>a.op==="hold_ACK_on_owned_latch")){
     yield* Deferred.await(cleanupEntered);yield* later(1);AterminalBeforeACK=A.pollUnsafe()!==undefined;interruptTerminalBeforeACK=controller.pollUnsafe()!==undefined;ACKbeforeRelease=states.get(first.label)!.c.source_release_ACKs;assert.equal(AterminalBeforeACK,false);assert.equal(interruptTerminalBeforeACK,false);
     activeLabel=first.label;yield* Deferred.succeed(cleanupResume,undefined);yield* Fiber.await(controller);const exit=yield* Fiber.await(A);yield* observe(first.label,exit);yield* later(2);
    }else{yield* Fiber.await(controller);const exit=yield* Fiber.await(A);yield* observe(first.label,exit);yield* later(1);}
   }else{yield* later(1);beforeResume=results.has(input.calls[1]!.label)&&A.pollUnsafe()===undefined;activeLabel=first.label;yield* Deferred.succeed(resume,undefined);const exit=yield* Fiber.await(A);yield* observe(first.label,exit);yield* later(2);}
  }
  for(const st of states.values())assert.equal(st.actions.size,st.input.actions.length,"all owned input action phases executed");
  const A=states.get(input.calls[0]!.label)!,B=states.get(input.calls[1]!.label)!,C=input.calls[2]?states.get(input.calls[2].label):undefined;
  const trace={maximum_active_source_callbacks:maxCallbacks,maximum_owned_leases:maxLeases,source_callback_entries:sourceEntries,B_trusted_callbacks:B.trusted,B_allocations:B.c.source_allocations,B_terminal_before_A_resumed:beforeResume,C_admitted_after_A_terminal:C!==undefined&&C.c.source_allocations===1,ACKs_before_latch_release:ACKbeforeRelease,A_terminal_before_ACK:AterminalBeforeACK,interrupt_controller_terminal_before_ACK:interruptTerminalBeforeACK,A_allocations:A.c.source_allocations,A_cleanup_attempts:A.c.source_release_attempts,A_cleanup_ACKs:A.c.source_release_ACKs,A_descriptor_calls:A.c.descriptor_calls,A_raw_reads:A.c.source_reads,B_admitted_after_A_terminal:B.c.source_allocations===1,factory_poisoned_after_A:results.get(input.calls[1]!.label)?.failure==="cleanup_failed",A_external_interrupt_requested:externalInterrupt,A_release_attempts:A.c.source_release_attempts,A_release_ACKs:A.c.source_release_ACKs,A_terminal_after_release_attempt:results.has(input.calls[0]!.label)&&A.c.source_release_attempts>0};
  return {calls:input.calls.map(call=>({label:call.label,observation:results.get(call.label)})),ownership_trace:trace,secret_cause_exposed:secret,archive_read_calls:0,title_observations:0};
 }));
}
for(const scene of usageDesktopSessionProjectionFixture.stage2_review_supplement.scenes){test(`independent desktop ownership: ${scene.case_id}`,async()=>{
 const result=await Effect.runPromise(runConcurrent(scene.stimulus));assert.deepEqual(result.calls,scene.expected.calls);const trace=object(result.ownership_trace);for(const [key,value]of Object.entries(scene.expected.ownership_trace))assert.deepEqual(trace[key],value,key);assert.equal(result.secret_cause_exposed,scene.expected.secret_cause_exposed);assert.equal(result.archive_read_calls,scene.expected.archive_read_calls);assert.equal(result.title_observations,scene.expected.title_observations);
});}
for(const scene of usageDesktopSessionProjectionFixture.stage2_review_supplement.preservation_observer_scenes){test(`independent desktop preservation observer: ${scene.case_id}`,()=>{assert.deepEqual(observePreservation(scene.stimulus),scene.expected);});}
