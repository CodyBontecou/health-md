/** Private coverage-only contract. Source grants/native profile/consumer admission are separate. */
import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import type * as Scope from "effect/Scope";
import type { NativeTypedProfile, UnknownJson } from "./typed-values.js";
const contractBrand: unique symbol = Symbol("CoverageContract");
const requestBrand: unique symbol = Symbol("CoverageRead");
const scalarBrand: unique symbol = Symbol("CoverageScalar");
const rangeBrand: unique symbol = Symbol("CoverageCivil");
export interface OwnedCoverageRequest { readonly [contractBrand]: "request" }
export interface OwnedCoverageResponse { readonly [contractBrand]: "response" }
export interface OwnedContractReadRequest { readonly [requestBrand]: true }
export interface OwnedContractScalar { readonly [scalarBrand]: true }
export interface OwnedCivilDecision { readonly [rangeBrand]: true }
export type Code = "invalid_request" | "invalid_response" | "unsupported_operation" | "invalid_page_controls" | "invalid_date_range" | "private_profile_unavailable" | "native_profile_unavailable" | "private_contract_limit" | "not_authorized" | "owned_handoff_closed" | "private_contract_busy";
export interface FixedContractFailure { readonly _tag: "CoverageContractFailure"; readonly code: Code }
export type Status = "available" | "complete_empty" | "partial" | "failed" | "unsupported" | "skipped" | "cancelled" | "not_requested" | "legacy_unavailable" | "redacted" | "not_synchronized";
export interface CivilRange { readonly start_date: string; readonly end_date: string }
export type MetricSelection = { readonly type: "all_available" } | { readonly type: "explicit"; readonly metric_ids: readonly string[] };
export type SourceSelection = { readonly type: "all_available" } | { readonly type: "explicit"; readonly source_ids: readonly string[]; readonly provider_ids: readonly string[] };
export type DateSelection = { readonly type: "all_available" } | { readonly type: "exact"; readonly range: CivilRange };
/** Decimal fields retain Swift Int values exactly; String dates remain unvalidated at raw decode. */
export interface CoverageRequestView { readonly schema: string; readonly schema_version: string; readonly metrics: MetricSelection; readonly sources: SourceSelection; readonly dates: DateSelection; readonly operation: { readonly type: "coverage" }; readonly page: { readonly max_items: string; readonly max_bytes: string; readonly cursor?: string } }
export interface CoverageView { readonly requested_range?: CivilRange; readonly available_range?: CivilRange; readonly status: Status; readonly days_considered: string; readonly days_with_values: string; readonly missing: readonly { readonly range: CivilRange; readonly status: Status; readonly reason?: string }[]; readonly missing_interval_count?: string; readonly missing_truncated?: boolean }
export interface CoverageResponseView { readonly schema: string; readonly schema_version: string; readonly items: readonly []; readonly coverage: CoverageView; readonly sources: readonly { readonly schema: string; readonly schema_version: string; readonly digest: string }[]; readonly evidence: readonly []; readonly limitations: readonly { readonly code: string; readonly message: string }[]; readonly metadata?: Extract<UnknownJson, { readonly kind: "object" }> }
export type Phase = "before_decode" | "after_profile" | "before_admission" | "before_read" | "before_encode" | "before_construction" | "before_publication" | "after_callback";
export interface CapturedContractCurrent { check(phase: Phase): Effect.Effect<void, FixedContractFailure> }
/** Issuer validates primitive kind/payload only after exact own slot/lifetime check. No source grant. */
export interface ContractProfileIssuer {
 issueNumber(slot: unknown, kind: "i64" | "u64" | "f64", payload: unknown): OwnedContractScalar | null;
 issueCivil(slot: unknown, start: unknown, end: unknown, accepted: unknown): OwnedCivilDecision | null;
}
/** Explicit composition: no tagged wrapper, no duplicated number algorithm. Adapter implementation/admission is a later native-profile proof. */
export interface ContractSourceProfile {
 number(raw: string, context: "swift_Int" | "unknown_JSON", slot: unknown, issuer: ContractProfileIssuer): Effect.Effect<OwnedContractScalar, FixedContractFailure>;
 civilRange(start: string, end: string, slot: unknown, issuer: ContractProfileIssuer): Effect.Effect<OwnedCivilDecision, FixedContractFailure>;
 readonly canonicalNumber: NativeTypedProfile["canonicalNumber"];
 readonly duplicateDecodedKey: NativeTypedProfile["duplicateDecodedKey"];
}
export interface CoverageReadView {
 readRequest(request: unknown, value: unknown): Effect.Effect<CoverageRequestView | null, FixedContractFailure>;
 readResponse(request: unknown, value: unknown): Effect.Effect<CoverageResponseView | null, FixedContractFailure>;
 encode(request: unknown, value: unknown): Effect.Effect<string | null, FixedContractFailure>;
}
export interface CoverageContractFactory {
 decodeRequest(representation: unknown, payload: unknown): Effect.Effect<OwnedCoverageRequest, FixedContractFailure>;
 admitRequest(value: unknown): Effect.Effect<OwnedCoverageRequest, FixedContractFailure>;
 decodeResponse(representation: unknown, payload: unknown): Effect.Effect<OwnedCoverageResponse, FixedContractFailure>;
 constructResponse(value: unknown): Effect.Effect<OwnedCoverageResponse, FixedContractFailure>;
 withRequest<A,E>(value: unknown, callback: (request: OwnedContractReadRequest, view: CoverageReadView) => Effect.Effect<A,E>): Effect.Effect<A | null,E | FixedContractFailure>;
 withResponse<A,E>(value: unknown, callback: (request: OwnedContractReadRequest, view: CoverageReadView) => Effect.Effect<A,E>): Effect.Effect<A | null,E | FixedContractFailure>;
}

