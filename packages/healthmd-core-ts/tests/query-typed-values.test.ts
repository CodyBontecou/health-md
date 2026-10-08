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
import { createTypedValueFactory, type TypedValueFactory, type FixedTypedFailure, type TypedPhase, type NativeTypedProfile, type NativeScalarIssuer, type OwnedNativeScalar, type OwnedTypedValue, type TypedView, type TypedReadView, type OwnedReadRequest } from "../src/query/typed-values.js";
import { queryTypedValuesFixture as fixture } from "./query-typed-values-vectors.js";
const sourcePortInputs = {
  "number_inputs": [
    {
      "raw": "0",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "0",
      "source_id": "json-number-0"
    },
    {
      "raw": "-0",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "0",
      "source_id": "json-number--0"
    },
    {
      "raw": "1",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "1",
      "source_id": "json-number-1"
    },
    {
      "raw": "1.0",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "1",
      "source_id": "json-number-1.0"
    },
    {
      "raw": "1e0",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "1",
      "source_id": "json-number-1e0"
    },
    {
      "raw": "1.5",
      "context": "unknown_JSON",
      "kind": "f64",
      "payload": "3ff8000000000000",
      "source_id": "json-number-1.5"
    },
    {
      "raw": "9007199254740993",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "9007199254740993",
      "source_id": "json-number-9007199254740993"
    },
    {
      "raw": "9223372036854775807",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "9223372036854775807",
      "source_id": "json-number-9223372036854775807"
    },
    {
      "raw": "9223372036854775808",
      "context": "unknown_JSON",
      "kind": "u64",
      "payload": "9223372036854775808",
      "source_id": "json-number-9223372036854775808"
    },
    {
      "raw": "18446744073709551615",
      "context": "unknown_JSON",
      "kind": "u64",
      "payload": "18446744073709551615",
      "source_id": "json-number-18446744073709551615"
    },
    {
      "raw": "18446744073709551616",
      "context": "unknown_JSON",
      "kind": "f64",
      "payload": "43f0000000000000",
      "source_id": "json-number-18446744073709551616"
    },
    {
      "raw": "-9223372036854775809",
      "context": "unknown_JSON",
      "kind": "f64",
      "payload": "c3e0000000000000",
      "source_id": "json-number--9223372036854775809"
    },
    {
      "raw": "1e308",
      "context": "unknown_JSON",
      "kind": "f64",
      "payload": "7fe1ccf385ebc8a0",
      "source_id": "json-number-1e308"
    },
    {
      "raw": "1e-400",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "0",
      "source_id": "json-number-1e-400"
    },
    {
      "raw": "-1e-400",
      "context": "unknown_JSON",
      "kind": "i64",
      "payload": "0",
      "source_id": "json-number--1e-400"
    },
    {
      "raw": "5e-324",
      "context": "unknown_JSON",
      "kind": "f64",
      "payload": "0000000000000001",
      "source_id": "json-number-5e-324"
    },
    {
      "raw": "9007199254740993",
      "context": "i64_count",
      "kind": "i64",
      "payload": "9007199254740993",
      "source_id": "count-exact"
    },
    {
      "raw": "9223372036854775807",
      "context": "i64_count",
      "kind": "i64",
      "payload": "9223372036854775807",
      "source_id": "count-max"
    },
    {
      "raw": "1.0",
      "context": "i64_count",
      "kind": "i64",
      "payload": "1",
      "source_id": "count-integral-decimal"
    },
    {
      "raw": "1e0",
      "context": "i64_count",
      "kind": "i64",
      "payload": "1",
      "source_id": "count-integral-exponent"
    },
    {
      "raw": "3",
      "context": "i64_count",
      "kind": "i64",
      "payload": "3",
      "source_id": "count-extra"
    },
    {
      "raw": "-0",
      "context": "quantity_f64",
      "kind": "f64",
      "payload": "8000000000000000",
      "source_id": "quantity-negative-zero"
    },
    {
      "raw": "1.0",
      "context": "quantity_f64",
      "kind": "f64",
      "payload": "3ff0000000000000",
      "source_id": "quantity-integral-float"
    },
    {
      "raw": "3",
      "context": "i64_count",
      "kind": "i64",
      "payload": "3",
      "source_id": "duplicate-type-count-first"
    },
    {
      "raw": "1",
      "context": "i64_count",
      "kind": "i64",
      "payload": "1",
      "source_id": "duplicate-value"
    },
    {
      "raw": "1",
      "context": "i64_count",
      "kind": "i64",
      "payload": "1",
      "source_id": "duplicate-escaped-value"
    },
    {
      "raw": "12.5",
      "context": "quantity_f64",
      "kind": "f64",
      "payload": "4029000000000000",
      "source_id": "original_source_literal_or_exact_math"
    },
    {
      "raw": "60",
      "context": "duration_f64",
      "kind": "f64",
      "payload": "404e000000000000",
      "source_id": "original_source_literal_or_exact_math"
    },
    {
      "raw": "1.5",
      "context": "unknown_JSON",
      "kind": "f64",
      "payload": "3ff8000000000000",
      "source_id": "original_source_literal_or_exact_math"
    }
  ],
  "canonical_f64_inputs": {
    "3ff8000000000000": "1.5",
    "43f0000000000000": "1.8446744073709552e+19",
    "c3e0000000000000": "-9.223372036854776e+18",
    "7fe1ccf385ebc8a0": "1e+308",
    "0000000000000001": "5e-324",
    "8000000000000000": "-0",
    "3ff0000000000000": "1",
    "4029000000000000": "12.5",
    "404e000000000000": "60"
  },
  "timestamp_inputs": [
    {
      "raw_frame": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456717Z\"}",
      "rawCanonical": "2023-11-14T22:13:20.123456717Z",
      "issue_payload": {
        "canonical": "2023-11-14T22:13:20.123456717Z",
        "reference_bits": "41c58214400fcd6e",
        "unix_bits": "41d954fc4007e6b7"
      },
      "source_witness_id": "timestamp-nine-representable",
      "input_only": true
    }
  ],
  "duplicate_inputs": [
    {
      "raw_frame": "{\"type\":\"count\",\"type\":\"string\",\"value\":3}",
      "policy": "first"
    },
    {
      "raw_frame": "{\"type\":\"string\",\"type\":\"count\",\"value\":\"x\"}",
      "policy": "first"
    },
    {
      "raw_frame": "{\"type\":\"count\",\"value\":1,\"value\":2}",
      "policy": "first"
    },
    {
      "raw_frame": "{\"type\":\"count\",\"value\":1,\"val\\u0075e\":2}",
      "policy": "first"
    },
    {
      "raw_frame": "{\"type\":\"future_value\",\"value\":{\"a\":1,\"\\u0061\":2}}",
      "policy": "first"
    },
    {
      "raw_frame": "{\"type\":\"future_value\",\"value\":{\"a\":{\"x\":1,\"x\":2}}}",
      "policy": "first"
    }
  ],
  "policy": "Keys raw/context/kind/payload only. Neither case id nor expected observation reaches profile; finite native source and exact mathematical integer inputs, no complete Foundation numeric/Date renderer."
} as const;
type Action={readonly at:string;readonly action:string;readonly bits?:readonly string[]};
type Stimulus={readonly operation:string;readonly representation:string;readonly payload:unknown;readonly actions:readonly Action[]};
type Observation={kind:"completion"|"private_failure"|"interruption";failure:FixedTypedFailure['code']|null;view:TypedView|null;canonical_utf8:string|null;allocations:0;release_calls:0;release_ACKs:0;provider_echo:boolean;[key:string]:unknown};
const fixed=(code:FixedTypedFailure['code']):FixedTypedFailure=>Object.freeze({_tag:"TypedValueFailure",code});
const sentinel="SYNTHETIC_EXCLUDED_PROVIDER_TITLE";
function expandPayload(p:unknown,traps:()=>object):unknown {
 if(typeof p==='string')return p;if(typeof p!=='object'||p===null)return p;
 const r=p as {recipe?:string;repeat?:number;array_depth?:number;elements?:number;repeat_ascii_x?:number;driver_constructs?:string};
 if(r.driver_constructs)return traps();
 if(r.recipe==='ascii_space_repeat')return ' '.repeat(r.repeat!);
 if(r.recipe==='nested_unknown_JSON_arrays')return '{"type":"future_value","value":'+'['.repeat(r.array_depth!)+'null'+']'.repeat(r.array_depth!)+'}';
 if(r.recipe==='unknown_array_nulls')return '{"type":"future_value","value":['+Array(r.elements!).fill('null').join(',')+']}';
 if(r.recipe==='typed_string')return '{"type":"string","value":"'+'x'.repeat(r.repeat_ascii_x!)+'"}';
 throw new Error('unrecognized closed input recipe');
}
function scalarWitness(raw:string,context:Parameters<NativeTypedProfile['number']>[1]):{kind:"i64"|"u64"|"f64";payload:string}|null {
 const exact=sourcePortInputs.number_inputs.find(x=>x.raw===raw&&x.context===context);if(exact)return{kind:exact.kind,payload:exact.payload};
 // Pure exact integer input stimulus. This is not a full Foundation numeric parser.
 if(!/^-?(?:0|[1-9][0-9]*)$/.test(raw)||raw==='-0'||raw.length>20)return null;
 const n=BigInt(raw);if(context==='i64_count'||context==='i64_category')return n>=-(1n<<63n)&&n<(1n<<63n)?{kind:'i64',payload:n.toString()}:null;
 if(context==='unknown_JSON'){if(n>=-(1n<<63n)&&n<(1n<<63n))return{kind:'i64',payload:n.toString()};if(n>=0n&&n<(1n<<64n))return{kind:'u64',payload:n.toString()};}return null;
}
function runScene(stimulus:Stimulus):Effect.Effect<Observation,FixedTypedFailure> {
 return Effect.scoped(Effect.gen(function*(){
  const original=yield* Scope.make();yield* Effect.addFinalizer(()=>Scope.close(original,Exit.succeed(undefined)));
  const entered=yield* Deferred.make<void>(),gate=yield* Deferred.make<void>();
  const actions=stimulus.actions;const has=(action:string)=>actions.some(x=>x.action===action);
  let factory:TypedValueFactory|null=null,revoked=false,readCalls=0,profileCalls=0,canonicalCalls=0,callbacks=0,traps=0,materializations=0,replacementCalls=0,cancelACK=false;
  let reentry:FixedTypedFailure['code']|null=null,nonfiniteIssued=0,readResult:TypedView|null=null;const readResults:(TypedView|null)[]=[];const phases:TypedPhase[]=[];
  let savedRead:Effect.Effect<TypedView|null,FixedTypedFailure>|null=null,priorScalar:OwnedNativeScalar|null=null,foreignScalar:OwnedNativeScalar|null=null;
  const proxy=()=>new Proxy({}, {get(){traps++;throw sentinel;},ownKeys(){traps++;throw sentinel;},getOwnPropertyDescriptor(){traps++;throw sentinel;},getPrototypeOf(){traps++;throw sentinel;},has(){traps++;throw sentinel;}});
  const close=Scope.close(original,Exit.succeed(undefined));
  const observeRead=(e:Effect.Effect<TypedView|null,FixedTypedFailure>)=>e.pipe(Effect.tap(v=>Effect.sync(()=>{readResult=v;readResults.push(v);if(v!==null)materializations++;})));
  const current={check:(phase:TypedPhase):Effect.Effect<void,FixedTypedFailure>=>Effect.gen(function*(){phases.push(phase);if(phase==='before_read')readCalls++;
   if(phase==='before_decode'&&has('deny_current_source_or_purpose_or_detail_or_destination'))return yield* Effect.fail(fixed('not_authorized'));
   if(phase==='before_read'&&(has('suspend_current_close_original_resume_success')||has('suspend_signal_registered_then_external_interrupt'))){
    // Handler surrounds readiness AND wait; readiness cannot race cancellation registration.
    yield* Effect.gen(function*(){yield* Deferred.succeed(entered,undefined);yield* Deferred.await(gate);}).pipe(Effect.onInterrupt(()=>Effect.sync(()=>{cancelACK=true;})));
   }
   if(phase==='before_encode'&&has('revoke_after_successful_read'))revoked=true;
   if(phase==='before_publication'&&has('close_original_then_defect')){yield* close;return yield* Effect.die(sentinel);}
   if(phase==='after_callback'&&has('execute_saved_read')){assert.ok(savedRead);yield* observeRead(savedRead);}
   if(revoked)return yield* Effect.fail(fixed('not_authorized'));
  })};
  const f64Canonical:Readonly<Record<string,string>>=sourcePortInputs.canonical_f64_inputs;
  const profile:NativeTypedProfile={
   number:(raw,context,slot,issuer)=>Effect.gen(function*(){profileCalls++;
    if(has('close_original_then_fail_private')){yield* close;return yield* Effect.fail(fixed('invalid_typed_value'));}
    if(has('decode_reenter_same_factory')){assert.ok(factory);const ex=yield* Effect.exit(factory.decode(stimulus.representation,stimulus.payload));if(Exit.isFailure(ex)){const r=ex.cause.reasons.find(x=>x._tag==='Fail');if(r?._tag==='Fail')reentry=r.error.code;}}
    if(has('return_foreign_factory_numeric_token')){assert.ok(foreignScalar);return foreignScalar;}
    if(has('return_prior_callback_token_same_primitive_wire')&&priorScalar)return priorScalar;
    const invalid=actions.find(x=>x.action==='attempt_issue_nonfinite_bits_then_fail_non_finite_number');if(invalid){for(const b of invalid.bits??[])if(issuer.issueNumber(slot,'f64',b)!==null)nonfiniteIssued++;return yield* Effect.fail(fixed('non_finite_number'));}
    const w=scalarWitness(raw,context);if(!w){const typedInteger=context==='i64_count'||context==='i64_category';return yield* Effect.fail(fixed(typedInteger?'invalid_typed_value':'native_profile_unavailable'));}
    const token=issuer.issueNumber(slot,w.kind,w.payload);assert.ok(token);priorScalar=token;return token;
   }),
   timestamp:(raw,slot,issuer)=>Effect.gen(function*(){profileCalls++;
    const w=sourcePortInputs.timestamp_inputs.find(x=>x.rawCanonical===raw);let token:OwnedNativeScalar|null;
    if(w)token=issuer.issueTimestamp(slot,w.issue_payload.canonical,w.issue_payload.reference_bits,w.issue_payload.unix_bits);
    else if(raw==='2023-11-14T22:13:20.125000000Z')token=issuer.issueTimestamp(slot,raw);
    else return yield* Effect.fail(fixed('invalid_typed_value'));
    assert.ok(token);return token;
   }),
   canonicalNumber:(kind,payload)=>{canonicalCalls++;if(kind!=='f64')return Result.succeed(BigInt(payload).toString());const s=f64Canonical[payload];return s===undefined?Result.fail(fixed('native_profile_unavailable')):Result.succeed(s);},
   duplicateDecodedKey:(wire,_key)=>sourcePortInputs.duplicate_inputs.some(x=>x.raw_frame===wire)?Result.succeed('first'):Result.fail(fixed('native_profile_unavailable')),
  };
  factory=yield* Scope.provide(original)(createTypedValueFactory(current,profile));const own=factory;
  if(has('return_foreign_factory_numeric_token')){
   const foreignProfile:NativeTypedProfile={...profile,number:(raw,context,slot,issuer)=>Effect.gen(function*(){const w=scalarWitness(raw,context);assert.ok(w);const token=issuer.issueNumber(slot,w.kind,w.payload);assert.ok(token);foreignScalar=token;return token;})};
   const foreign=yield* Scope.provide(original)(createTypedValueFactory({check:()=>Effect.void},foreignProfile));
   yield* foreign.decode(stimulus.representation,stimulus.payload);assert.ok(foreignScalar);
  }

  // Genuine previous callback token in this SAME factory with exactly the same primitive frame.
  if(has('return_prior_callback_token_same_primitive_wire')){const saved=actions.find(x=>x.action==='return_prior_callback_token_same_primitive_wire');assert.ok(saved);const input=stimulus.payload;const seed=yield* Effect.exit(own.decode(stimulus.representation,input));assert.ok(Exit.isSuccess(seed));profileCalls=0;phases.length=0;}
  if(has('close_original'))yield* close;
  const completed:{view:TypedView|null;wire:string|null}={view:null,wire:null};
  const operation:Effect.Effect<void,FixedTypedFailure>=Effect.gen(function*(){const value=yield* own.decode(stimulus.representation,expandPayload(stimulus.payload,proxy));
   yield* own.withValue(value,(request,view)=>Effect.gen(function*(){callbacks++;
    if(has('foreign_factory_value_proxy')){yield* observeRead(view.read(request,proxy()));return;}
    if(has('foreign_callback_request_proxy_with_own_value')){yield* observeRead(view.read(proxy(),value));return;}
    if(has('save_read_return')||has('save_view_then_return')){savedRead=view.read(request,value);return;}
    const lazy=view.read(request,value);
    if(has('execute_same_lazy_read_success_revoke_execute_again')){completed.view=yield* observeRead(lazy);revoked=true;yield* observeRead(lazy);return;}
    completed.view=yield* observeRead(lazy);
    if(stimulus.operation==='decode_then_withValue_controlled_read_only')return;
    completed.wire=yield* view.encode(request,value);
   }));
  });
  let result:Exit.Exit<void,FixedTypedFailure>;
  if(has('suspend_current_close_original_resume_success')||has('suspend_signal_registered_then_external_interrupt')){
   const child=yield* Effect.forkChild(operation,{startImmediately:true});yield* Deferred.await(entered);
   if(has('suspend_current_close_original_resume_success')){yield* close;yield* Deferred.succeed(gate,undefined);}else yield* Fiber.interrupt(child);
   result=yield* Fiber.await(child);
  }else result=yield* Effect.exit(operation);
  if(has('replace_current_method_provide_fresh_scope_execute_read')){current.check=()=>Effect.sync(()=>{replacementCalls++;});assert.ok(savedRead);yield* Effect.scoped(observeRead(savedRead));}
  if(has('execute_saved_read_twice')){assert.ok(savedRead);yield* observeRead(savedRead);yield* observeRead(savedRead);}
  let kind:Observation['kind']='completion',code:FixedTypedFailure['code']|null=null;
  if(Exit.isFailure(result)){if(result.cause.reasons.some(x=>x._tag==='Interrupt'))kind='interruption';else{kind='private_failure';const f=result.cause.reasons.find(x=>x._tag==='Fail');code=f?._tag==='Fail'?f.error.code:null;}}
  const obs:Observation={kind,failure:code,view:kind==='completion'?completed.view:null,canonical_utf8:kind==='completion'?completed.wire:null,allocations:0,release_calls:0,release_ACKs:0,provider_echo:false,
   observed_reads:materializations,native_decode_calls:profileCalls,native_canonical_number_calls:canonicalCalls,withValue_callbacks:callbacks,property_traps:traps,current_read_calls:readCalls,read_current_calls:readCalls,successful_materializations:materializations,replacement_current_calls:replacementCalls,current_pending_cancel_ACK:cancelACK,read_result:readResult,read_results:readResults,reentry_failure:reentry,outer_completion:kind==='completion',profile_calls:profileCalls,issuer_nonfinite_tokens:nonfiniteIssued,canonical_published:completed.wire!==null,boundary_accepted:kind==='completion',civil_calendar_validation_performed:false,current_phase_trace:phases};
  if(has('execute_same_lazy_read_success_revoke_execute_again')){obs.first_read=completed.view?.type==='count'?'count'+completed.view.decimal:null;obs.second_failure=code;}
  if(completed.wire!==null){obs.canonical_UTF8_bytes=Buffer.byteLength(completed.wire,'utf8');obs.canonical_SHA256=createHash('sha256').update(completed.wire).digest('hex');}
  obs.provider_echo=JSON.stringify(obs).includes(sentinel);return obs;
 }));
}
function expectedRecipe(recipe:unknown):TypedView {
 const r=recipe as {kind:string;repeat?:number;array_depth?:number;null_elements?:number};
 if(r.kind==='typed_string_ascii')return{type:'string',value:'x'.repeat(r.repeat!)};
 let value:import('../src/query/typed-values.js').UnknownJson={kind:'null'};
 if(r.kind==='unknown_array_nesting')for(let i=0;i<r.array_depth!;i++)value={kind:'array',values:[value]};
 else if(r.kind==='unknown_array_nulls')value={kind:'array',values:Array.from({length:r.null_elements!},()=>({kind:'null' as const}))};
 else throw new Error('unknown expected-only structural recipe');
 return{type:'unknown',tag:'future_value',value};
}
for(const scene of fixture.cases){
 test('independent query typed value literal: '+scene.case_id,async()=>{
  const actual=await Effect.runPromise(runScene(scene.stimulus));
  // Expected data participates ONLY in assertions after the real action-driven effect exits.
  for(const [key,expected]of Object.entries(scene.expected)){
   if(key==='view_recipe'){assert.deepEqual(actual.view,expectedRecipe(expected));continue;}
   if(key==='native_pipeline_observation'||key==='native_decoder_stage_error_not_inferred'){
    assert.ok('native_source_golden_id' in scene);const row=fixture.native_source_witness.output.value.rows.find(r=>r.id===scene.native_source_golden_id);assert.ok(row);
    assert.equal(row.result,'native_rejected');assert.equal(key==='native_pipeline_observation'?row.result:row.result==='native_rejected',expected);
    continue; // Whole native source pipeline evidence, not candidate-stage instrumentation.
   }
   assert.deepEqual(actual[key],expected,key);
  }
 });
}
test('query typed values immutable source corpus and native witness provenance',async()=>{
 const bytes=await readFile(new URL('../../tests/query-typed-values-vectors.ts',import.meta.url));
 assert.equal(createHash('sha256').update(bytes).digest('hex'),'76f1fa20c3901132824ecd598fd67a5dfbad5741ec3288ff202b9ea7a37674d0');
 assert.equal(fixture.cases.length,128);assert.equal(new Set(fixture.cases.map(x=>x.case_id)).size,128);
 assert.equal(fixture.native_source_witness.output.value.rows.length,46);assert.equal(fixture.native_source_witness.output.value.dates.length,6);
});
