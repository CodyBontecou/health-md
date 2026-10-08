import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { OwnedPersonalRecord, createPersonalRecordCodec } from "../contracts/personal-slice.js";
export type SessionCode="invalid_request"|"invalid_source"|"scope_not_authorized"|"owned_handoff_closed"|"cleanup_failed"|"source_failed"|"candidate_limit_exceeded";
export interface SessionFailure {readonly code:SessionCode}
const originalBrand:unique symbol=Symbol("original"); const projectionBrand:unique symbol=Symbol("projection");
export interface OwnedOriginal {readonly [originalBrand]:true}
export interface OwnedSessionProjection {readonly [projectionBrand]:true}
export interface OriginalLifetime {isLive():boolean; readonly closed:Effect.Effect<void>}
export type ProjectionPhase="before_allocation"|"before_original"|"before_decode"|"before_publication"|"before_read";
export interface TrustedSessionBinding {readonly dataset_id:string;readonly source_id:string;readonly source_revision:string;readonly purpose:string;readonly clock_profile:"synthetic-v1"|"native-evidence-v1"}
export interface CurrentSessionAuthority {check(binding:TrustedSessionBinding,phase:ProjectionPhase):Effect.Effect<void,SessionFailure>}
export interface SessionSourceDescriptor {
 readonly dataset_id:string;readonly source_id:string;readonly source_revision:string;
 readonly source_evidence_ref:{readonly state:"known";readonly value:string}|{readonly state:"unknown";readonly reason:"not_reported"};
 readonly app_identity:string;readonly authoritative_app_class:"browser"|"non_browser"|"unknown";
 readonly declared_projection_app_class:"browser"|"non_browser"|"unknown";
 readonly admitted_fields:readonly ["record","original_end","clock_basis","native_algorithm","local_start_text","source_utc_offset"];
 readonly forbidden_detail_present:readonly ("browser_title"|"browser_url"|"browser_history"|"input_telemetry"|"nonbrowser_title"|"archive_auxiliary")[];
}
export interface SourceDescriptorCapability {describe(binding:TrustedSessionBinding):Effect.Effect<SessionSourceDescriptor,SessionFailure>}
export interface OriginalView {read(ticket:unknown):Effect.Effect<string|null,SessionFailure>}
export interface OriginalIssuer {commit():OwnedOriginal|null}
export interface EligibleOriginalSource {
 withOriginal<A>(originalScope:OriginalLifetime,issuer:OriginalIssuer,use:(ticket:OwnedOriginal,view:OriginalView)=>Effect.Effect<A,SessionFailure>):Effect.Effect<A,SessionFailure>;
}
export interface ProjectionMetadata {readonly status:"canonical_session"|"outside_clock_profile"|"unknown_original_end"|"clock_inconsistent"|"duration_disagreement";readonly canonical:boolean;readonly original_end:"present"|"unknown";readonly fabricated_observed_end:false;readonly discard_under_two:false;readonly cleanup_ACK:true}
export interface SourceEvidenceReference {readonly state:"known";readonly value:string}
export interface SessionStatusWrapper {readonly record_ref:string;readonly canonical_status:"valid"|"unavailable"|"outside_canonical";readonly reason_codes:readonly string[];readonly source_evidence_ref:SourceEvidenceReference}
export interface ProjectionView {read(projection:unknown):Effect.Effect<{readonly metadata:ProjectionMetadata;readonly record:OwnedPersonalRecord|null;readonly status:SessionStatusWrapper}|null,SessionFailure>}
export interface SessionProjector {project(request:unknown):Effect.Effect<OwnedSessionProjection,SessionFailure>;readonly view:ProjectionView}
export interface SessionProjectorFactory {create(trusted:{readonly binding:TrustedSessionBinding;readonly current:CurrentSessionAuthority;readonly source:EligibleOriginalSource;readonly descriptor:SourceDescriptorCapability;readonly codec:ReturnType<typeof createPersonalRecordCodec>}):Effect.Effect<SessionProjector,SessionFailure,Scope.Scope>}

