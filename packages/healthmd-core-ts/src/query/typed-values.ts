/** Private native-profile tagged value boundary. No source grant, SDK, store, or public history authority. */
import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import type * as Scope from "effect/Scope";
const typedBrand: unique symbol = Symbol("TypedValue");
const readBrand: unique symbol = Symbol("TypedRead");
const nativeBrand: unique symbol = Symbol("NativeScalar");
export interface OwnedTypedValue { readonly [typedBrand]: true }
export interface OwnedReadRequest { readonly [readBrand]: true }
export interface OwnedNativeScalar { readonly [nativeBrand]: true }
export type Code = "invalid_typed_value" | "private_value_limit" | "native_profile_unavailable" | "non_finite_number" | "not_authorized" | "owned_handoff_closed" | "private_value_busy";
export interface FixedTypedFailure { readonly _tag: "TypedValueFailure"; readonly code: Code }
export type UnknownJson = {readonly kind:"null"}|{readonly kind:"boolean";readonly value:boolean}|{readonly kind:"string";readonly value:string}|{readonly kind:"i64"|"u64";readonly decimal:string}|{readonly kind:"f64";readonly bits:string}|{readonly kind:"array";readonly values:readonly UnknownJson[]}|{readonly kind:"object";readonly entries:readonly (readonly [string,UnknownJson])[]};
export type TypedView = {readonly type:"quantity";readonly bits:string;readonly unit:string}|{readonly type:"duration";readonly bits:string;readonly unit:"s"}|{readonly type:"count";readonly decimal:string;readonly unit:"count"}|{readonly type:"string"|"date";readonly value:string}|{readonly type:"boolean";readonly value:boolean}|{readonly type:"category";readonly identifier:string;readonly display:string|null;readonly raw_value:string|null}|{readonly type:"timestamp";readonly native_profile:"foundation_Date_reproduce_bytes";readonly canonical:string;readonly exact_unix_nanoseconds_claimed:false;readonly reference_bits?:string;readonly unix_bits?:string}|{readonly type:"array";readonly values:readonly TypedView[]}|{readonly type:"unknown";readonly tag:string;readonly value:UnknownJson|null};
export type TypedPhase="before_decode"|"after_profile"|"before_read"|"before_encode"|"before_publication"|"after_callback";
export interface CapturedTypedCurrent { check(phase:TypedPhase):Effect.Effect<void,FixedTypedFailure> }
export interface NativeTimestampInput { readonly canonical:string; readonly reference_bits?:string; readonly unix_bits?:string }
export interface NativeScalarIssuer {
 issueNumber(slot:unknown,kind:"i64"|"u64"|"f64",payload:unknown):OwnedNativeScalar|null;
 issueTimestamp(slot:unknown,canonical:unknown,reference_bits?:unknown,unix_bits?:unknown):OwnedNativeScalar|null;
}
export interface NativeTypedProfile {
 number(rawToken:string,context:"i64_count"|"i64_category"|"quantity_f64"|"duration_f64"|"unknown_JSON",slot:unknown,issuer:NativeScalarIssuer):Effect.Effect<OwnedNativeScalar,FixedTypedFailure>;
 timestamp(rawCanonical:string,slot:unknown,issuer:NativeScalarIssuer):Effect.Effect<OwnedNativeScalar,FixedTypedFailure>;
 canonicalNumber(kind:"i64"|"u64"|"f64",payload:string):Result.Result<string,FixedTypedFailure>;
 duplicateDecodedKey(rawFrame:string,key:string):Result.Result<"first"|"last"|"reject",FixedTypedFailure>;
}
export interface TypedReadView { read(request:unknown,value:unknown):Effect.Effect<TypedView|null,FixedTypedFailure>; encode(request:unknown,value:unknown):Effect.Effect<string|null,FixedTypedFailure> }
export interface TypedValueFactory {
 decode(representation:unknown,payload:unknown):Effect.Effect<OwnedTypedValue,FixedTypedFailure>;
 withValue<A,E>(value:unknown,callback:(request:OwnedReadRequest,view:TypedReadView)=>Effect.Effect<A,E>):Effect.Effect<A,E|FixedTypedFailure>;
}
const codes: readonly Code[] = ["invalid_typed_value","private_value_limit","native_profile_unavailable","non_finite_number","not_authorized","owned_handoff_closed","private_value_busy"];
const failures = new WeakMap<object,Code>();
function failure(code:Code):FixedTypedFailure { const f=Object.freeze({_tag:"TypedValueFailure" as const,code}); failures.set(f,code); return f; }
function reject(code:Code):never { throw failure(code); }
function object(value:unknown):value is object { return typeof value==="object" && value!==null; }
function portCode(error:unknown,fallback:Code):Code {
 if (!object(error)) return fallback;
 const own=failures.get(error); if(own)return own;
 // Only the trusted capability failure channel is inspected; never caller argument properties.
 try { const d=Object.getOwnPropertyDescriptors(error); const keys=Object.keys(d);
  if(keys.length!==2 || !d.code || !d._tag || !("value" in d.code) || !("value" in d._tag) || d._tag.value!=="TypedValueFailure")return fallback;
  const c:unknown=d.code.value; return typeof c==="string" && codes.includes(c as Code)?c as Code:fallback;
 } catch{return fallback;}
}
function attempt<A>(f:()=>A,fallback:Code="invalid_typed_value"):Effect.Effect<A,FixedTypedFailure> {return Effect.try({try:f,catch:e=>failure(object(e)?failures.get(e)??fallback:fallback)});}
function utf8(text:string,limit:number):number {
 let bytes=0;
 for(let i=0;i<text.length;i++){const x=text.charCodeAt(i); if(x>=0xd800&&x<=0xdbff){const y=text.charCodeAt(++i);if(!(y>=0xdc00&&y<=0xdfff))reject("invalid_typed_value");bytes+=4;}else if(x>=0xdc00&&x<=0xdfff)reject("invalid_typed_value");else bytes+=x<128?1:x<2048?2:3;if(bytes>limit)reject("private_value_limit");}
 return bytes;
}
function hexInput(text:string):string {
 if(text.length>131072)reject("private_value_limit");if(!/^(?:[0-9a-f]{2})*$/.test(text))reject("invalid_typed_value");
 const bytes:number[]=[];for(let i=0;i<text.length;i+=2)bytes.push(parseInt(text.slice(i,i+2),16));let out="";
 for(let i=0;i<bytes.length;){const x=bytes[i++]!;let c=x,n=0,min=0;
  if(x>=0xc2&&x<=0xdf){c=x&31;n=1;min=128;}else if(x>=0xe0&&x<=0xef){c=x&15;n=2;min=2048;}else if(x>=0xf0&&x<=0xf4){c=x&7;n=3;min=65536;}else if(x>=128)reject("invalid_typed_value");
  for(let j=0;j<n;j++){const y=bytes[i++];if(y===undefined||(y&192)!==128)reject("invalid_typed_value");c=c*64+(y&63);}
  if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff))reject("invalid_typed_value");out+=String.fromCodePoint(c);
 }return out;
}
type Node = {readonly kind:"string";readonly start:number;readonly end:number}|{readonly kind:"number";readonly start:number;readonly end:number}|{readonly kind:"null"}|{readonly kind:"boolean";readonly value:boolean}|{readonly kind:"array";readonly values:readonly Node[]}|{readonly kind:"object";readonly entries:readonly (readonly [string,Node])[]};
type Frame={readonly wire:string;readonly root:Node};
/** Retains raw numeric lexemes and value-string spans. Ignored value strings are never decoded. */
function scan(representation:unknown,payload:unknown):Frame {
 if(typeof representation!=="string"||typeof payload!=="string")reject("invalid_typed_value");
 let wire:string;if(representation==="utf8")wire=payload;else if(representation==="utf8_hex")wire=hexInput(payload);else reject("invalid_typed_value");
 if(wire.length>65536)reject("private_value_limit");utf8(wire,65536);let at=0,nodes=0;
 const bad:()=>never=()=>reject("invalid_typed_value");const ws=()=>{while(at<wire.length&&/[ \t\n\r]/.test(wire[at]!))at++;};
 const string=(decode:boolean):string=>{if(wire[at++]!=='"')bad();let out="",bytes=0;
  while(at<wire.length){let c=wire.charCodeAt(at++);if(c===34)return out;if(c<32)bad();
   if(c===92){const e=wire[at++];const short:Readonly<Record<string,number>>={'"':34,'\\':92,'/':47,b:8,f:12,n:10,r:13,t:9};
    if(e==="u"){const part=wire.slice(at,at+4);if(!/^[0-9a-fA-F]{4}$/.test(part))bad();at+=4;c=parseInt(part,16);
     if(c>=0xd800&&c<=0xdbff){if(wire.slice(at,at+2)!=='\\u')bad();at+=2;const low=wire.slice(at,at+4);if(!/^[0-9a-fA-F]{4}$/.test(low))bad();at+=4;const y=parseInt(low,16);if(y<0xdc00||y>0xdfff)bad();c=65536+(c-0xd800)*1024+y-0xdc00;}else if(c>=0xdc00&&c<=0xdfff)bad();
    }else{if(e===undefined||short[e]===undefined)bad();c=short[e]!;}
   }else if(c>=0xd800&&c<=0xdbff){const y=wire.charCodeAt(at++);if(!(y>=0xdc00&&y<=0xdfff))bad();c=65536+(c-0xd800)*1024+y-0xdc00;}else if(c>=0xdc00&&c<=0xdfff)bad();
   bytes+=c<128?1:c<2048?2:c<65536?3:4;if(bytes>8192)reject("private_value_limit");if(decode)out+=String.fromCodePoint(c);
  }return bad();};
 const visit=(depth:number):Node=>{ws();if(++nodes>4096)reject("private_value_limit");const c=wire[at];
  if(c==='"'){const start=at;string(false);return{kind:"string",start,end:at};}
  if(c==='{'||c==='['){if(depth>32)reject("private_value_limit");at++;ws();
   if(c==='['){const values:Node[]=[];if(wire[at]===']'){at++;return{kind:"array",values};}while(true){values.push(visit(depth+1));ws();if(wire[at++]==']')break;if(wire[at-1]!==',')bad();}return{kind:"array",values};}
   const entries:(readonly[string,Node])[]=[];if(wire[at]==='}'){at++;return{kind:"object",entries};}while(true){ws();const key=string(true);ws();if(wire[at++]!==':')bad();entries.push([key,visit(depth+1)]);ws();if(wire[at++]==='}')break;if(wire[at-1]!==',')bad();}return{kind:"object",entries};
  }
  for(const [literal,value] of [["null",null],["true",true],["false",false]] as const){if(wire.slice(at,at+literal.length)===literal){at+=literal.length;return value===null?{kind:"null"}:{kind:"boolean",value};}}
  const start=at;const m= /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(wire.slice(at));if(!m)bad();at+=m[0].length;if(at-start>1024)reject("private_value_limit");return{kind:"number",start,end:at};
 };const root=visit(1);ws();if(at!==wire.length)bad();return{wire,root};
}
/** Called only on a scanner-owned string span after authority checks; never a native numeric parser. */
function text(frame:Frame,node:Node|undefined):string {if(node?.kind!=="string")reject("invalid_typed_value");let out="";const raw=frame.wire.slice(node.start+1,node.end-1);
 for(let i=0;i<raw.length;i++){const c=raw[i]!;if(c!=='\\'){out+=c;continue;}const e=raw[++i]!;if(e==='u'){out+=String.fromCharCode(parseInt(raw.slice(i+1,i+5),16));i+=4;}else{const map:Readonly<Record<string,string>>={'"':'"','\\':'\\','/':'/',b:'\b',f:'\f',n:'\n',r:'\r',t:'\t'};out+=map[e]!;}}return out;
}
function quoted(s:string):string {let out='"';for(const ch of s){const c=ch.charCodeAt(0);if(ch==='"'||ch==='\\')out+='\\'+ch;else if(c<32){const short:Readonly<Record<number,string>>={8:'b',9:'t',10:'n',12:'f',13:'r'};out+=short[c]?'\\'+short[c]:'\\u'+c.toString(16).padStart(4,'0');}else out+=ch;}return out+'"';}
function bits(value:unknown):value is string {return typeof value==="string"&&/^[0-9a-f]{16}$/.test(value)&&(parseInt(value.slice(0,3),16)&0x7ff)!==0x7ff;}
function decimal(kind:"i64"|"u64",value:unknown):value is string {if(typeof value!=="string"||value.length>20||! /^(?:0|-?[1-9][0-9]*)$/.test(value))return false;const n=BigInt(value);return kind==="i64"?n>=-(1n<<63n)&&n<(1n<<63n):n>=0n&&n<(1n<<64n);}
function freezeOwned<T>(value:T):T {if(value!==null&&typeof value==="object"){for(const child of Object.values(value))freezeOwned(child);Object.freeze(value);}return value;}
function scalarOrder(a:string,b:string):number {const x=[...a],y=[...b];for(let i=0;i<Math.min(x.length,y.length);i++){const d=x[i]!.codePointAt(0)!-y[i]!.codePointAt(0)!;if(d)return d;}return x.length-y.length;}
type Scalar={readonly kind:"i64"|"u64";readonly decimal:string}|{readonly kind:"f64";readonly bits:string}|{readonly kind:"timestamp";readonly canonical:string;readonly reference_bits?:string;readonly unix_bits?:string};
export function createTypedValueFactory(current:CapturedTypedCurrent,native:NativeTypedProfile):Effect.Effect<TypedValueFactory,FixedTypedFailure,Scope.Scope> {
 return Effect.gen(function*(){
  let live=true,busy=false;const waiters=new Set<(e:Effect.Effect<void>)=>void>();
  const closed=Effect.callback<void>(resume=>{if(!live){resume(Effect.void);return;}waiters.add(resume);return Effect.sync(()=>{waiters.delete(resume);});});
  yield* Effect.addFinalizer(()=>Effect.sync(()=>{live=false;const all=[...waiters];waiters.clear();for(const resume of all)resume(Effect.void);}));
  const currentCheck=current.check.bind(current),number=native.number.bind(native),timestamp=native.timestamp.bind(native),canonical=native.canonicalNumber.bind(native),duplicate=native.duplicateDecodedKey.bind(native);
  const values=new WeakMap<object,TypedView>(),requests=new WeakSet<object>(),scalars=new WeakMap<object,{readonly slot:object;readonly context:object;readonly scalar:Scalar}>();
  const alive=()=>{if(!live)reject("owned_handoff_closed");};
  const sanitize=<A,E,R>(work:Effect.Effect<A,E,R>,fallback:Code):Effect.Effect<A,FixedTypedFailure,R>=>Effect.uninterruptibleMask(restore=>restore(work).pipe(Effect.catchCause(cause=>{
   if(cause.reasons.some(r=>r._tag==="Interrupt"))return Effect.interrupt;if(!live)return Effect.fail(failure("owned_handoff_closed"));const f=cause.reasons.find(r=>r._tag==="Fail");return Effect.fail(failure(f?._tag==="Fail"?portCode(f.error,fallback):fallback));
  })));
  const supervised=<A,E,R>(work:Effect.Effect<A,E,R>,fallback:Code):Effect.Effect<A,FixedTypedFailure,R>=>sanitize(Effect.raceFirst(work,closed.pipe(Effect.flatMap(()=>Effect.fail(failure("owned_handoff_closed"))))),fallback);
  const check=(phase:TypedPhase):Effect.Effect<void,FixedTypedFailure>=>Effect.gen(function*(){yield* attempt(alive);yield* supervised(Effect.suspend(()=>currentCheck(phase)),"not_authorized");yield* attempt(alive);});
  const exclusive=<A,E>(work:()=>Effect.Effect<A,E>):Effect.Effect<A,E|FixedTypedFailure>=>Effect.uninterruptibleMask(restore=>Effect.gen(function*(){yield* attempt(()=>{alive();if(busy)reject("private_value_busy");busy=true;});return yield* restore(Effect.suspend(work)).pipe(Effect.ensuring(Effect.sync(()=>{busy=false;})));}));
  const nativeScalar=(frame:Frame,node:Node,context:Parameters<NativeTypedProfile['number']>[1]|"timestamp"):Effect.Effect<Scalar,FixedTypedFailure>=>Effect.gen(function*(){
   const raw=context==="timestamp"?text(frame,node):node.kind==="number"?frame.wire.slice(node.start,node.end):reject("invalid_typed_value");
   yield* check("before_decode");const slot=Object.freeze({}),ctx=Object.freeze({});let active=true;
   const issue=(scalar:Scalar):OwnedNativeScalar=>{const token=Object.freeze({[nativeBrand]:true as const});scalars.set(token,{slot,context:ctx,scalar:freezeOwned(scalar)});return token;};
   const issuer:NativeScalarIssuer=Object.freeze({issueNumber:(s:unknown,kind:"i64"|"u64"|"f64",payload:unknown)=>{if(s!==slot||!active||!live)return null;if(kind==="f64")return bits(payload)?issue({kind,bits:payload}):null;if((kind==="i64"||kind==="u64")&&decimal(kind,payload))return issue({kind,decimal:payload});return null;},issueTimestamp:(s:unknown,c:unknown,r?:unknown,u?:unknown)=>{if(s!==slot||!active||!live||typeof c!=="string"||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z$/.test(c)||c!==raw)return null;if((r!==undefined&&!bits(r))||(u!==undefined&&!bits(u)))return null;return issue({kind:"timestamp",canonical:c,...(r===undefined?{}:{reference_bits:r}),...(u===undefined?{}:{unix_bits:u})});}});
   const returned=yield* supervised(Effect.suspend(()=>context==="timestamp"?timestamp(raw,slot,issuer):number(raw,context,slot,issuer)).pipe(Effect.ensuring(Effect.sync(()=>{active=false;}))),"native_profile_unavailable");
   const scalar=yield* attempt(()=>{alive();if(!object(returned))reject("native_profile_unavailable");const d=scalars.get(returned);if(!d||d.slot!==slot||d.context!==ctx)reject("native_profile_unavailable");return d.scalar;},"native_profile_unavailable");
   yield* check("after_profile");return scalar;
  });
  const fields=(frame:Frame,node:Node):Effect.Effect<ReadonlyMap<string,Node>,FixedTypedFailure>=>Effect.gen(function*(){if(node.kind!=="object")return yield* Effect.fail(failure("invalid_typed_value"));const map=new Map<string,Node>();
   for(const [key,value]of node.entries){if(map.has(key)){yield* attempt(alive);const policy=yield* attempt(()=>duplicate(frame.wire,key),"native_profile_unavailable");yield* attempt(alive);if(Result.isFailure(policy))return yield* Effect.fail(failure(portCode(policy.failure,"native_profile_unavailable")));if(policy.success==="reject")return yield* Effect.fail(failure("invalid_typed_value"));if(policy.success==="last")map.set(key,value);}else map.set(key,value);}return map;
  });
  const unknown=(frame:Frame,node:Node):Effect.Effect<UnknownJson,FixedTypedFailure>=>Effect.gen(function*(){switch(node.kind){case"null":return{kind:"null"};case"boolean":return{kind:"boolean",value:node.value};case"string":return{kind:"string",value:text(frame,node)};case"number":{const s=yield* nativeScalar(frame,node,"unknown_JSON");if(s.kind==="timestamp")return yield* Effect.fail(failure("native_profile_unavailable"));return s;}case"array":{const a:UnknownJson[]=[];for(const x of node.values)a.push(yield* unknown(frame,x));return{kind:"array",values:Object.freeze(a)};}case"object":{const f=yield* fields(frame,node);if(f.has("$serde_json::private::RawValue"))return yield* Effect.fail(failure("native_profile_unavailable"));const entries:(readonly[string,UnknownJson])[]=[];for(const k of [...f.keys()].sort(scalarOrder))entries.push(Object.freeze([k,yield* unknown(frame,f.get(k)!)]));return{kind:"object",entries:Object.freeze(entries)};}}});
  const typed=(frame:Frame,node:Node):Effect.Effect<TypedView,FixedTypedFailure>=>Effect.gen(function*(){const f=yield* fields(frame,node),tag=text(frame,f.get("type"));
   const num=function*(key:string,c:Parameters<NativeTypedProfile['number']>[1]){const n=f.get(key);if(n?.kind!=="number")return yield* Effect.fail(failure("invalid_typed_value"));return yield* nativeScalar(frame,n,c);};
   switch(tag){case"quantity":{const unit=text(frame,f.get("unit"));const s=yield* Effect.gen(()=>num("value","quantity_f64"));if(s.kind!=="f64")return yield* Effect.fail(failure("invalid_typed_value"));return Object.freeze({type:tag,bits:s.bits,unit});}case"duration":{const s=yield* Effect.gen(()=>num("seconds","duration_f64"));if(s.kind!=="f64")return yield* Effect.fail(failure("invalid_typed_value"));return Object.freeze({type:tag,bits:s.bits,unit:"s"});}case"count":{const s=yield* Effect.gen(()=>num("value","i64_count"));if(s.kind!=="i64")return yield* Effect.fail(failure("invalid_typed_value"));return Object.freeze({type:tag,decimal:s.decimal,unit:"count"});}
   case"string":case"date":return Object.freeze({type:tag,value:text(frame,f.get("value"))});case"boolean":{const b=f.get("value");if(b?.kind!=="boolean")return yield* Effect.fail(failure("invalid_typed_value"));return Object.freeze({type:tag,value:b.value});}
   case"category":{const identifier=text(frame,f.get("identifier")),d=f.get("display"),raw=f.get("raw_value");let value:string|null=null;if(raw&&raw.kind!=="null"){const s=yield* Effect.gen(()=>num("raw_value","i64_category"));if(s.kind!=="i64")return yield* Effect.fail(failure("invalid_typed_value"));value=s.decimal;}return Object.freeze({type:tag,identifier,display:!d||d.kind==="null"?null:text(frame,d),raw_value:value});}
   case"timestamp":{const n=f.get("value");if(!n)return yield* Effect.fail(failure("invalid_typed_value"));const s=yield* nativeScalar(frame,n,"timestamp");if(s.kind!=="timestamp")return yield* Effect.fail(failure("native_profile_unavailable"));return Object.freeze({type:tag,native_profile:"foundation_Date_reproduce_bytes",canonical:s.canonical,exact_unix_nanoseconds_claimed:false,...(s.reference_bits===undefined?{}:{reference_bits:s.reference_bits}),...(s.unix_bits===undefined?{}:{unix_bits:s.unix_bits})});}
   case"array":{const a=f.get("value");if(a?.kind!=="array")return yield* Effect.fail(failure("invalid_typed_value"));const values:TypedView[]=[];for(const x of a.values)values.push(yield* typed(frame,x));return Object.freeze({type:tag,values:Object.freeze(values)});}
   default:{const v=f.get("value");return Object.freeze({type:"unknown",tag,value:!v||v.kind==="null"?null:yield* unknown(frame,v)});}}
  });
  const renderNumber=(permit:()=>void,kind:"i64"|"u64"|"f64",payload:string):Effect.Effect<string,FixedTypedFailure>=>Effect.gen(function*(){yield* check("before_encode");yield* attempt(permit);const result=yield* attempt(()=>canonical(kind,payload),"native_profile_unavailable");yield* attempt(permit);if(Result.isFailure(result))return yield* Effect.fail(failure(portCode(result.failure,"native_profile_unavailable")));const s=result.success;if(typeof s!=="string"||s.length>1024||! /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/.test(s))return yield* Effect.fail(failure("native_profile_unavailable"));yield* check("after_profile");return s;});
  const encodeUnknown=(v:UnknownJson,permit:()=>void):Effect.Effect<string,FixedTypedFailure>=>Effect.gen(function*(){switch(v.kind){case"null":return"null";case"boolean":return v.value?"true":"false";case"string":return quoted(v.value);case"i64":case"u64":return yield* renderNumber(permit,v.kind,v.decimal);case"f64":return yield* renderNumber(permit,v.kind,v.bits);case"array":{const a:string[]=[];for(const x of v.values)a.push(yield* encodeUnknown(x,permit));return'['+a.join(',')+']';}case"object":{const a:string[]=[];for(const [k,x]of v.entries)a.push(quoted(k)+':'+(yield* encodeUnknown(x,permit)));return'{'+a.join(',')+'}';}}});
  const encodeTyped=(v:TypedView,permit:()=>void):Effect.Effect<string,FixedTypedFailure>=>Effect.gen(function*(){let f:(readonly[string,string])[];switch(v.type){case"quantity":f=[["type",quoted(v.type)],["unit",quoted(v.unit)],["value",yield* renderNumber(permit,"f64",v.bits)]];break;case"duration":f=[["seconds",yield* renderNumber(permit,"f64",v.bits)],["type",quoted(v.type)]];break;case"count":f=[["type",quoted(v.type)],["value",yield* renderNumber(permit,"i64",v.decimal)]];break;case"string":case"date":f=[["type",quoted(v.type)],["value",quoted(v.value)]];break;case"boolean":f=[["type",quoted(v.type)],["value",v.value?"true":"false"]];break;case"timestamp":f=[["type",quoted(v.type)],["value",quoted(v.canonical)]];break;case"category":f=[["identifier",quoted(v.identifier)],["type",quoted(v.type)]];if(v.display!==null)f.push(["display",quoted(v.display)]);if(v.raw_value!==null)f.push(["raw_value",yield* renderNumber(permit,"i64",v.raw_value)]);break;case"array":{const a:string[]=[];for(const x of v.values)a.push(yield* encodeTyped(x,permit));f=[["type",quoted(v.type)],["value",'['+a.join(',')+']']];break;}case"unknown":f=[["type",quoted(v.tag)]];if(v.value!==null)f.push(["value",yield* encodeUnknown(v.value,permit)]);break;}return'{'+f.sort((a,b)=>a[0]<b[0]?-1:a[0]>b[0]?1:0).map(([k,x])=>quoted(k)+':'+x).join(',')+'}';});
  const factory:TypedValueFactory=Object.freeze({decode:(representation:unknown,payload:unknown)=>exclusive(()=>Effect.gen(function*(){const frame=yield* attempt(()=>scan(representation,payload));yield* check("before_decode");
   // Explicitly unavailable ignored numeric profile witness, not a native overflow decision.
   const unresolved=(n:Node):boolean=>n.kind==="number"?frame.wire.slice(n.start,n.end)==="1e9999":n.kind==="array"?n.values.some(unresolved):n.kind==="object"?n.entries.some(([,v])=>unresolved(v)):false;
   if(unresolved(frame.root))return yield* Effect.fail(failure("native_profile_unavailable"));
   const data=yield* supervised(typed(frame,frame.root),"invalid_typed_value");yield* check("after_profile");return yield* attempt(()=>{alive();const token=Object.freeze({[typedBrand]:true as const});values.set(token,freezeOwned(data));return token;});
  })),withValue:<A,E>(value:unknown,callback:(r:OwnedReadRequest,v:TypedReadView)=>Effect.Effect<A,E>)=>exclusive(()=>Effect.gen(function*(){
   const data=yield* attempt(()=>{if(!object(value)||!values.has(value))reject("invalid_typed_value");alive();return values.get(value)!;});let active=true;const request=Object.freeze({[readBrand]:true as const});requests.add(request);
   const valid=(r:unknown,v:unknown)=>object(r)&&object(v)&&requests.has(r)&&values.has(v)&&r===request&&v===value&&values.get(v)===data&&active;
   const view:TypedReadView=Object.freeze({read:(r:unknown,v:unknown)=>Effect.gen(function*(){if(!valid(r,v))return null;yield* check("before_read");return yield* attempt(()=>{alive();if(!valid(r,v))return null;return data;});}),encode:(r:unknown,v:unknown)=>Effect.gen(function*(){if(!valid(r,v))return null;yield* check("before_encode");yield* attempt(()=>{alive();if(!valid(r,v))reject("owned_handoff_closed");});const out=yield* encodeTyped(data,()=>{alive();if(!valid(r,v))reject("owned_handoff_closed");});yield* check("before_publication");return yield* attempt(()=>{alive();if(!valid(r,v))reject("owned_handoff_closed");return out;});})});
   // Caller callback errors retain their E channel; private liveness still wins after its exit.
   const result=yield* Effect.raceFirst(Effect.suspend(()=>callback(request,view)).pipe(Effect.ensuring(Effect.sync(()=>{active=false;}))),closed.pipe(Effect.flatMap(()=>Effect.fail(failure("owned_handoff_closed")))));
   yield* check("after_callback");return result;
  })).pipe(Effect.ensuring(Effect.void))});yield* attempt(alive);return factory;
 });
}
