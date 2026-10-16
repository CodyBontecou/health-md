import assert from "node:assert/strict";
import { test } from "node:test";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import * as Scope from "effect/Scope";
import * as Exit from "effect/Exit";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import { createCoverageContractFactory, type Code, type Phase, type FixedContractFailure, type ContractSourceProfile, type ContractProfileIssuer, type CoverageContractFactory, type OwnedContractScalar, type OwnedCoverageRequest, type CoverageRequestView, type CoverageResponseView, type CoverageReadView, type OwnedContractReadRequest } from "../src/query/coverage-contract.js";
import { queryCoverageContractFixture as fixture } from "./query-coverage-contract-vectors.js";
interface Action { readonly op:string; readonly action?:string; readonly phase?:string; readonly token?:string; readonly request?:string; readonly startImmediately?:boolean }
interface Stimulus { readonly method:string; readonly representation:string; readonly payload:string; readonly actions:readonly Action[]; readonly profile:string }
interface Observation {
 kind:"completed"|"private_failure"|"inactive"|"interrupted";
 code:Code|null;
 semantic_wire:CoverageRequestView|CoverageResponseView|null;
 encoded_utf8:string|null;
 allocation_calls:0;release_calls:0;release_ack:0;native_qualified:false;source_grant_qualified:false;provider_echo:boolean;
 metadata_value?:CoverageResponseView["metadata"];
 read_materializations?:number;read_current_calls?:number;proxy_traps?:number;replacement_current_calls?:number;callback_cancel_ack?:number;busy_clears_after_callback_ack?:boolean;observation_window?:string;current_calls?:number|null;nested_code?:Code;
}
const secret="SYNTHETIC_PROVIDER_TITLE_NEVER_OUTPUT";
const fixed=(code:Code):FixedContractFailure=>({_tag:"CoverageContractFailure",code});
// Only raw/context primitive semantic port input witnesses reach this capability.
// These are the independent source-input rows, never case IDs or scene.expected.
const numberInputs=fixture.scalar_source_witnesses;
function scalar(raw:string,context:"swift_Int"|"unknown_JSON"):{kind:"i64"|"u64"|"f64";payload:string}|null {
 if(context==="unknown_JSON"){
  const witness=numberInputs.find(x=>x.raw===raw);if(witness){const v=witness.issued;if(v===null)return null;if(v.kind==="f64")return{kind:"f64",payload:v.bits};return{kind:v.kind,payload:v.decimal};}
 }
 // Explicit mathematical integer fixture, not Foundation lexical/rounding equivalence.
 if(raw.length>20||! /^(?:0|-?[1-9][0-9]*)$/.test(raw))return null;
 const n=BigInt(raw);if(n>=-(1n<<63n)&&n<(1n<<63n))return{kind:"i64",payload:n.toString()};
 if(context==="unknown_JSON"&&n>=0n&&n<(1n<<64n))return{kind:"u64",payload:n.toString()};return null;
}
const calendarInputs:readonly(readonly[string,string,boolean])[]=[
 ["2026-01-01","2026-01-01",true],["2024-02-29","2024-03-01",true],["2026-02-30","2026-02-30",false],
 ["2026-02-02","2026-02-01",false],["synthetic","synthetic",false],["","",false],["2026-1-01","2026-01-02",false]
];
function failureCode<A>(exit:Exit.Exit<A,FixedContractFailure>):Code|null { if(Exit.isSuccess(exit))return null;const f=exit.cause.reasons.find(r=>r._tag==="Fail");return f?._tag==="Fail"?f.error.code:null; }
function runScene(stimulus:Stimulus):Effect.Effect<Observation,FixedContractFailure> {
 return Effect.scoped(Effect.gen(function*(){
  const original=yield* Scope.make();yield* Effect.addFinalizer(()=>Scope.close(original,Exit.succeed(undefined)));
  const entered=yield* Deferred.make<void>(),gate=yield* Deferred.make<void>();
  const actions=stimulus.actions,has=(op:string)=>actions.some(a=>a.op===op),hook=(op:string)=>actions.find(a=>a.op===op);
  let factory:CoverageContractFactory|null=null,revoked=false,reads=0,materializations=0,traps=0,replacements=0,cancelACK=0,currentCancelACK=0,nested:Code|null=null;
  let readResult:CoverageRequestView|CoverageResponseView|null=null,encoded:string|null=null;
  let saved:Effect.Effect<CoverageRequestView|null,FixedContractFailure>|null=null,foreignScalar:OwnedContractScalar|null=null;
  let currentCalls=0,observing=false,readObservation=false,profileHookEnabled=true,terminalDecodeCompleted=false;
  let profileActive=0,profileStarted=0,profileFinalized=0,currentActive=0;
  const close=Scope.close(original,Exit.succeed(undefined));
  const proxy=()=>new Proxy({}, {get(){traps++;throw secret;},ownKeys(){traps++;throw secret;},getOwnPropertyDescriptor(){traps++;throw secret;},getPrototypeOf(){traps++;throw secret;},has(){traps++;throw secret;}});
  const observeRead=(work:Effect.Effect<CoverageRequestView|null,FixedContractFailure>)=>work.pipe(Effect.tap(v=>Effect.sync(()=>{readResult=v;if(v!==null)materializations++;})));
  const current={check:(phase:Phase):Effect.Effect<void,FixedContractFailure>=>Effect.gen(function*(){
   currentActive++;if(observing)currentCalls++;if(readObservation&&phase==="before_read")reads++;
   const c=hook("current_hook");if(c?.phase===phase){if(c.action?.startsWith("close_then")){yield* close;if(c.action==="close_then_fail")return yield* Effect.fail(fixed("not_authorized"));if(c.action==="close_then_defect")return yield* Effect.die(secret);}if(c.action==="deny")return yield* Effect.fail(fixed("not_authorized"));}
   if(readObservation&&hook("defer_current")?.phase===phase){yield* Effect.gen(function*(){yield* Deferred.succeed(entered,undefined);yield* Deferred.await(gate);}).pipe(Effect.onInterrupt(()=>Effect.sync(()=>{currentCancelACK++;})));}
   if(phase==="after_callback"&&has("postcurrent_execute_saved_read")){assert.ok(saved);yield* observeRead(saved);}
   if(revoked)return yield* Effect.fail(fixed("not_authorized"));
  }).pipe(Effect.ensuring(Effect.sync(()=>{currentActive--;})))};
  const profile:ContractSourceProfile={
   number:(raw,context,slot,issuer)=>Effect.gen(function*(){
    profileActive++;profileStarted++;
    const action=profileHookEnabled?hook("profile_hook")?.action:undefined;
    if(action==="close_then_return_issued")yield* close;
    if(action==="defect_provider_secret")return yield* Effect.die(secret);
    if(action==="return_other_factory_scalar"){assert.ok(foreignScalar);return foreignScalar;}
    if(action==="suspend_onInterrupt_ack")yield* Effect.gen(function*(){yield* Deferred.succeed(entered,undefined);yield* Deferred.await(gate);}).pipe(Effect.onInterrupt(()=>Effect.sync(()=>{cancelACK++;})));
    if(action==="reentrant_decode"){assert.ok(factory);const e=yield* Effect.exit(factory.decodeRequest(stimulus.representation,stimulus.payload));nested=failureCode(e);}
    const value=scalar(raw,context);if(!value)return yield* Effect.fail(fixed("native_profile_unavailable"));
    const token=issuer.issueNumber(action==="issue_wrong_slot"?Object.freeze({}):slot,value.kind,value.payload);if(token===null)return yield* Effect.fail(fixed("native_profile_unavailable"));return token;
   }).pipe(Effect.ensuring(Effect.sync(()=>{profileActive--;profileFinalized++;}))),
   civilRange:(start,end,slot,issuer)=>Effect.gen(function*(){const row=calendarInputs.find(x=>x[0]===start&&x[1]===end);if(!row)return yield* Effect.fail(fixed("native_profile_unavailable"));const token=issuer.issueCivil(slot,start,end,row[2]);assert.ok(token);return token;}),
   canonicalNumber:(kind,payload)=>{
    if(kind!=="f64")return Result.succeed(BigInt(payload).toString());
    const row=numberInputs.find(x=>x.issued?.kind==="f64"&&x.issued.bits===payload);return row?.canonical_utf8===null||row?.canonical_utf8===undefined?Result.fail({_tag:"TypedValueFailure" as const,code:"native_profile_unavailable" as const}):Result.succeed(row.canonical_utf8);
   },
   duplicateDecodedKey:()=>stimulus.profile==="explicit_duplicate_reject"?Result.succeed("reject"):Result.succeed(stimulus.profile==="explicit_duplicate_last"?"last":"first"),
  };
  factory=yield* Scope.provide(original)(createCoverageContractFactory(current,profile));const own=factory;
  const baseline=()=>own.decodeRequest(stimulus.representation,stimulus.payload);
  // A real token from a separate factory is seeded through its own issuer callback.
  let foreignRequest:OwnedCoverageRequest|null=null;
  if(has("seed_other_factory")||hook("profile_hook")?.action==="return_other_factory_scalar"){
   const foreignProfile:ContractSourceProfile={...profile,number:(raw,context,slot,issuer)=>Effect.gen(function*(){const s=scalar(raw,context);assert.ok(s);const token=issuer.issueNumber(slot,s.kind,s.payload);assert.ok(token);foreignScalar=token;return token;})};
   const foreign=yield* Scope.provide(original)(createCoverageContractFactory({check:()=>Effect.void},foreignProfile));foreignRequest=yield* foreign.decodeRequest(stimulus.representation,stimulus.payload);
  }
  const lifetime=stimulus.method==="lifetime";
  let seed:OwnedCoverageRequest|null=null;
  const seedNeeded=has("with_token")||has("read_saved")||has("with_foreign_token")||has("return_callback")||has("provide_fresh_scope");
  if(lifetime&&seedNeeded){profileHookEnabled=false;seed=yield* baseline();profileHookEnabled=true;}
  if(has("close_original")&&!has("await_current_entered")&&!has("replace_current_method"))yield* close;
  const normal:Effect.Effect<void,FixedContractFailure>=Effect.gen(function*(){
   if(stimulus.method==="decode_request"||stimulus.method==="admit_request"){
    let token=yield* baseline();if(stimulus.method==="admit_request")token=yield* own.admitRequest(token);
    yield* own.withRequest(token,(request,view)=>Effect.gen(function*(){readResult=yield* view.readRequest(request,token);encoded=yield* view.encode(request,token);}));
   }else{
    let token=yield* own.decodeResponse(stimulus.representation,stimulus.payload);if(stimulus.method==="construct_response")token=yield* own.constructResponse(token);
    yield* own.withResponse(token,(request,view)=>Effect.gen(function*(){readResult=yield* view.readResponse(request,token);encoded=yield* view.encode(request,token);}));
   }
  });
  let exit:Exit.Exit<void,FixedContractFailure>;
  if(!lifetime)exit=yield* Effect.exit(normal);
  else if(hook("profile_hook")?.action==="suspend_onInterrupt_ack"){
   observing=true;const fiber=yield* Effect.forkChild(baseline().pipe(Effect.asVoid),{startImmediately:true});yield* Deferred.await(entered);yield* Fiber.interrupt(fiber);const e=yield* Fiber.await(fiber);exit=Exit.isFailure(e)?e:Exit.succeed(undefined);profileHookEnabled=false;const reusable=yield* Effect.exit(baseline());assert.ok(Exit.isSuccess(reusable),"after joined callback ACK the original live factory must accept another decode");
  }else if(has("await_current_entered")){
   assert.ok(seed);const token=seed;readObservation=true;
   const work=own.withRequest(token,(request,view)=>observeRead(view.readRequest(request,token))).pipe(Effect.asVoid);
   const fiber=yield* Effect.forkChild(work,{startImmediately:true});yield* Deferred.await(entered);yield* close;yield* Deferred.succeed(gate,undefined);exit=yield* Fiber.await(fiber);
  }else if(has("with_foreign_token")){
   assert.ok(foreignRequest);exit=yield* Effect.exit(own.withRequest(foreignRequest,()=>Effect.die("foreign callback entered")).pipe(Effect.asVoid));
  }else if(hook("with_token")?.token==="proxy"){
   exit=yield* Effect.exit(own.withRequest(proxy(),()=>Effect.die("proxy callback entered")).pipe(Effect.asVoid));
  }else if(seed){
   const token=seed;exit=yield* Effect.exit(own.withRequest(token,(request,view)=>Effect.gen(function*(){
    readObservation=true;
    if(has("save_read_effect"))saved=view.readRequest(request,token);
    if(has("replace_current_method")){saved=view.readRequest(request,token);return;}
    if(has("read")){const a=hook("read")!;yield* observeRead(view.readRequest(a.request==="proxy"?proxy():request,a.token==="proxy"?proxy():token));return;}
    if(has("execute_saved_read")&&!has("return_callback")){assert.ok(saved);yield* observeRead(saved);if(has("revoke_current")){revoked=true;yield* observeRead(saved);}return;}
   })) .pipe(Effect.asVoid));
   if(has("replace_current_method")){current.check=()=>Effect.sync(()=>{replacements++;});yield* close;assert.ok(saved);yield* Effect.scoped(observeRead(saved));}
   if(has("return_callback")&&has("execute_saved_read")){assert.ok(saved);yield* observeRead(saved);}
  }else{observing=true;exit=yield* Effect.exit(baseline().pipe(Effect.asVoid));terminalDecodeCompleted=Exit.isSuccess(exit);}
  assert.equal(currentActive,0,"all started Current callbacks must finish or acknowledge interruption before observation");
  void currentCancelACK;
  const code=failureCode(exit);const interrupted=Exit.isFailure(exit)&&exit.cause.reasons.some(r=>r._tag==="Interrupt");
  const obs:Observation={kind:interrupted?"interrupted":code?"private_failure":lifetime&&readResult===null&&!terminalDecodeCompleted?"inactive":"completed",code,semantic_wire:lifetime?null:readResult,encoded_utf8:lifetime?null:encoded,allocation_calls:0,release_calls:0,release_ack:0,native_qualified:false,source_grant_qualified:false,provider_echo:false};
  if(stimulus.profile==="finite_macos_untagged_number_witness"&&readResult&&"coverage" in readResult&&readResult.metadata)obs.metadata_value=readResult.metadata;
  if(lifetime){obs.read_materializations=materializations;obs.read_current_calls=reads;obs.proxy_traps=traps;obs.replacement_current_calls=replacements;obs.callback_cancel_ack=cancelACK;obs.busy_clears_after_callback_ack=profileActive===0&&profileFinalized===profileStarted;obs.observation_window="Only scheduled actions after decode seed; decode seed excluded from read counters. Current before_decode scenes count current_calls separately.";obs.current_calls=hook("current_hook")?currentCalls:null;if(nested)obs.nested_code=nested;}
  obs.provider_echo=JSON.stringify(obs).includes(secret);return obs;
 }));
}
for(const scene of fixture.cases){
 test("independent query coverage contract literal: "+scene.case_id,async()=>{
  const actual=await Effect.runPromise(runScene(scene.stimulus));
  for(const [field,expected]of Object.entries(scene.expected))assert.deepEqual(Reflect.get(actual,field),expected,field);
 });
}
test("query coverage contract immutable Stage1 raw bytes",async()=>{
 const raw=await readFile(new URL("../../tests/query-coverage-contract-vectors.ts",import.meta.url));
 assert.equal(createHash("sha256").update(raw).digest("hex"),"cc100cbba9676e70b59fabbf2d1004dd7a67c28f7c6ba818258f26969a88edb1");
});
// Compile-only shape/opacity guarantees; no services or runtime side effects.
function closedTypeWitnesses(view:CoverageReadView,request:OwnedContractReadRequest,value:OwnedCoverageRequest):void {
 // @ts-expect-error own tokens cannot be caller-created JSON shapes
 const forged:OwnedCoverageRequest={};
 // @ts-expect-error a lazy read requires Effect execution, never a synchronous view permit
 const synchronous:CoverageRequestView|null=view.readRequest(request,value);
 // @ts-expect-error coverage metadata is an untagged object graph, never an array root
 const metadata:CoverageResponseView["metadata"]={kind:"array",values:[]};
 void forged;void synchronous;void metadata;
}
void closedTypeWitnesses;