import * as Result from "effect/Result";
import * as Cause from "effect/Cause";
const failureCodes=new WeakMap<object,SessionCode>();
export function sessionFailure(code:SessionCode):SessionFailure {const e=Object.freeze({code});failureCodes.set(e,code);return e;}
function codeOf(e:unknown,fallback:SessionCode):SessionCode{return e!==null&&(typeof e==="object"||typeof e==="function")?failureCodes.get(e)??fallback:fallback;}
function reject(code:SessionCode):never{throw sessionFailure(code);}
function attempt<A>(f:()=>A,fallback:SessionCode="invalid_source"):Effect.Effect<A,SessionFailure>{return Effect.try({try:f,catch:e=>sessionFailure(codeOf(e,fallback))});}
function safe<A,E,R>(work:Effect.Effect<A,E,R>,fallback:SessionCode,cleanupOwned:()=>boolean=()=>true):Effect.Effect<A,SessionFailure,R>{
 return Effect.uninterruptibleMask(restore=>restore(work).pipe(Effect.catchCause(cause=>{
  if(cleanupOwned()&&cause.reasons.some(r=>(r._tag==="Fail"||r._tag==="Die")&&codeOf(r._tag==="Fail"?r.error:r.defect,fallback)==="cleanup_failed"))return Effect.fail(sessionFailure("cleanup_failed"));
  if(cause.reasons.some(r=>r._tag==="Interrupt"))return Effect.failCause(Cause.fromReasons<never>(cause.reasons.flatMap(r=>r._tag==="Interrupt"?[Cause.makeInterruptReason(r.fiberId)]:[])));
  const f=cause.reasons.find(r=>r._tag==="Fail"),code=f?._tag==="Fail"?codeOf(f.error,fallback):fallback;return Effect.fail(sessionFailure(code==="cleanup_failed"&&!cleanupOwned()?fallback:code));
 })));
}
type Json=null|boolean|number|string|readonly Json[]|{readonly [key:string]:Json};
function object(v:unknown,keys?:readonly string[]):Record<string,unknown>{
 if(v===null||typeof v!=="object"||Array.isArray(v))reject("invalid_source");
 const o:Record<string,unknown>=Object.fromEntries(Object.entries(v));
 if(keys&&(Object.keys(o).length!==keys.length||keys.some(k=>!Object.hasOwn(o,k))))reject("invalid_source");return o;
}
function unicodeSize(s:string,max:number):number{let n=0;for(let i=0;i<s.length;i++){const c=s.charCodeAt(i);if(c===0)reject("invalid_source");if(c>=0xd800&&c<=0xdbff){const d=s.charCodeAt(++i);if(!(d>=0xdc00&&d<=0xdfff))reject("invalid_source");n+=4;}else if(c>=0xdc00&&c<=0xdfff)reject("invalid_source");else n+=c<128?1:c<2048?2:3;if(n>max)reject("candidate_limit_exceeded");}return n;}
function text(v:unknown,max=512):string{if(typeof v!=="string"||v.length===0)reject("invalid_source");unicodeSize(v,max);return v;}
/** Projection-only parser: closed root, duplicate escaped keys and bounded canonical
 * small integer tokens are checked before Number. Personal codec validates its record.
 */
