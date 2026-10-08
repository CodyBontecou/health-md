/** Private source-profile framing adapter. Native parser/pipe admission remains separate. */
import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
const ticketBrand: unique symbol = Symbol("ticket");
const lineBrand: unique symbol = Symbol("line");
const replyBrand: unique symbol = Symbol("reply");
const pieceBrand: unique symbol = Symbol("piece");
const terminalBrand: unique symbol = Symbol("terminal");
export interface OwnedIoTicket { readonly [ticketBrand]: true }
export interface OwnedLine { readonly [lineBrand]: true }
export interface OwnedReply { readonly [replyBrand]: true }
export interface OwnedWritePiece { readonly [pieceBrand]: true }
export interface OwnedTerminal { readonly [terminalBrand]: true }
export type Code = "private_stdio_input"|"private_stdio_authority"|"private_stdio_owned"|"private_stdio_source"|"private_stdio_dispatch"|"private_stdio_dispatch_unavailable"|"private_stdio_sink"|"private_stdio_cleanup"|"private_stdio_busy"|"owned_handoff_closed";
export interface FixedFailure { readonly code: Code }
export type Phase = "before_allocation"|"before_read"|"before_dispatch"|"before_publication"|"assert_current";
export interface CapturedLifetime { isLive(): boolean; readonly closed: Effect.Effect<void> }
export interface Current { check(phase: Phase): Effect.Effect<void, FixedFailure> }
export interface SourceGate { beforeRead(ticket: unknown): Effect.Effect<void, FixedFailure> }
export interface FlushGate { beforeFlush(ticket: unknown): Effect.Effect<void, FixedFailure> }
export interface LineView { text(line: unknown): Effect.Effect<string|null,FixedFailure> }
export interface ReplyIssuer { issue(line: unknown, primitiveReply: unknown): OwnedReply|null }
export type DispatcherAvailability = {readonly profile:"synthetic_source_framing";readonly maximumDecodedUTF8Bytes:6291456}|{readonly profile:"existing_private_rpc";readonly maximumDecodedUTF8Bytes:65536};
export interface FrameDispatcher { readonly availability: DispatcherAvailability; handle(line:OwnedLine,view:LineView,issuer:ReplyIssuer):Effect.Effect<OwnedReply|null,FixedFailure> }
export interface WriteView { text(piece:unknown):Effect.Effect<string|null,FixedFailure> }
export interface Io {
 next(ticket:OwnedIoTicket,gate:SourceGate):Effect.Effect<string|null,FixedFailure>;
 write(ticket:OwnedIoTicket,piece:OwnedWritePiece,view:WriteView):Effect.Effect<void,FixedFailure>;
 flush(ticket:OwnedIoTicket,gate:FlushGate):Effect.Effect<void,FixedFailure>;
}
export interface CommitIssuer { commit():OwnedIoTicket|null }
export interface IoOwner {
 withIo<A>(lifetime:CapturedLifetime,issuer:CommitIssuer,use:(ticket:OwnedIoTicket,io:Io)=>Effect.Effect<A,FixedFailure>):Effect.Effect<A,FixedFailure>;
}
export interface TerminalMetadata { readonly input_EOF:true;readonly aggregate_io_release_ACK:true;readonly publication:"acknowledged_private_sink_only" }
export interface StdioFrames {exchange(primitiveRequest:unknown):Effect.Effect<OwnedTerminal,FixedFailure>;inspect(terminal:unknown):TerminalMetadata|null}
export interface StdioFactory {create(trusted:{readonly current:Current;readonly owner:IoOwner;readonly dispatcher:FrameDispatcher}):Effect.Effect<StdioFrames,FixedFailure,Scope.Scope>}