const codes: readonly Code[] = ["invalid_request","invalid_response","unsupported_operation","invalid_page_controls","invalid_date_range","private_profile_unavailable","native_profile_unavailable","private_contract_limit","not_authorized","owned_handoff_closed","private_contract_busy"];
const ownFailures = new WeakMap<object, Code>();
function failure(code: Code): FixedContractFailure { const f = Object.freeze({_tag:"CoverageContractFailure" as const,code}); ownFailures.set(f,code); return f; }
function reject(code: Code): never { throw failure(code); }
function object(v: unknown): v is object { return typeof v === "object" && v !== null; }
function portCode(value: unknown, fallback: Code): Code {
 if (!object(value)) return fallback;
 const own = ownFailures.get(value); if (own) return own;
 try { const ds=Object.getOwnPropertyDescriptors(value); const keys=Object.keys(ds); const tag=ds._tag; const code=ds.code;
  if(keys.length!==2 || !tag || !code || !("value" in tag) || !("value" in code) || tag.value!=="CoverageContractFailure") return fallback;
  const c:unknown=code.value; return typeof c==="string" && codes.some(x=>x===c)?codes.find(x=>x===c)!:fallback;
 } catch { return fallback; }
}
function attempt<A>(work:()=>A, fallback:Code="invalid_request"):Effect.Effect<A,FixedContractFailure> { return Effect.try({try:work,catch:e=>failure(object(e)?ownFailures.get(e)??fallback:fallback)}); }
function utf8(text:string,limit:number):number {
 let bytes=0;
 for(let i=0;i<text.length;i++){const x=text.charCodeAt(i); if(x>=0xd800&&x<=0xdbff){const y=text.charCodeAt(++i);if(!(y>=0xdc00&&y<=0xdfff))reject("invalid_request");bytes+=4;}else if(x>=0xdc00&&x<=0xdfff)reject("invalid_request");else bytes+=x<128?1:x<2048?2:3;if(bytes>limit)reject("private_contract_limit");}
 return bytes;
}
function hexInput(text:string):string {
 if(text.length>131072)reject("private_contract_limit");if(!/^(?:[0-9a-f]{2})*$/.test(text))reject("invalid_request");
 const bytes:number[]=[];for(let i=0;i<text.length;i+=2)bytes.push(parseInt(text.slice(i,i+2),16));let out="";
 for(let i=0;i<bytes.length;){const x=bytes[i++]!;let c=x,n=0,min=0;
  if(x>=0xc2&&x<=0xdf){c=x&31;n=1;min=128;}else if(x>=0xe0&&x<=0xef){c=x&15;n=2;min=2048;}else if(x>=0xf0&&x<=0xf4){c=x&7;n=3;min=65536;}else if(x>=128)reject("invalid_request");
  for(let j=0;j<n;j++){const y=bytes[i++];if(y===undefined||(y&192)!==128)reject("invalid_request");c=c*64+(y&63);}
  if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff))reject("invalid_request");out+=String.fromCodePoint(c);
 }return out;
}
type Node = {readonly kind:"string";readonly start:number;readonly end:number}|{readonly kind:"number";readonly start:number;readonly end:number}|{readonly kind:"null"}|{readonly kind:"boolean";readonly value:boolean}|{readonly kind:"array";readonly values:readonly Node[]}|{readonly kind:"object";readonly entries:readonly (readonly [string,Node])[]};
type Frame={readonly wire:string;readonly root:Node};
/** Retains raw numeric lexemes and value-string spans. Ignored value strings are never decoded. */
function scan(representation:unknown,payload:unknown):Frame {
 if(typeof representation!=="string"||typeof payload!=="string")reject("invalid_request");
 let wire:string;if(representation==="utf8")wire=payload;else if(representation==="utf8_hex")wire=hexInput(payload);else reject("invalid_request");
 if(wire.length>65536)reject("private_contract_limit");utf8(wire,65536);let at=0,nodes=0;
 const bad:()=>never=()=>reject("invalid_request");const ws=()=>{while(at<wire.length&&/[ \t\n\r]/.test(wire[at]!))at++;};
 const string=(decode:boolean):string=>{if(wire[at++]!=='"')bad();let out="",bytes=0;
  while(at<wire.length){let c=wire.charCodeAt(at++);if(c===34)return out;if(c<32)bad();
   if(c===92){const e=wire[at++];const short:Readonly<Record<string,number>>={'"':34,'\\':92,'/':47,b:8,f:12,n:10,r:13,t:9};
    if(e==="u"){const part=wire.slice(at,at+4);if(!/^[0-9a-fA-F]{4}$/.test(part))bad();at+=4;c=parseInt(part,16);
     if(c>=0xd800&&c<=0xdbff){if(wire.slice(at,at+2)!=='\\u')bad();at+=2;const low=wire.slice(at,at+4);if(!/^[0-9a-fA-F]{4}$/.test(low))bad();at+=4;const y=parseInt(low,16);if(y<0xdc00||y>0xdfff)bad();c=65536+(c-0xd800)*1024+y-0xdc00;}else if(c>=0xdc00&&c<=0xdfff)bad();
    }else{if(e===undefined||short[e]===undefined)bad();c=short[e]!;}
   }else if(c>=0xd800&&c<=0xdbff){const y=wire.charCodeAt(at++);if(!(y>=0xdc00&&y<=0xdfff))bad();c=65536+(c-0xd800)*1024+y-0xdc00;}else if(c>=0xdc00&&c<=0xdfff)bad();
   bytes+=c<128?1:c<2048?2:c<65536?3:4;if(bytes>8192)reject("private_contract_limit");if(decode)out+=String.fromCodePoint(c);
  }return bad();};
 const visit=(depth:number):Node=>{ws();if(++nodes>4096)reject("private_contract_limit");const c=wire[at];
  if(c==='"'){const start=at;string(false);return{kind:"string",start,end:at};}
  if(c==='{'||c==='['){if(depth>32)reject("private_contract_limit");at++;ws();
   if(c==='['){const values:Node[]=[];if(wire[at]===']'){at++;return{kind:"array",values};}while(true){values.push(visit(depth+1));ws();if(wire[at++]==']')break;if(wire[at-1]!==',')bad();}return{kind:"array",values};}
   const entries:(readonly[string,Node])[]=[];if(wire[at]==='}'){at++;return{kind:"object",entries};}while(true){ws();const key=string(true);ws();if(wire[at++]!==':')bad();entries.push([key,visit(depth+1)]);ws();if(wire[at++]==='}')break;if(wire[at-1]!==',')bad();}return{kind:"object",entries};
  }
  for(const [literal,value] of [["null",null],["true",true],["false",false]] as const){if(wire.slice(at,at+literal.length)===literal){at+=literal.length;return value===null?{kind:"null"}:{kind:"boolean",value};}}
  const start=at;const m= /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(wire.slice(at));if(!m)bad();at+=m[0].length;if(at-start>1024)reject("private_contract_limit");return{kind:"number",start,end:at};
 };const root=visit(1);ws();if(at!==wire.length)bad();return{wire,root};
}
/** Called only on a scanner-owned string span after authority checks; never a native numeric parser. */
function text(frame:Frame,node:Node|undefined):string {if(node?.kind!=="string")reject("invalid_request");let out="";const raw=frame.wire.slice(node.start+1,node.end-1);
 for(let i=0;i<raw.length;i++){const c=raw[i]!;if(c!=='\\'){out+=c;continue;}const e=raw[++i]!;if(e==='u'){out+=String.fromCharCode(parseInt(raw.slice(i+1,i+5),16));i+=4;}else{const map:Readonly<Record<string,string>>={'"':'"','\\':'\\','/':'/',b:'\b',f:'\f',n:'\n',r:'\r',t:'\t'};out+=map[e]!;}}return out;
}
function quoted(s:string):string {let out='"';for(const ch of s){const c=ch.charCodeAt(0);if(ch==='"'||ch==='\\')out+='\\'+ch;else if(c<32){const short:Readonly<Record<number,string>>={8:'b',9:'t',10:'n',12:'f',13:'r'};out+=short[c]?'\\'+short[c]:'\\u'+c.toString(16).padStart(4,'0');}else out+=ch;}return out+'"';}
function decimal(kind:"i64"|"u64", value:unknown):value is string { if(typeof value!=="string"||value.length>20||!/^(?:0|-?[1-9][0-9]*)$/.test(value))return false;const n=BigInt(value);return kind==="i64"?n>=-(1n<<63n)&&n<(1n<<63n):n>=0n&&n<(1n<<64n); }
function finiteBits(value:unknown):value is string { return typeof value==="string"&&/^[0-9a-f]{16}$/.test(value)&&(parseInt(value.slice(0,3),16)&0x7ff)!==0x7ff; }
function freeze<T>(value:T):T { if(object(value)){for(const child of Object.values(value))freeze(child);Object.freeze(value);}return value; }
const statuses:readonly Status[]=["available","complete_empty","partial","failed","unsupported","skipped","cancelled","not_requested","legacy_unavailable","redacted","not_synchronized"];
const otherOperations=["metric_series","period_comparison","workout_listing","sleep_session_listing","workout_sleep_alignment","source_record_listing","derive_packet"];
type Scalar = {readonly kind:"i64"|"u64";readonly decimal:string}|{readonly kind:"f64";readonly bits:string};
type Stored = {readonly kind:"request";readonly view:CoverageRequestView}|{readonly kind:"response";readonly view:CoverageResponseView};
function quoted(value:string):string { let out='"';for(const ch of value){const c=ch.charCodeAt(0);if(ch==='"'||ch==='\\')out+='\\'+ch;else if(c<32){const short:Readonly<Record<number,string>>={8:'b',9:'t',10:'n',12:'f',13:'r'};out+=short[c]?'\\'+short[c]:'\\u'+c.toString(16).padStart(4,'0');}else out+=ch;}return out+'"'; }
function sorted<T>(items:readonly T[],key:(v:T)=>string):T[] { return [...items].sort((a,b)=>key(a)<key(b)?-1:key(a)>key(b)?1:0); }