function parse(raw:unknown):{fields:Record<string,unknown>;recordRaw:string}{
 if(typeof raw!=="string")reject("invalid_source");unicodeSize(raw,65536);let at=0,nodes=0,recordRaw="";
 const white=()=>{while(at<raw.length&&" \t\r\n".includes(raw[at]!))at++;};
 const string=():string=>{const start=at++;let slash=false;while(at<raw.length){const c=raw.charCodeAt(at++);if(c===34&&!slash){const v:unknown=JSON.parse(raw.slice(start,at));if(typeof v!=="string")reject("invalid_source");unicodeSize(v,65536);return v;}if(c<32)reject("invalid_source");if(slash){slash=false;continue;}if(c===92)slash=true;}return reject("invalid_source");};
 const value=(depth:number):Json=>{if(depth>32||++nodes>4096)reject("candidate_limit_exceeded");white();const c=raw[at];
  if(c==='"')return string();if(c==="{"){at++;white();const entries:[string,Json][]=[],seen=new Set<string>();if(raw[at]==="}"){at++;return {};}
   while(true){if(raw[at]!=='"')reject("invalid_source");const k=string();if(seen.has(k))reject("invalid_source");seen.add(k);white();if(raw[at++]!==":")reject("invalid_source");white();const begin=at;const v=value(depth+1);if(depth===0&&k==="record")recordRaw=raw.slice(begin,at);entries.push([k,v]);white();const end=raw[at++];if(end==="}")break;if(end!==",")reject("invalid_source");white();}return Object.fromEntries(entries);}
  if(c==="["){at++;white();const xs:Json[]=[];if(raw[at]==="]"){at++;return xs;}while(true){xs.push(value(depth+1));white();const end=raw[at++];if(end==="]")break;if(end!==",")reject("invalid_source");}return xs;}
  for(const [word,v]of [["true",true],["false",false],["null",null]] satisfies readonly (readonly [string,Json])[]){if(raw.slice(at,at+word.length)===word){at+=word.length;return v;}}
  const start=at;while(at<raw.length&&!" ,]}\t\r\n".includes(raw[at]!))at++;const token=raw.slice(start,at);if(!/^(0|-?[1-9][0-9]*)$/.test(token)||token.length>16)reject("invalid_source");const integer=BigInt(token);if(integer>9007199254740991n||integer< -9007199254740991n)reject("invalid_source");return Number(integer);
 };const parsed=value(0);white();if(at!==raw.length)reject("invalid_source");return {fields:object(parsed,["record","original_end","clock_basis","native_algorithm","local_start_text","source_utc_offset"]),recordRaw};
}
interface Rational {n:bigint;d:bigint}
function bits(v:unknown):Rational{if(typeof v!=="string"||!/^[0-9a-f]{16}$/.test(v))reject("invalid_source");const b=BigInt("0x"+v),e=Number((b>>52n)&2047n),f=b&((1n<<52n)-1n);if(e===2047)reject("invalid_source");let n=e===0?f:(1n<<52n)+f;const power=e===0?-1074:e-1023-52;if(b>>63n)n=-n;return power>=0?{n:n<<BigInt(power),d:1n}:{n,d:1n<<BigInt(-power)};}
function instant(v:unknown):Rational{const o=object(v);let r:Rational;if(o.representation==="binary64_epoch_seconds")r=bits(o.bits);else if(o.representation==="seconds_nanos"){
 const decimal=text(o.epoch_seconds,20);if(!/^(0|-?[1-9][0-9]*)$/.test(decimal))reject("invalid_source");const n=BigInt(decimal);if(n< -9223372036854775808n||n>9223372036854775807n||typeof o.nanoseconds!=="number"||!Number.isInteger(o.nanoseconds)||o.nanoseconds<0||o.nanoseconds>999999999)reject("invalid_source");r={n:n*1000000000n+BigInt(o.nanoseconds),d:1000000000n};
 }else return reject("invalid_source");if(o.epoch==="apple_reference_2001")r={n:r.n+978307200n*r.d,d:r.d};else if(o.epoch!=="unix")reject("invalid_source");return r;}