const failures = new WeakMap<object, Code>();
export function fixedFailure(code: Code): FixedFailure {
 const error = Object.freeze({ code }); failures.set(error, code); return error;
}
const member = (value: unknown): value is object => value !== null && (typeof value === "object" || typeof value === "function");
function codeOf(value: unknown, fallback: Code): Code { return member(value) ? failures.get(value) ?? fallback : fallback; }
function refuse(code: Code): never { throw fixedFailure(code); }
function attempt<A>(body: () => A, fallback: Code): Effect.Effect<A, FixedFailure> {
 return Effect.try({ try: body, catch: error => fixedFailure(codeOf(error, fallback)) });
}
function safe<A,E,R>(work: Effect.Effect<A,E,R>, fallback: Code): Effect.Effect<A,FixedFailure,R> {
 return Effect.uninterruptibleMask(restore => restore(work).pipe(Effect.catchCause(cause => {
  const cleanup = cause.reasons.some(r => (r._tag === "Fail" || r._tag === "Die") && codeOf(r._tag === "Fail" ? r.error : r.defect,fallback) === "private_stdio_cleanup");
  if (cleanup) return Effect.fail(fixedFailure("private_stdio_cleanup"));
  if (cause.reasons.some(r => r._tag === "Interrupt")) return Effect.interrupt;
  const fail = cause.reasons.find(r => r._tag === "Fail");
  return Effect.fail(fixedFailure(fail?._tag === "Fail" ? codeOf(fail.error,fallback) : fallback));
 })));
}
function utf8Length(text: string, stopAfter = Infinity): number {
 let n=0;
 for(let i=0;i<text.length;i++) {
  const c=text.charCodeAt(i);
  if(c<128)n++;else if(c<2048)n+=2;else if(c>=0xd800&&c<=0xdbff){const d=text.charCodeAt(++i);if(!(d>=0xdc00&&d<=0xdfff))refuse("private_stdio_input");n+=4;}
  else if(c>=0xdc00&&c<=0xdfff)refuse("private_stdio_input");else n+=3;
   if(n>stopAfter)return n;
 }
 return n;
}
const white=(c:number)=>c>=9&&c<=13||c===32||c===133||c===160||c===5760||c>=8192&&c<=8202||c===8232||c===8233||c===8239||c===8287||c===12288;
/** Rust1.88 Unicode16 White_Space, separate from JS trim/BOM semantics. */
function trimRust(text:string):string {let lo=0,hi=text.length;while(lo<hi&&white(text.charCodeAt(lo)))lo++;while(hi>lo&&white(text.charCodeAt(hi-1)))hi--;return text.slice(lo,hi);}
/** Utf8Chunks maximal invalid subpart: consume only valid continuation prefix. */
function lossy(raw:readonly number[]):string {
 const fragments:string[]=[];let at=0;
 while(at<raw.length) {
  const first=raw[at++]!;if(first<128){fragments.push(String.fromCharCode(first));continue;}
  let width=first>=0xc2&&first<=0xdf?2:first>=0xe0&&first<=0xef?3:first>=0xf0&&first<=0xf4?4:0;
  if(!width){fragments.push("\ufffd");continue;}
  let scalar=first&(width===2?31:width===3?15:7),valid=true;
  for(let pos=1;pos<width;pos++) {
   const next=raw[at];let ok=next!==undefined&&next>=0x80&&next<=0xbf;
   if(pos===1&&first===0xe0)ok=ok&&next!>=0xa0;
   if(pos===1&&first===0xed)ok=ok&&next!<=0x9f;
   if(pos===1&&first===0xf0)ok=ok&&next!>=0x90;
   if(pos===1&&first===0xf4)ok=ok&&next!<=0x8f;
   if(!ok){valid=false;break;}at++;scalar=(scalar<<6)|(next!&63);
  }
  fragments.push(valid?String.fromCodePoint(scalar):"\ufffd");
 }
 return fragments.join("");
}
function rawSlot(input:unknown):number[] {
 if(typeof input!=="string"||input.length>8192||input.length%2||!/^[0-9a-f]*$/.test(input))refuse("private_stdio_input");
 const out:number[]=[];for(let i=0;i<input.length;i+=2)out.push(Number.parseInt(input.slice(i,i+2),16));return out;
}
export function createStdioFrames(trusted:{readonly current:Current;readonly owner:IoOwner;readonly dispatcher:FrameDispatcher}):Effect.Effect<StdioFrames,FixedFailure,Scope.Scope> {
 return Effect.gen(function*(){
  let live=true,poisoned=false,busy=false;
  const waiters=new Set<(effect:Effect.Effect<void>)=>void>();
  const closed=Effect.callback<void>(resume=>{if(!live){resume(Effect.void);return;}waiters.add(resume);return Effect.sync(()=>{waiters.delete(resume);});});
  yield* Effect.addFinalizer(()=>Effect.sync(()=>{live=false;const pending=[...waiters];waiters.clear();for(const r of pending)r(Effect.void);}));
  const lifetime:CapturedLifetime=Object.freeze({isLive:()=>live&&!poisoned,closed});
  const current=trusted.current.check.bind(trusted.current),withIo=trusted.owner.withIo.bind(trusted.owner);
  const handle=trusted.dispatcher.handle.bind(trusted.dispatcher);
  const availability=Object.freeze({...trusted.dispatcher.availability});
  if(!(availability.profile==="synthetic_source_framing"&&availability.maximumDecodedUTF8Bytes===6291456||availability.profile==="existing_private_rpc"&&availability.maximumDecodedUTF8Bytes===65536))return yield* Effect.fail(fixedFailure("private_stdio_dispatch_unavailable"));
  const tickets=new WeakSet<object>(),lines=new WeakMap<object,string>(),replies=new WeakMap<object,{line:object,text:string}>(),pieces=new WeakMap<object,{reply:object,text:string}>(),terminals=new WeakMap<object,TerminalMetadata>();
  const alive=()=>{if(poisoned)refuse("private_stdio_cleanup");if(!live)refuse("owned_handoff_closed");};
  const check=(phase:Phase):Effect.Effect<void,FixedFailure>=>Effect.uninterruptibleMask(restore=>Effect.gen(function*(){
    yield* attempt(alive,"owned_handoff_closed");
    const result=yield* Effect.exit(restore(safe(Effect.suspend(()=>current(phase)),"private_stdio_authority")));
    if(result._tag==="Failure"&&result.cause.reasons.some(r=>r._tag==="Interrupt"||((r._tag==="Fail"||r._tag==="Die")&&codeOf(r._tag==="Fail"?r.error:r.defect,"private_stdio_authority")==="private_stdio_cleanup")))return yield* Effect.failCause(result.cause);
    // A trusted callback can close the captured Scope and then fail or defect.
    // Expiry is checked after actual callback completion even on that failure.
    yield* attempt(alive,"owned_handoff_closed");
    if(result._tag==="Failure")return yield* Effect.failCause(result.cause);
   }));
  const exchange=(request:unknown):Effect.Effect<OwnedTerminal,FixedFailure>=>Effect.suspend(()=>{
   const admission=attempt(()=>{alive();if(typeof request!=="string"||request!=="{\"version\":1}")refuse("private_stdio_input");if(busy)refuse("private_stdio_busy");busy=true;},"private_stdio_input");
   const work = Effect.gen(function*(){
    yield* check("before_allocation");let allocated:object|null=null,callbackLive=true,used=false,reachedEOF=false;
    const issuer:CommitIssuer=Object.freeze({commit(){if(!callbackLive||allocated||!lifetime.isLive())return null;const t:OwnedIoTicket={[ticketBrand]:true};Object.freeze(t);tickets.add(t);allocated=t;return t;}});
    const use=(ticket:OwnedIoTicket,io:Io)=>Effect.gen(function*(){
     yield* attempt(()=>{alive();if(used||!member(ticket)||!tickets.has(ticket)||ticket!==allocated)refuse("private_stdio_owned");used=true;},"private_stdio_owned");
     const next=io.next.bind(io),write=io.write.bind(io),flush=io.flush.bind(io);
     let buffer:number[]=[],overflow=false;
     const dispatch=(text:string)=>Effect.gen(function*(){
      if(!text)return;
      if(utf8Length(text)>availability.maximumDecodedUTF8Bytes)return yield* Effect.fail(fixedFailure("private_stdio_dispatch_unavailable"));
      const line:OwnedLine={[lineBrand]:true};Object.freeze(line);lines.set(line,text);yield* check("before_dispatch");let active=true;
      const view:LineView=Object.freeze({text(input:unknown){return Effect.suspend(()=>{
       if(!active||!lifetime.isLive()||input!==line||!member(input)||!lines.has(input))return Effect.succeed(null);
       return check("before_dispatch").pipe(Effect.andThen(attempt(()=>active&&lifetime.isLive()&&input===line?lines.get(line)!:null,"private_stdio_owned")));
      });}});
      const issue:ReplyIssuer=Object.freeze({issue(input:unknown,primitive:unknown){if(!active||!lifetime.isLive()||input!==line||!member(input)||!lines.has(input)||typeof primitive!=="string")return null;if(primitive.length>65536)return null;try{if(utf8Length(primitive,65536)>65536)return null;}catch{return null;}const r:OwnedReply={[replyBrand]:true};Object.freeze(r);replies.set(r,{line,text:primitive});return r;}});
      const reply=yield* safe(Effect.suspend(()=>handle(line,view,issue)).pipe(Effect.ensuring(Effect.sync(()=>{active=false;}))),"private_stdio_dispatch");
      yield* check("before_dispatch");if(reply===null)return;
      const data=yield* attempt(()=>{if(!member(reply))refuse("private_stdio_owned");const d=replies.get(reply);if(!d||d.line!==line)refuse("private_stdio_owned");return d;},"private_stdio_owned");
      for(const text of [data.text,"\n"]){
       yield* check("before_publication");let writing=true;const piece:OwnedWritePiece={[pieceBrand]:true};Object.freeze(piece);pieces.set(piece,{reply,text});
       const writeView:WriteView=Object.freeze({text(input:unknown){return Effect.suspend(()=>{
        if(!writing||!lifetime.isLive()||input!==piece||!member(input)||!pieces.has(input))return Effect.succeed(null);
        return check("before_publication").pipe(Effect.andThen(attempt(()=>writing&&lifetime.isLive()&&input===piece?pieces.get(piece)!.text:null,"private_stdio_owned")));
       });}});
       yield* safe(Effect.suspend(()=>write(ticket,piece,writeView)).pipe(Effect.ensuring(Effect.sync(()=>{writing=false;}))),"private_stdio_sink");yield* check("before_publication");
      }
      yield* check("before_publication");let flushing=true;
      const gate:FlushGate=Object.freeze({beforeFlush(input:unknown){return Effect.suspend(()=>{
       if(!flushing||!lifetime.isLive())return Effect.fail(fixedFailure("owned_handoff_closed"));
       if(input!==ticket||!member(input)||!tickets.has(input))return Effect.fail(fixedFailure("private_stdio_owned"));
       return check("before_publication").pipe(Effect.andThen(attempt(()=>{if(!flushing||!lifetime.isLive())refuse("owned_handoff_closed");if(input!==ticket)refuse("private_stdio_owned");},"private_stdio_owned")));
      });}});
      yield* safe(Effect.suspend(()=>flush(ticket,gate)).pipe(Effect.ensuring(Effect.sync(()=>{flushing=false;}))),"private_stdio_sink");yield* check("before_publication");
     });
     while(true){
      yield* check("before_read");let reading=true;
      const gate:SourceGate=Object.freeze({beforeRead(input:unknown){return Effect.suspend(()=>{
       if(!reading||!lifetime.isLive())return Effect.fail(fixedFailure("owned_handoff_closed"));
       if(input!==ticket||!member(input)||!tickets.has(input))return Effect.fail(fixedFailure("private_stdio_owned"));
       return check("before_read").pipe(Effect.andThen(attempt(()=>{if(!reading||!lifetime.isLive())refuse("owned_handoff_closed");if(input!==ticket)refuse("private_stdio_owned");},"private_stdio_owned")));
      });}});
      const chunk=yield* safe(Effect.suspend(()=>next(ticket,gate)).pipe(Effect.ensuring(Effect.sync(()=>{reading=false;}))),"private_stdio_source");yield* check("before_read");
      if(chunk===null){if(buffer.length||overflow)yield* dispatch(overflow?"{":trimRust(lossy(buffer)));reachedEOF=true;break;}
      const raw=yield* attempt(()=>rawSlot(chunk),"private_stdio_input");
      for(const byte of raw){
       if(byte===10){const text=overflow?"{":trimRust(lossy(buffer));buffer=[];overflow=false;yield* dispatch(text);}
       else if(!overflow){if(buffer.length===2097152){buffer=[];overflow=true;}else buffer.push(byte);}
      }
     }
    });
    yield* safe(Effect.suspend(()=>withIo(lifetime,issuer,use)).pipe(Effect.ensuring(Effect.sync(()=>{callbackLive=false;}))),"private_stdio_cleanup");
    yield* attempt(()=>{if(!used||!reachedEOF||allocated===null)refuse("private_stdio_owned");},"private_stdio_owned");
    yield* check("assert_current");const terminal:OwnedTerminal={[terminalBrand]:true};Object.freeze(terminal);terminals.set(terminal,Object.freeze({input_EOF:true,aggregate_io_release_ACK:true,publication:"acknowledged_private_sink_only"}));return terminal;
   });
   return Effect.uninterruptibleMask(restore=>admission.pipe(Effect.andThen(restore(work).pipe(Effect.catchCause(cause=>{
    if(cause.reasons.some(r=>(r._tag==="Fail"||r._tag==="Die")&&codeOf(r._tag==="Fail"?r.error:r.defect,"private_stdio_dispatch")==="private_stdio_cleanup"))poisoned=true;
    return Effect.failCause(cause);
   }),Effect.ensuring(Effect.sync(()=>{busy=false;}))))));
  });
  const frames:StdioFrames=Object.freeze({exchange,inspect(input:unknown){return member(input)?terminals.get(input)??null:null;}});
  return frames;
 });
}