export function createCoverageContractFactory(current:CapturedContractCurrent, profile:ContractSourceProfile):Effect.Effect<CoverageContractFactory,FixedContractFailure,Scope.Scope> {
 return Effect.gen(function*(){
  let live=true,busy=false;const waiters=new Set<(e:Effect.Effect<void>)=>void>();
  const closed=Effect.callback<void>(resume=>{if(!live){resume(Effect.void);return;}waiters.add(resume);return Effect.sync(()=>{waiters.delete(resume);});});
  yield* Effect.addFinalizer(()=>Effect.sync(()=>{live=false;const all=[...waiters];waiters.clear();for(const resume of all)resume(Effect.void);}));
  const currentCheck=current.check.bind(current), number=profile.number.bind(profile), civil=profile.civilRange.bind(profile), canonical=profile.canonicalNumber.bind(profile), duplicate=profile.duplicateDecodedKey.bind(profile);
  const values=new WeakMap<object,Stored>(), requests=new WeakMap<object,{readonly token:object;readonly context:object}>();
  const scalars=new WeakMap<object,{readonly slot:object;readonly context:object;readonly scalar:Scalar}>();
  const decisions=new WeakMap<object,{readonly slot:object;readonly context:object;readonly start:string;readonly end:string;readonly accepted:boolean}>();
  const alive=()=>{if(!live)reject("owned_handoff_closed");};
  const sanitize=<A,E,R>(work:Effect.Effect<A,E,R>,fallback:Code):Effect.Effect<A,FixedContractFailure,R>=>Effect.uninterruptibleMask(restore=>restore(work).pipe(Effect.catchCause(cause=>{
   if(cause.reasons.some(r=>r._tag==="Interrupt"))return Effect.interrupt;
   if(!live)return Effect.fail(failure("owned_handoff_closed"));const f=cause.reasons.find(r=>r._tag==="Fail");return Effect.fail(failure(f?._tag==="Fail"?portCode(f.error,fallback):fallback));
  })));
  const supervised=<A,E,R>(work:Effect.Effect<A,E,R>,fallback:Code):Effect.Effect<A,FixedContractFailure,R>=>sanitize(Effect.raceFirst(work,closed.pipe(Effect.flatMap(()=>Effect.fail(failure("owned_handoff_closed"))))),fallback);
  const check=(phase:Phase):Effect.Effect<void,FixedContractFailure>=>Effect.gen(function*(){yield* attempt(alive);yield* supervised(Effect.suspend(()=>currentCheck(phase)),"not_authorized");yield* attempt(alive);});
  const exclusive=<A,E>(work:()=>Effect.Effect<A,E>):Effect.Effect<A,E|FixedContractFailure>=>Effect.uninterruptibleMask(restore=>Effect.gen(function*(){yield* attempt(()=>{alive();if(busy)reject("private_contract_busy");busy=true;});return yield* restore(Effect.suspend(work)).pipe(Effect.ensuring(Effect.sync(()=>{busy=false;})));}));
  const fields=(frame:Frame,node:Node|undefined,code:Code,allowed?:readonly string[]):Effect.Effect<ReadonlyMap<string,Node>,FixedContractFailure>=>Effect.gen(function*(){
   if(node?.kind!=="object")return yield* Effect.fail(failure(code));const map=new Map<string,Node>();
   // Closed key admission precedes known/excluded payload materialization.
   if(allowed&&node.entries.some(([k])=>!allowed.includes(k)))return yield* Effect.fail(failure(code));
   for(const [key,value]of node.entries){if(map.has(key)){
    yield* check("before_decode");const policy=yield* attempt(()=>{alive();const r=duplicate(frame.wire,key);alive();if(Result.isFailure(r))reject("native_profile_unavailable");if(r.success!=="first"&&r.success!=="last"&&r.success!=="reject")reject("native_profile_unavailable");return r.success;},"native_profile_unavailable");yield* check("after_profile");
    if(policy==="reject")return yield* Effect.fail(failure("native_profile_unavailable"));if(policy==="first")continue;
   }map.set(key,value);}return map;
  });
  const str=(frame:Frame,node:Node|undefined,code:Code):string=>{if(node?.kind!=="string")reject(code);return text(frame,node);};
  const arr=(node:Node|undefined,code:Code):readonly Node[]=>{if(node?.kind!=="array")reject(code);return node.values;};
  const optional=(map:ReadonlyMap<string,Node>,key:string):Node|undefined=>{const n=map.get(key);return n?.kind==="null"?undefined:n;};
  const nativeScalar=(frame:Frame,node:Node|undefined,context:"swift_Int"|"unknown_JSON",code:Code):Effect.Effect<Scalar,FixedContractFailure>=>Effect.gen(function*(){
   if(node?.kind!=="number")return yield* Effect.fail(failure(code));const raw=frame.wire.slice(node.start,node.end);yield* check("before_decode");
   const slot=Object.freeze({}),ctx=Object.freeze({});let active=true;
   const issuer:ContractProfileIssuer=Object.freeze({issueNumber:(s:unknown,kind:"i64"|"u64"|"f64",payload:unknown)=>{
    if(s!==slot||!active||!live)return null;let scalar:Scalar;
    if(kind==="f64"){if(context==="swift_Int"||!finiteBits(payload))return null;scalar={kind,bits:payload};}
    else {if((kind!=="i64"&&kind!=="u64")||!decimal(kind,payload)||(context==="swift_Int"&&kind!=="i64"))return null;scalar={kind,decimal:payload};}
    const token=Object.freeze({[scalarBrand]:true as const});scalars.set(token,{slot,context:ctx,scalar:freeze(scalar)});return token;
   },issueCivil:()=>null});
   const returned=yield* supervised(Effect.suspend(()=>number(raw,context,slot,issuer)).pipe(Effect.ensuring(Effect.sync(()=>{active=false;}))),"native_profile_unavailable");
   const read=()=>{alive();if(!object(returned))reject("native_profile_unavailable");const s=scalars.get(returned);if(!s||s.slot!==slot||s.context!==ctx)reject("native_profile_unavailable");return s.scalar;};
   const scalar=yield* attempt(read,"native_profile_unavailable");yield* check("after_profile");yield* attempt(read,"native_profile_unavailable");return scalar;
  });
  const int=(frame:Frame,node:Node|undefined,code:Code):Effect.Effect<string,FixedContractFailure>=>Effect.gen(function*(){const s=yield* nativeScalar(frame,node,"swift_Int",code);if(s.kind!=="i64")return yield* Effect.fail(failure("native_profile_unavailable"));return s.decimal;});
  const range=(frame:Frame,node:Node|undefined,code:Code):Effect.Effect<CivilRange,FixedContractFailure>=>Effect.gen(function*(){const f=yield* fields(frame,node,code,["start_date","end_date"]);return yield* attempt(()=>({start_date:str(frame,f.get("start_date"),code),end_date:str(frame,f.get("end_date"),code)}),code);});
  const stringIDs=(frame:Frame,node:Node|undefined,code:Code):readonly string[]=>{const ids=arr(node,code).map(n=>str(frame,n,code));if(new Set(ids).size!==ids.length)reject(code);return sorted(ids,x=>x);};
  const metrics=(frame:Frame,node:Node|undefined):Effect.Effect<MetricSelection,FixedContractFailure>=>Effect.gen(function*(){const f=yield* fields(frame,node,"invalid_request",["type","metric_ids"]);return yield* attempt<MetricSelection>(()=>{const type=str(frame,f.get("type"),"invalid_request");if(type==="all_available"){if(f.has("metric_ids"))reject("invalid_request");return{type};}if(type!=="explicit")reject("invalid_request");return{type,metric_ids:stringIDs(frame,f.get("metric_ids"),"invalid_request")};});});
  const sources=(frame:Frame,node:Node|undefined):Effect.Effect<SourceSelection,FixedContractFailure>=>Effect.gen(function*(){if(node===undefined||node.kind==="null")return{type:"all_available" as const};const f=yield* fields(frame,node,"invalid_request",["type","source_ids","provider_ids"]);return yield* attempt<SourceSelection>(()=>{const type=str(frame,f.get("type"),"invalid_request");if(type==="all_available"){if(f.has("source_ids")||f.has("provider_ids"))reject("invalid_request");return{type};}if(type!=="explicit")reject("invalid_request");const a=optional(f,"source_ids"),b=optional(f,"provider_ids");return{type,source_ids:a?stringIDs(frame,a,"invalid_request"):[],provider_ids:b?stringIDs(frame,b,"invalid_request"):[]};});});
  const dates=(frame:Frame,node:Node|undefined):Effect.Effect<DateSelection,FixedContractFailure>=>Effect.gen(function*(){const f=yield* fields(frame,node,"invalid_request",["type","range"]);const type=yield* attempt(()=>str(frame,f.get("type"),"invalid_request"));if(type==="all_available"){if(f.has("range"))return yield* Effect.fail(failure("invalid_request"));return{type:"all_available" as const};}if(type!=="exact")return yield* Effect.fail(failure("invalid_request"));return{type:"exact" as const,range:yield* range(frame,f.get("range"),"invalid_request")};});
  const decodeRequestView=(frame:Frame):Effect.Effect<CoverageRequestView,FixedContractFailure>=>Effect.gen(function*(){
   const f=yield* fields(frame,frame.root,"invalid_request",["schema","schema_version","metrics","sources","dates","operation","page"]);
   const op=yield* fields(frame,f.get("operation"),"invalid_request");const tag=yield* attempt(()=>str(frame,op.get("type"),"invalid_request"));
   if(otherOperations.includes(tag))return yield* Effect.fail(failure("private_profile_unavailable"));if(tag!=="coverage"||[...op.keys()].some(k=>k!=="type"))return yield* Effect.fail(failure("invalid_request"));
   const page=yield* fields(frame,f.get("page"),"invalid_request",["max_items","max_bytes","cursor"]);
   const schema=yield* attempt(()=>str(frame,f.get("schema"),"invalid_request"));const schema_version=yield* int(frame,f.get("schema_version"),"invalid_request");
   const m=yield* metrics(frame,f.get("metrics")),s=yield* sources(frame,f.get("sources")),d=yield* dates(frame,f.get("dates"));
   const max_items=yield* int(frame,page.get("max_items"),"invalid_request"),max_bytes=yield* int(frame,page.get("max_bytes"),"invalid_request");const cursor=optional(page,"cursor");
   return{schema,schema_version,metrics:m,sources:s,dates:d,operation:{type:"coverage"},page:{max_items,max_bytes,...(cursor?{cursor:yield* attempt(()=>str(frame,cursor,"invalid_request"))}:{})}};
  });
  const json=(frame:Frame,node:Node):Effect.Effect<UnknownJson,FixedContractFailure>=>Effect.gen(function*(){
   if(node.kind==="null")return{kind:"null"};if(node.kind==="boolean")return node;
   if(node.kind==="string")return{kind:"string",value:yield* attempt(()=>text(frame,node),"invalid_response")};
   if(node.kind==="number")return yield* nativeScalar(frame,node,"unknown_JSON","invalid_response");
   if(node.kind==="array"){const values:UnknownJson[]=[];for(const n of node.values)values.push(yield* json(frame,n));return{kind:"array",values};}
   const fieldsMap=yield* fields(frame,node,"invalid_response"),entries:(readonly[string,UnknownJson])[]=[];for(const k of sorted([...fieldsMap.keys()],x=>x))entries.push([k,yield* json(frame,fieldsMap.get(k)!)]);return{kind:"object",entries};
  });
  const availability=(frame:Frame,node:Node|undefined):Status=>{const s=str(frame,node,"invalid_response");const status=statuses.find(x=>x===s);if(!status)reject("invalid_response");return status;};
  const coverage=(frame:Frame,node:Node|undefined):Effect.Effect<CoverageView,FixedContractFailure>=>Effect.gen(function*(){
   const f=yield* fields(frame,node,"invalid_response");const status=yield* attempt(()=>availability(frame,f.get("status")),"invalid_response");
   const days_considered=yield* int(frame,f.get("days_considered"),"invalid_response"),days_with_values=yield* int(frame,f.get("days_with_values"),"invalid_response");
   const missing:CoverageView["missing"][number][]=[];const ns=yield* attempt(()=>arr(f.get("missing"),"invalid_response"),"invalid_response");
   for(const n of ns){const m=yield* fields(frame,n,"invalid_response"),r=yield* range(frame,m.get("range"),"invalid_response");const st=yield* attempt(()=>availability(frame,m.get("status")),"invalid_response"),reason=optional(m,"reason");missing.push({range:r,status:st,...(reason?{reason:yield* attempt(()=>str(frame,reason,"invalid_response"),"invalid_response")}:{})});}
   const rr=optional(f,"requested_range"),ar=optional(f,"available_range"),mc=optional(f,"missing_interval_count"),mt=optional(f,"missing_truncated");
   if(mt&&mt.kind!=="boolean")return yield* Effect.fail(failure("invalid_response"));
   return{status,days_considered,days_with_values,missing,...(rr?{requested_range:yield* range(frame,rr,"invalid_response")} :{}),...(ar?{available_range:yield* range(frame,ar,"invalid_response")} :{}),...(mc?{missing_interval_count:yield* int(frame,mc,"invalid_response")} :{}),...(mt?.kind==="boolean"?{missing_truncated:mt.value}:{})};
  });
  const decodeResponseView=(frame:Frame):Effect.Effect<CoverageResponseView,FixedContractFailure>=>Effect.gen(function*(){
   const f=yield* fields(frame,frame.root,"invalid_response");const items=yield* attempt(()=>arr(f.get("items"),"invalid_response"),"invalid_response"),evidence=yield* attempt(()=>arr(f.get("evidence"),"invalid_response"),"invalid_response");
   if(items.length||evidence.length||optional(f,"packet")||optional(f,"next_cursor"))return yield* Effect.fail(failure("private_profile_unavailable"));
   const schema=yield* attempt(()=>str(frame,f.get("schema"),"invalid_response"),"invalid_response"),schema_version=yield* int(frame,f.get("schema_version"),"invalid_response");
   const c=yield* coverage(frame,f.get("coverage"));const ss:CoverageResponseView["sources"][number][]=[],ls:CoverageResponseView["limitations"][number][]=[];
   for(const n of yield* attempt(()=>arr(f.get("sources"),"invalid_response"),"invalid_response")){const s=yield* fields(frame,n,"invalid_response");ss.push({schema:yield* attempt(()=>str(frame,s.get("schema"),"invalid_response"),"invalid_response"),schema_version:yield* int(frame,s.get("schema_version"),"invalid_response"),digest:yield* attempt(()=>str(frame,s.get("digest"),"invalid_response"),"invalid_response")});}
   for(const n of yield* attempt(()=>arr(f.get("limitations"),"invalid_response"),"invalid_response")){const l=yield* fields(frame,n,"invalid_response");ls.push(yield* attempt(()=>({code:str(frame,l.get("code"),"invalid_response"),message:str(frame,l.get("message"),"invalid_response")}),"invalid_response"));}
   const metadata=optional(f,"metadata");if(metadata&&metadata.kind!=="object")return yield* Effect.fail(failure("invalid_response"));const g=metadata?yield* json(frame,metadata):undefined;if(g&&g.kind!=="object")return yield* Effect.fail(failure("invalid_response"));
   return{schema,schema_version,items:[],evidence:[],coverage:c,sources:ss,limitations:ls,...(g?.kind==="object"?{metadata:g}:{})};
  });
  const issueRequest=(view:CoverageRequestView):OwnedCoverageRequest=>{const token=Object.freeze({[contractBrand]:"request" as const});values.set(token,freeze({kind:"request",view}));return token;};
  const issueResponse=(view:CoverageResponseView):OwnedCoverageResponse=>{const token=Object.freeze({[contractBrand]:"response" as const});values.set(token,freeze({kind:"response",view}));return token;};
  const get=(value:unknown,kind:"request"|"response"):Stored|null=>{if(!object(value))return null;const stored=values.get(value);return stored?.kind===kind?stored:null;};
  const decode=(kind:"request"|"response",representation:unknown,payload:unknown):Effect.Effect<OwnedCoverageRequest|OwnedCoverageResponse,FixedContractFailure>=>exclusive(()=>Effect.gen(function*(){
   const frame=yield* attempt(()=>scan(representation,payload),kind==="request"?"invalid_request":"invalid_response");yield* check("before_decode");
   if(kind==="request"){const view=yield* decodeRequestView(frame);yield* check("before_publication");return yield* attempt(()=>{alive();return issueRequest(view);});}
   const view=yield* decodeResponseView(frame);yield* check("before_publication");return yield* attempt(()=>{alive();return issueResponse(view);},"invalid_response");
  }));
  const validateCivil=(r:CivilRange):Effect.Effect<void,FixedContractFailure>=>Effect.gen(function*(){
   yield* check("before_admission");const slot=Object.freeze({}),ctx=Object.freeze({});let active=true;
   const issuer:ContractProfileIssuer=Object.freeze({issueNumber:()=>null,issueCivil:(s:unknown,start:unknown,end:unknown,accepted:unknown)=>{
    if(!active||!live||s!==slot||start!==r.start_date||end!==r.end_date||typeof accepted!=="boolean")return null;const t=Object.freeze({[rangeBrand]:true as const});decisions.set(t,{slot,context:ctx,start:r.start_date,end:r.end_date,accepted});return t;
   }});
   const returned=yield* supervised(Effect.suspend(()=>civil(r.start_date,r.end_date,slot,issuer)).pipe(Effect.ensuring(Effect.sync(()=>{active=false;}))),"native_profile_unavailable");
   const read=()=>{alive();if(!object(returned))reject("native_profile_unavailable");const d=decisions.get(returned);if(!d||d.slot!==slot||d.context!==ctx||d.start!==r.start_date||d.end!==r.end_date)reject("native_profile_unavailable");return d.accepted;};
   const accepted=yield* attempt(read,"native_profile_unavailable");yield* check("after_profile");yield* attempt(read,"native_profile_unavailable");if(!accepted)return yield* Effect.fail(failure("invalid_date_range"));
  });
  const admitRequest=(value:unknown):Effect.Effect<OwnedCoverageRequest,FixedContractFailure>=>exclusive(()=>Effect.gen(function*(){
   const stored=get(value,"request");if(!stored||stored.kind!=="request")return yield* Effect.fail(failure("invalid_request"));yield* check("before_admission");
   const v=stored.view;yield* attempt(()=>{alive();if(get(value,"request")!==stored)reject("invalid_request");if(v.schema!=="healthmd.query_request"||v.schema_version!=="1")reject("unsupported_operation");const a=BigInt(v.page.max_items),b=BigInt(v.page.max_bytes);if(a<=0n||a>1000n||b<=0n||b>1048576n)reject("invalid_page_controls");});
   if(v.dates.type==="exact")yield* validateCivil(v.dates.range);yield* check("before_publication");return yield* attempt(()=>{alive();if(get(value,"request")!==stored)reject("invalid_request");return issueRequest(v);});
  }));
  const constructResponse=(value:unknown):Effect.Effect<OwnedCoverageResponse,FixedContractFailure>=>exclusive(()=>Effect.gen(function*(){
   const stored=get(value,"response");if(!stored||stored.kind!=="response")return yield* Effect.fail(failure("invalid_response"));yield* check("before_construction");
   const view=yield* attempt(()=>{
    alive();if(get(value,"response")!==stored)reject("invalid_response");const v=stored.view;
    const missing=sorted(v.coverage.missing,x=>x.range.start_date),sources=v.sources.slice(0,64);
    const {missing_interval_count:_count,missing_truncated:_truncated,...rawCoverage}=v.coverage;
    const c:CoverageView={...rawCoverage,missing:missing.slice(0,64),...(missing.length>64?{missing_interval_count:String(missing.length),missing_truncated:true}:{})};
    const proposed=[...v.limitations];if(v.sources.length>64)proposed.push({code:"source_descriptors_truncated",message:"Additional source descriptors were omitted from this bounded response page."});if(c.missing_truncated===true)proposed.push({code:"coverage_intervals_truncated",message:"Additional missing intervals were omitted; inspect missing_interval_count."});
    const unique=new Map<string,CoverageResponseView["limitations"][number]>();for(const l of proposed)unique.set(quoted(l.code)+","+quoted(l.message),l);
    const all=[...unique.values()].sort((a,b)=>a.code<b.code?-1:a.code>b.code?1:a.message<b.message?-1:a.message>b.message?1:0);let limitations=all;
    if(all.length>64){limitations=all.slice(0,62);const factual=all.find(x=>x.code==="factual_observations_only");if(factual&&!limitations.includes(factual))limitations.push(factual);limitations.push({code:"limitations_truncated",message:"Additional limitations were omitted from this bounded response page."});limitations=sorted(limitations,x=>x.code);}
    return{...v,coverage:c,sources,limitations};
   },"invalid_response");yield* check("before_publication");return yield* attempt(()=>{alive();if(get(value,"response")!==stored)reject("invalid_response");return issueResponse(view);},"invalid_response");
  }));
  const wireObject=(entries:readonly(readonly[string,string])[]):string=>"{"+sorted(entries,x=>x[0]).map(([k,v])=>quoted(k)+":"+v).join(",")+"}";
  const strings=(items:readonly string[]):string=>"["+items.map(quoted).join(",")+"]";
  const scalarWire=(v:Scalar):string=>{alive();const result=canonical(v.kind,v.kind==="f64"?v.bits:v.decimal);alive();if(Result.isFailure(result))reject("native_profile_unavailable");const s=result.success;if(typeof s!=="string"||s.length>1024||! /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/.test(s))reject("native_profile_unavailable");return s;};
  const jsonWire=(v:UnknownJson):string=>{switch(v.kind){case"null":return"null";case"boolean":return String(v.value);case"string":return quoted(v.value);case"i64":case"u64":case"f64":return scalarWire(v);case"array":return"["+v.values.map(jsonWire).join(",")+"]";case"object":return wireObject(v.entries.map(([k,n])=>[k,jsonWire(n)]));}};
  const rangeWire=(r:CivilRange):string=>wireObject([["start_date",quoted(r.start_date)],["end_date",quoted(r.end_date)]]);
  const intWire=(s:string):string=>scalarWire({kind:"i64",decimal:s});
  const encodeStored=(stored:Stored):string=>{
   if(stored.kind==="request"){const v=stored.view;return wireObject([["schema",quoted(v.schema)],["schema_version",intWire(v.schema_version)],["metrics",v.metrics.type==="all_available"?'{"type":"all_available"}':wireObject([["type",'"explicit"'],["metric_ids",strings(v.metrics.metric_ids)]])],["sources",v.sources.type==="all_available"?'{"type":"all_available"}':wireObject([["type",'"explicit"'],["source_ids",strings(v.sources.source_ids)],["provider_ids",strings(v.sources.provider_ids)]])],["dates",v.dates.type==="all_available"?'{"type":"all_available"}':wireObject([["type",'"exact"'],["range",rangeWire(v.dates.range)]])],["operation",'{"type":"coverage"}'],["page",wireObject([["max_items",intWire(v.page.max_items)],["max_bytes",intWire(v.page.max_bytes)],...(v.page.cursor===undefined?[]:[["cursor",quoted(v.page.cursor)] as const])])]]);}
   const v=stored.view,c=v.coverage;const cw=wireObject([["status",quoted(c.status)],["days_considered",intWire(c.days_considered)],["days_with_values",intWire(c.days_with_values)],["missing","["+c.missing.map(m=>wireObject([["range",rangeWire(m.range)],["status",quoted(m.status)],...(m.reason===undefined?[]:[["reason",quoted(m.reason)] as const])])).join(",")+"]"],...(c.requested_range?[["requested_range",rangeWire(c.requested_range)] as const]:[]),...(c.available_range?[["available_range",rangeWire(c.available_range)] as const]:[]),...(c.missing_interval_count===undefined?[]:[["missing_interval_count",intWire(c.missing_interval_count)] as const]),...(c.missing_truncated===undefined?[]:[["missing_truncated",String(c.missing_truncated)] as const])]);
   return wireObject([["schema",quoted(v.schema)],["schema_version",intWire(v.schema_version)],["coverage",cw],["items","[]"],["evidence","[]"],["sources","["+v.sources.map(s=>wireObject([["schema",quoted(s.schema)],["schema_version",intWire(s.schema_version)],["digest",quoted(s.digest)]])).join(",")+"]"],["limitations","["+v.limitations.map(l=>wireObject([["code",quoted(l.code)],["message",quoted(l.message)]])).join(",")+"]"],...(v.metadata?[["metadata",jsonWire(v.metadata)] as const]:[])]);
  };
  const withValue=<A,E>(kind:"request"|"response",value:unknown,callback:(request:OwnedContractReadRequest,view:CoverageReadView)=>Effect.Effect<A,E>):Effect.Effect<A|null,E|FixedContractFailure>=>Effect.suspend(()=>{
   const stored=get(value,kind);if(!stored||!object(value))return Effect.succeed(null);
   return exclusive(()=>Effect.gen(function*(){yield* check("before_publication");const context=Object.freeze({}),request=Object.freeze({[requestBrand]:true as const});let active=true;requests.set(request,{token:value,context});
    const admitted=(r:unknown,t:unknown):boolean=>{if(!active||!live||!object(r)||!object(t))return false;const rd=requests.get(r);return rd?.context===context&&rd.token===t&&t===value&&values.get(t)===stored;};
    const read=<T>(r:unknown,t:unknown,phase:"before_read"|"before_encode",materialize:()=>T):Effect.Effect<T|null,FixedContractFailure>=>Effect.suspend(()=>{
     if(!admitted(r,t))return Effect.succeed(null);return Effect.gen(function*(){yield* check(phase);return yield* attempt(()=>{alive();if(!admitted(r,t))return null;const result=materialize();alive();if(!admitted(r,t))return null;return result;},"native_profile_unavailable");});
    });
    const view:CoverageReadView=Object.freeze({readRequest:(r:unknown,t:unknown)=>read(r,t,"before_read",()=>stored.kind==="request"?stored.view:null),readResponse:(r:unknown,t:unknown)=>read(r,t,"before_read",()=>stored.kind==="response"?stored.view:null),encode:(r:unknown,t:unknown)=>read(r,t,"before_encode",()=>encodeStored(stored))});
    const output=yield* supervised(Effect.suspend(()=>callback(request,view)).pipe(Effect.ensuring(Effect.sync(()=>{active=false;requests.delete(request);}))),"native_profile_unavailable");yield* check("after_callback");return output;
   }).pipe(Effect.ensuring(Effect.sync(()=>{ /* each inner callback owns its live sentinel */ }))));
  });
  const requestToken=(v:unknown):v is OwnedCoverageRequest=>get(v,"request")?.kind==="request";
  const responseToken=(v:unknown):v is OwnedCoverageResponse=>get(v,"response")?.kind==="response";
  return Object.freeze({decodeRequest:(r:unknown,p:unknown)=>decode("request",r,p).pipe(Effect.flatMap(t=>attempt(()=>{alive();if(!requestToken(t))reject("invalid_request");return t;}))),decodeResponse:(r:unknown,p:unknown)=>decode("response",r,p).pipe(Effect.flatMap(t=>attempt(()=>{alive();if(!responseToken(t))reject("invalid_response");return t;},"invalid_response"))),admitRequest,constructResponse,withRequest:<A,E>(v:unknown,c:(r:OwnedContractReadRequest,w:CoverageReadView)=>Effect.Effect<A,E>)=>withValue("request",v,c),withResponse:<A,E>(v:unknown,c:(r:OwnedContractReadRequest,w:CoverageReadView)=>Effect.Effect<A,E>)=>withValue("response",v,c)});
 });
}