function compare(a:Rational,b:Rational):bigint{return a.n*b.d-b.n*a.d;}
const whitelist=["record","original_end","clock_basis","native_algorithm","local_start_text","source_utc_offset"];
type ValidatedDescriptor=Omit<SessionSourceDescriptor,"source_evidence_ref">&{readonly source_evidence_ref:SourceEvidenceReference};
function descriptor(d:SessionSourceDescriptor,b:TrustedSessionBinding):ValidatedDescriptor{
 const o=object(d,["dataset_id","source_id","source_revision","source_evidence_ref","app_identity","authoritative_app_class","declared_projection_app_class","admitted_fields","forbidden_detail_present"]);
 if(o.dataset_id!==b.dataset_id||o.source_id!==b.source_id||o.source_revision!==b.source_revision)reject("invalid_source");
 const ref=object(o.source_evidence_ref,["state","value"]);if(ref.state!=="known")reject("invalid_source");const value=text(ref.value,256);const app=text(o.app_identity);
 const suppliedFields=o.admitted_fields;if(!Array.isArray(suppliedFields)||suppliedFields.length!==6||whitelist.some((k,i)=>suppliedFields[i]!==k))reject("invalid_source");
 const allowed=["browser","non_browser","unknown"];if(!allowed.includes(d.authoritative_app_class)||!allowed.includes(d.declared_projection_app_class))reject("invalid_source");
 if(d.authoritative_app_class!==d.declared_projection_app_class||!Array.isArray(o.forbidden_detail_present)||o.forbidden_detail_present.length!==0)reject("scope_not_authorized");
 const fields:SessionSourceDescriptor["admitted_fields"]=["record","original_end","clock_basis","native_algorithm","local_start_text","source_utc_offset"];const result:ValidatedDescriptor={dataset_id:b.dataset_id,source_id:b.source_id,source_revision:b.source_revision,source_evidence_ref:{state:"known",value},app_identity:app,authoritative_app_class:d.authoritative_app_class,declared_projection_app_class:d.declared_projection_app_class,admitted_fields:Object.freeze(fields),forbidden_detail_present:Object.freeze([])};Object.freeze(result.source_evidence_ref);return Object.freeze(result);
}
interface Prepared {metadata:ProjectionMetadata;status:SessionStatusWrapper;recordRaw:string|null}
function prepare(raw:unknown,d:ValidatedDescriptor,b:TrustedSessionBinding):Prepared{
 const parsed=parse(raw),f=parsed.fields,r=object(f.record),lineage=object(r.lineage),p=object(r.payload),app=object(p.app),appIdentity=object(app.identity);
 if(r.domain!=="device_usage"||r.payload_kind!=="foreground_app_session"||lineage.dataset_id!==b.dataset_id||lineage.source_id!==b.source_id||lineage.source_revision!==b.source_revision||lineage.purpose!==b.purpose||appIdentity.state!=="known"||appIdentity.value!==d.app_identity||app.app_class!==d.authoritative_app_class)reject("scope_not_authorized");
 const duration=object(p.duration);if(duration.representation!=="binary64"||duration.unit!=="second")reject("invalid_source");const measured=bits(duration.bits),start=instant(object(p.start).instant);
 if(f.original_end!=="present"&&f.original_end!=="absent")reject("invalid_source");if(f.clock_basis!=="synthetic_observation"&&f.clock_basis!=="native_source_arithmetic")reject("invalid_source");
 if((f.clock_basis==="synthetic_observation")!==(b.clock_profile==="synthetic-v1")||p.duration_basis!==f.clock_basis)reject("scope_not_authorized");
 let status:ProjectionMetadata["status"]="canonical_session";
 if(f.original_end==="absent")status="unknown_original_end";else {const end=instant(object(p.end).instant);
  if(compare(start,end)>0||measured.n<0n)status="clock_inconsistent";else if(f.clock_basis==="native_source_arithmetic")status="outside_clock_profile";
  else if((end.n*start.d-start.n*end.d)*measured.d!==measured.n*end.d*start.d)status="duration_disagreement";
 }
 const canonical=status==="canonical_session";
 const reason=status==="clock_inconsistent"?"clock_inconsistent":status==="duration_disagreement"?"invalid_exact_value":"unsupported_shape";
 const wrapper:SessionStatusWrapper=Object.freeze({record_ref:text(r.record_id),canonical_status:canonical?"valid":status==="unknown_original_end"?"unavailable":"outside_canonical",reason_codes:Object.freeze(canonical?[]:[reason]),source_evidence_ref:d.source_evidence_ref});
 return {metadata:Object.freeze({status,canonical,original_end:f.original_end==="absent"?"unknown":"present",fabricated_observed_end:false,discard_under_two:false,cleanup_ACK:true}),status:wrapper,recordRaw:canonical?parsed.recordRaw:null};
}
interface Entry {metadata:ProjectionMetadata;status:SessionStatusWrapper;record:OwnedPersonalRecord|null}
export function createSessionProjector(trusted:Parameters<SessionProjectorFactory["create"]>[0]):Effect.Effect<SessionProjector,SessionFailure,Scope.Scope>{
 return Effect.gen(function*(){
  let live=true,poisoned=false,busy=false;const waiters=new Set<(e:Effect.Effect<void>)=>void>();
  const closed=Effect.callback<void>(resume=>{if(!live){resume(Effect.void);return;}waiters.add(resume);return Effect.sync(()=>{waiters.delete(resume);});});
  yield* Effect.addFinalizer(()=>Effect.sync(()=>{live=false;const pending=[...waiters];waiters.clear();for(const resume of pending)resume(Effect.void);}));
  const lifetime:OriginalLifetime=Object.freeze({isLive:()=>live&&!poisoned,closed});
  const binding=Object.freeze({...trusted.binding}),current=trusted.current.check.bind(trusted.current),describe=trusted.descriptor.describe.bind(trusted.descriptor),withOriginal=trusted.source.withOriginal.bind(trusted.source),decode=trusted.codec.decode.bind(trusted.codec),encode=trusted.codec.encode.bind(trusted.codec);
  const originals=new WeakSet<object>(),projections=new WeakMap<object,Entry>();
  const alive=()=>{if(poisoned)reject("cleanup_failed");if(!live)reject("owned_handoff_closed");};
  const check=(phase:ProjectionPhase):Effect.Effect<void,SessionFailure>=>Effect.uninterruptibleMask(restore=>Effect.gen(function*(){yield* attempt(alive);const exit=yield* Effect.exit(restore(safe(Effect.suspend(()=>current(binding,phase)),"scope_not_authorized")));if(exit._tag==="Failure"&&exit.cause.reasons.some(r=>r._tag==="Interrupt"||r._tag==="Fail"&&r.error.code==="cleanup_failed"))return yield* Effect.failCause(exit.cause);yield* attempt(alive);if(exit._tag==="Failure")return yield* Effect.failCause(exit.cause);}));
  const view:ProjectionView=Object.freeze({read(input:unknown){return Effect.suspend(()=>{
   if(!live||poisoned||input===null||(typeof input!=="object"&&typeof input!=="function")||!projections.has(input))return Effect.succeed(null);
   return check("before_read").pipe(Effect.andThen(attempt(()=>live&&!poisoned?projections.get(input)!:null)));
  });}});
  const project=(request:unknown):Effect.Effect<OwnedSessionProjection,SessionFailure>=>Effect.uninterruptibleMask(restore=>Effect.gen(function*(){
   yield* attempt(()=>{alive();const wanted='{"version":1,"source_binding":"'+binding.source_id+'","clock_profile":"'+binding.clock_profile+'"}';if(typeof request!=="string"||request!==wanted)reject("invalid_request");if(busy)reject("candidate_limit_exceeded");busy=true;},"invalid_request");
   const work=Effect.gen(function*(){
    yield* check("before_allocation");let allocated:OwnedOriginal|null=null,used=false,issuerLive=true;
    const issuer:OriginalIssuer=Object.freeze({commit(){if(!issuerLive||allocated||!lifetime.isLive())return null;const t:OwnedOriginal={[originalBrand]:true};Object.freeze(t);originals.add(t);allocated=t;return t;}});
    const use=(ticket:OwnedOriginal,originalView:OriginalView):Effect.Effect<Prepared,SessionFailure>=>Effect.gen(function*(){
     yield* attempt(()=>{alive();if(used||ticket!==allocated||ticket===null||typeof ticket!=="object"||!originals.has(ticket))reject("invalid_source");used=true;});
     yield* check("before_original");yield* check("before_original");const descRaw=yield* safe(Effect.suspend(()=>describe(binding)),"source_failed");yield* check("before_original");const desc=yield* attempt(()=>descriptor(descRaw,binding));
     const read=originalView.read.bind(originalView);const raw=yield* safe(Effect.suspend(()=>read(ticket)),"source_failed");yield* check("before_original");yield* check("before_decode");return yield* attempt(()=>prepare(raw,desc,binding));
    });
    const prepared=yield* safe(Effect.suspend(()=>withOriginal(lifetime,issuer,use)).pipe(Effect.ensuring(Effect.sync(()=>{issuerLive=false;}))),"source_failed",()=>allocated!==null);
    yield* attempt(()=>{alive();if(!used||allocated===null)reject("invalid_source");});yield* check("before_publication");
    let record:OwnedPersonalRecord|null=null;
    if(prepared.recordRaw!==null){const decoded=yield* attempt(()=>decode(prepared.recordRaw));if(Result.isFailure(decoded))return yield* Effect.fail(sessionFailure(decoded.failure.code==="scope_not_authorized"?"scope_not_authorized":"invalid_source"));record=decoded.success;yield* check("before_publication");const encoded=yield* attempt(()=>encode(record));if(Result.isFailure(encoded))return yield* Effect.fail(sessionFailure(encoded.failure.code==="scope_not_authorized"?"scope_not_authorized":"invalid_source"));}
    yield* check("before_publication");const projection:OwnedSessionProjection={[projectionBrand]:true};Object.freeze(projection);projections.set(projection,Object.freeze({metadata:prepared.metadata,status:prepared.status,record}));return projection;
   });
   return yield* restore(work).pipe(Effect.catchCause(cause=>{if(cause.reasons.some(r=>(r._tag==="Fail"||r._tag==="Die")&&codeOf(r._tag==="Fail"?r.error:r.defect,"source_failed")==="cleanup_failed"))poisoned=true;return Effect.failCause(cause);}),Effect.ensuring(Effect.sync(()=>{busy=false;})));
  }));
  return Object.freeze({project,view});
 });
}
