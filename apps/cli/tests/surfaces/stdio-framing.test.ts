import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Scope from "effect/Scope";
import * as Exit from "effect/Exit";
import { createStdioFrames, fixedFailure, type Code, type FixedFailure, type Current, type Phase,
  type CapturedLifetime, type CommitIssuer, type IoOwner, type Io, type FrameDispatcher,
  type ReplyIssuer, type OwnedLine, type OwnedReply, type OwnedIoTicket, type StdioFrames,
  type TerminalMetadata } from "../../src/surfaces/stdio-framing.js";
import { stdioFramingFixture } from "./stdio-framing-vectors.js";

interface Action { readonly at:string; readonly op:string; readonly ordinal:number }
interface Stimulus {
  readonly request:unknown; readonly availability:string;
  readonly raw_chunks:readonly {readonly hex:string;readonly repeat:number;readonly maximum_chunk_bytes:number}[];
  readonly EOF:boolean;
  readonly source_semantic_witnesses:readonly {readonly kind:string;readonly id?:string}[];
  readonly source_return_override?:string; readonly actions:readonly Action[];
  readonly setup?:{readonly kind:string;readonly observation_window:string;readonly request:string};
  readonly reply_primitive?:{readonly encoding:string;readonly segments?:readonly {readonly text:string;readonly repeat:number}[];readonly units?:readonly number[]};
}
interface ByteWitness {readonly segments:readonly {readonly text:string;readonly repeat:number}[];readonly utf8_bytes:number;readonly sha256:string}
type AttemptedOutputTrace={phase:"value"|"LF";bytes:ByteWitness;ack:boolean}|{phase:"flush";ack:boolean};
interface ActualCounts {
 allocation_calls:number;aggregate_release_attempts:number;aggregate_release_ACKs:number;
 source_next_calls:number;source_gate_calls:number;source_materializations:number;dispatcher_calls:number;
 line_read_calls:number;reply_issue_calls:number;write_calls:number;piece_read_calls:number;
 flush_calls:number;flush_gate_calls:number;authority_calls:number;property_traps:number;
 callbacks_after_expiry:number;outstanding_watchers:number;outstanding_phase_fibers:number;
}
type SceneKind="completion"|"private_failure"|"interruption";
interface SceneObservationFixed {
 readonly kind:SceneKind;readonly fixed_failure:Code|null;readonly returned_terminal:TerminalMetadata|null;
 readonly lexical_lines:readonly ByteWitness[];readonly output_trace:readonly AttemptedOutputTrace[];
 readonly stdout_utf8:ByteWitness|null;readonly stderr_utf8:string;readonly publication_ambiguous:boolean;
 readonly raw_buffer_peak:number;readonly pending_sink_calls_peak:number;readonly counts:ActualCounts;
 readonly provider_echo:boolean;readonly late_noncleanup_callbacks:number;readonly native_pipe_qualified:false;
}
type SceneObservation=SceneObservationFixed&Readonly<Record<string,unknown>>;
function counts():ActualCounts{return {allocation_calls:0,aggregate_release_attempts:0,aggregate_release_ACKs:0,
 source_next_calls:0,source_gate_calls:0,source_materializations:0,dispatcher_calls:0,line_read_calls:0,
 reply_issue_calls:0,write_calls:0,piece_read_calls:0,flush_calls:0,flush_gate_calls:0,authority_calls:0,
 property_traps:0,callbacks_after_expiry:0,outstanding_watchers:0,outstanding_phase_fibers:0};}
function difference(after:ActualCounts,before:ActualCounts):ActualCounts{return {
 allocation_calls:after.allocation_calls-before.allocation_calls,aggregate_release_attempts:after.aggregate_release_attempts-before.aggregate_release_attempts,
 aggregate_release_ACKs:after.aggregate_release_ACKs-before.aggregate_release_ACKs,source_next_calls:after.source_next_calls-before.source_next_calls,
 source_gate_calls:after.source_gate_calls-before.source_gate_calls,source_materializations:after.source_materializations-before.source_materializations,
 dispatcher_calls:after.dispatcher_calls-before.dispatcher_calls,line_read_calls:after.line_read_calls-before.line_read_calls,
 reply_issue_calls:after.reply_issue_calls-before.reply_issue_calls,write_calls:after.write_calls-before.write_calls,
 piece_read_calls:after.piece_read_calls-before.piece_read_calls,flush_calls:after.flush_calls-before.flush_calls,
 flush_gate_calls:after.flush_gate_calls-before.flush_gate_calls,authority_calls:after.authority_calls-before.authority_calls,
 property_traps:after.property_traps-before.property_traps,callbacks_after_expiry:after.callbacks_after_expiry-before.callbacks_after_expiry,
 outstanding_watchers:after.outstanding_watchers-before.outstanding_watchers,outstanding_phase_fibers:after.outstanding_phase_fibers-before.outstanding_phase_fibers};}
function digest(text:string):ByteWitness{return {segments:[{text,repeat:1}],utf8_bytes:Buffer.byteLength(text),sha256:createHash("sha256").update(text).digest("hex")};}
function sameBytes(value:unknown):unknown {
 if(value&&typeof value==="object"&&"segments"in value&&Array.isArray(value.segments)&&"utf8_bytes"in value&&"sha256"in value){
  let text="";for(const segment of value.segments){assert.equal(typeof segment.text,"string");assert.equal(typeof segment.repeat,"number");text+=segment.text.repeat(segment.repeat);}
  return {text,utf8_bytes:value.utf8_bytes,sha256:value.sha256};
 }
 if(Array.isArray(value))return value.map(sameBytes);
 if(value&&typeof value==="object")return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,sameBytes(item)]));
 return value;
}
function failureCode<A>(exit:Exit.Exit<A,FixedFailure>):Code|null {
 if(Exit.isSuccess(exit))return null;const reason=exit.cause.reasons.find(r=>r._tag==="Fail");return reason?._tag==="Fail"?reason.error.code:null;
}
// This seed executes the same public scoped ownership protocol in another factory.
function foreignTicketSeed():Effect.Effect<{ticket:OwnedIoTicket;counts:ActualCounts;terminal:TerminalMetadata|null},FixedFailure> {
 return Effect.scoped(Effect.gen(function*():Effect.gen.Return<{ticket:OwnedIoTicket;counts:ActualCounts;terminal:TerminalMetadata|null},FixedFailure,Scope.Scope>{
  const c=counts();let ticket:OwnedIoTicket|null=null;
  const io:Io={next:(t,gate)=>gate.beforeRead(t).pipe(Effect.as(null)),write:()=>Effect.void,flush:()=>Effect.void};
  const owner:IoOwner={withIo:<A>(_life:CapturedLifetime,issuer:CommitIssuer,use:(t:OwnedIoTicket,io:Io)=>Effect.Effect<A,FixedFailure>):Effect.Effect<A,FixedFailure>=>Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,FixedFailure,Scope.Scope>{
   const owned=yield* Effect.acquireRelease(Effect.sync(()=>{const t=issuer.commit();assert.ok(t);ticket=t;c.allocation_calls++;return t;}),()=>Effect.sync(()=>{c.aggregate_release_attempts++;c.aggregate_release_ACKs++;}));
   return yield* use(owned,io);
  }))};
  const frames=yield* createStdioFrames({current:{check:()=>Effect.void},owner,dispatcher:{availability:{profile:"synthetic_source_framing",maximumDecodedUTF8Bytes:6291456},handle:()=>Effect.succeed(null)}});
  const terminal=yield* frames.exchange("{\"version\":1}");assert.ok(ticket);return {ticket,counts:c,terminal:frames.inspect(terminal)};
 }));
}
function runScene(input:Stimulus):Effect.Effect<SceneObservation,FixedFailure> {
 return Effect.scoped(Effect.gen(function*():Effect.gen.Return<SceneObservation,FixedFailure,Scope.Scope>{
  const original=yield* Scope.make();yield* Effect.addFinalizer(()=>Scope.close(original,Exit.succeed(undefined)));
  let originalLive=true;yield* Scope.addFinalizer(original,Effect.sync(()=>{originalLive=false;}));
  const c=counts(),phaseOrdinals=new Map<string,number>(),reachedActions=new Set<number>();
  let seedMode=false,revoked=false,frames:StdioFrames|null=null,currentContext="",lateCallbacks=0;
  let baseline=counts(),busyExit:Exit.Exit<unknown,FixedFailure>|null=null,busyCounts:ActualCounts|null=null;
  let targetTicket:OwnedIoTicket|null=null,seedTicket:OwnedIoTicket|null=null,seedReply:OwnedReply|null=null,seedLine:OwnedLine|null=null,targetLine:OwnedLine|null=null;
  let targetLife:CapturedLifetime|null=null,dispatchLive=false,valueLive=false,controllerCloseCalls=0;
  const extras:Record<string,unknown>={},lexical:string[]=[],trace:AttemptedOutputTrace[]=[];
  const knownDefects=new WeakMap<object,Code>();
  const failDefect=(code:Code)=>{const error=fixedFailure(code);knownDefects.set(error,code);return Effect.die(error);};
  const cleanupFailed=<A>(exit:Exit.Exit<A,FixedFailure>)=>Exit.isFailure(exit)&&exit.cause.reasons.some(r=>r._tag==="Fail"?r.error.code==="private_stdio_cleanup":r._tag==="Die"&&r.defect!==null&&(typeof r.defect==="object"||typeof r.defect==="function")&&knownDefects.get(r.defect)==="private_stdio_cleanup");
  const signal=yield* Deferred.make<string>(),cleanupEntered=yield* Deferred.make<void>(),cleanupGate=yield* Deferred.make<void>();
  const peek=(at:string,ordinal=1)=>seedMode?undefined:input.actions.find(a=>a.at===at&&a.ordinal===ordinal)?.op;
  const action=(at:string,ordinal=1)=>{if(seedMode)return undefined;const index=input.actions.findIndex(a=>a.at===at&&a.ordinal===ordinal);if(index<0)return undefined;reachedActions.add(index);return input.actions[index]!.op;};
  const nextOrdinal=(at:string)=>{const n=(phaseOrdinals.get(at)??0)+1;phaseOrdinals.set(at,n);return n;};
  const enter=()=>{if(!originalLive){lateCallbacks++;c.callbacks_after_expiry++;}};
  let resumedSuspensions=0;
  const suspend:(op:string)=>Effect.Effect<never> = op=>Effect.gen(function*(){yield* Deferred.succeed(signal,op);return yield* Effect.never;}).pipe(Effect.tap(()=>Effect.sync(()=>{resumedSuspensions++;})));
  const proxyFor=<A extends object>(target:A):A=>new Proxy(target,{get(){c.property_traps++;throw "SYNTHETIC_SECRET";},getPrototypeOf(){c.property_traps++;throw "SYNTHETIC_SECRET";},ownKeys(){c.property_traps++;throw "SYNTHETIC_SECRET";}});
  const proxy=()=>proxyFor({});
  const savedGates:{source:Effect.Effect<void,FixedFailure>|null;flush:Effect.Effect<void,FixedFailure>|null}={source:null,flush:null};
  let savedLine:Effect.Effect<string|null,FixedFailure>|null=null,savedPiece:Effect.Effect<string|null,FixedFailure>|null=null,savedIssuer:ReplyIssuer|null=null,savedLineToken:OwnedLine|null=null;
  let pendingSink=0,peakSink=0,rawPeak=0,rawCount=0,bufferSize=0,overflow=false,empty=0,overflowLines=0,frameCount=0,responseCount=0;
  let observedRaw:number[]=[],sourceCallbackLive=false,pendingSlot:{hex:string|null;ordinal:number;callbackEnded:boolean}|null=null;
  const white=(n:number)=>n>=9&&n<=13||n===32||n===133||n===160||n===5760||n>=8192&&n<=8202||n===8232||n===8233||n===8239||n===8287||n===12288;
  const finishObservedLine=()=>{if(overflow){overflowLines++;frameCount++;}else{const text=Buffer.from(observedRaw).toString("utf8");if([...text].every(ch=>white(ch.codePointAt(0)!)))empty++;else frameCount++;}observedRaw=[];bufferSize=0;overflow=false;};
  // Admission-accounting model; not a candidate buffer/heap observer.
  const admitSlot=(hex:string|null)=>{if(hex===null){if(bufferSize||overflow)finishObservedLine();return;}if(!/^(?:[0-9a-f]{2})*$/.test(hex)||hex.length>8192)return;
   for(const byte of Buffer.from(hex,"hex")){if(byte===10)finishObservedLine();else if(!overflow){if(bufferSize===2097152){overflow=true;bufferSize=0;observedRaw=[];}else{observedRaw.push(byte);bufferSize++;rawPeak=Math.max(rawPeak,bufferSize);}}}};
  const observedRead:(kind:"line"|"piece",effect:Effect.Effect<string|null,FixedFailure>)=>Effect.Effect<string|null,FixedFailure>=(kind,effect)=>Effect.suspend(()=>{if(kind==="line")c.line_read_calls++;else c.piece_read_calls++;return effect;});
  const probe:(work:Effect.Effect<unknown,FixedFailure>,key:string)=>Effect.Effect<void>=(work,key)=>Effect.gen(function*(){const before=c.authority_calls;const exit=yield* Effect.exit(work);extras[key]=Exit.isSuccess(exit)?exit.value:failureCode(exit)??"interrupted";extras.expired_probe_checks=c.authority_calls-before;});
  const current:Current={check:(phase:Phase)=>Effect.gen(function*():Effect.gen.Return<void,FixedFailure>{
   enter();c.authority_calls++;const op=action(`current.${phase}`,nextOrdinal(`current.${phase}`));
   if(revoked||op==="deny")return yield* Effect.fail(fixedFailure("private_stdio_authority"));
   if(op==="close_original_then_fixed_fail"||op==="close_original_then_provider_defect"){
    yield* Scope.close(original,Exit.succeed(undefined));extras.original_close_completed=!originalLive;extras.original_close_claims_resource_ACK=false;extras.original_scope_live_after_callback=originalLive;
    return yield* (op==="close_original_then_fixed_fail"?Effect.fail(fixedFailure("private_stdio_authority")):failDefect("private_stdio_authority"));
   }
   const inner=action(currentContext);if(inner?.startsWith("suspend_then_"))return yield* suspend(inner);
   if(op==="execute_saved_source_gate"&&savedGates.source)yield* probe(savedGates.source,"expired_gate_result");
   if(op==="probe_saved_flush_gate"&&savedGates.flush)yield* probe(savedGates.flush,"expired_gate_result");
   if(op==="probe_expired_dispatch_issuer_view"&&savedLine&&savedIssuer&&savedLineToken){const before=c.authority_calls;extras.expired_issue_result=savedIssuer.issue(savedLineToken,"{}");extras.expired_read_result=yield* savedLine;extras.expired_probe_checks=c.authority_calls-before;extras.expired_probe_traps=c.property_traps;}
   if(op==="execute_saved_lazy_piece_read_after_value_callback_exit"&&savedPiece){const before=c.authority_calls;const value=yield* observedRead("piece",savedPiece);extras.saved_read_results=[value];extras.saved_read_extra_authority_calls=c.authority_calls-before;extras.saved_read_extra_text_materializations=value===null?0:1;extras.original_scope_live_at_reentry=originalLive;extras.value_callback_live_at_reentry=valueLive;}
   // The primitive has returned, its real callback has ended, and this is its
   // successful captured-current postcheck. No final Exit/case ID selects this.
   if(phase==="before_read"&&pendingSlot?.callbackEnded&&!sourceCallbackLive&&originalLive&&(targetLife===null||targetLife.isLive())){admitSlot(pendingSlot.hex);pendingSlot=null;}
  })};
  const chunks:string[]=[];for(const segment of input.raw_chunks){const bytes=segment.hex.repeat(segment.repeat);for(let at=0;at<bytes.length;at+=segment.maximum_chunk_bytes*2)chunks.push(bytes.slice(at,at+segment.maximum_chunk_bytes*2));if(bytes.length===0)chunks.push("");}
  let chunkIndex=0,semanticIndex=0,seedChunkIndex=0;
  const seedPing="7b226a736f6e727063223a22322e30222c226964223a312c226d6574686f64223a2270696e67227d0a";
  const io:Io={next:(ticket,gate)=>Effect.gen(function*():Effect.gen.Return<string|null,FixedFailure>{
   enter();sourceCallbackLive=true;c.source_next_calls++;const n=nextOrdinal("source.next");
   if(action("source.next",n)==="fail_fixed")return yield* Effect.fail(fixedFailure("private_stdio_source"));
   const gateOp=action("source.read_gate",n),previousSource=savedGates.source;savedGates.source=gate.beforeRead(ticket);
   if(gateOp==="save_then_close_original_then_provide_freshScope_and_replacement_current"){
    yield* Scope.close(original,Exit.succeed(undefined));let replacementCalls=0;
    current.check=()=>Effect.sync(()=>{replacementCalls++;});const before=c.authority_calls;
    const exit=yield* Effect.exit(Effect.scoped(savedGates.source));extras.expired_gate_result=failureCode(exit);extras.replacement_authority_calls=replacementCalls;extras.probe_checks=c.authority_calls-before;
    if(Exit.isFailure(exit))return yield* Effect.failCause(exit.cause);return null;
   }
   if(previousSource&&n>1){const before=c.authority_calls;const old=yield* Effect.exit(previousSource);extras.source_gate_expired_probe=failureCode(old);extras.expired_probe_authority_calls=c.authority_calls-before;}
   const before=c.authority_calls;currentContext="source.read_gate.current";
   const gateInput=gateOp==="foreign_ticket_Proxy"?proxy():gateOp==="other_factory_ticket"?seedTicket:ticket;
   const result=yield* Effect.exit(gate.beforeRead(gateInput));currentContext="";
   if(Exit.isFailure(result)){extras.probe_checks=c.authority_calls-before;extras.probe_traps=c.property_traps;return yield* Effect.failCause(result.cause);}c.source_gate_calls++;c.source_materializations++;
   let hex=seedMode?(seedChunkIndex++===0?seedPing:null):chunkIndex<chunks.length?chunks[chunkIndex++]!:null;
   if(action("source.after_gate_before_return",n)==="revoke_destination")revoked=true;
   if(action("source.after_gate",n)==="return_invalid_hex")hex=input.source_return_override??"gg";
   if(hex!==null&&/^(?:[0-9a-f]{2})*$/.test(hex))rawCount+=hex.length/2;
   pendingSlot={hex,ordinal:n,callbackEnded:false};return hex;
  }).pipe(Effect.ensuring(Effect.sync(()=>{sourceCallbackLive=false;if(pendingSlot)pendingSlot.callbackEnded=true;}))),
  write:(_ticket,piece,view)=>Effect.gen(function*():Effect.gen.Return<void,FixedFailure>{
   enter();c.write_calls++;pendingSink++;peakSink=Math.max(peakSink,pendingSink);
   const phase:"value"|"LF"=c.write_calls%2===1?"value":"LF";
   valueLive=phase==="value";const at=`sink.${phase}.read`,op=action(at);currentContext=`${at}.current`;
   const lazy=view.text(op==="foreign_piece_Proxy"?proxy():piece);savedPiece=lazy;
   const before=c.authority_calls;const read=yield* Effect.exit(observedRead("piece",lazy));currentContext="";
   if(Exit.isFailure(read))return yield* Effect.failCause(read.cause);
   if(read.value===null){extras.probe_checks=c.authority_calls-before;extras.probe_traps=c.property_traps;return yield* Effect.fail(fixedFailure("private_stdio_owned"));}
   if(op==="save_same_lazy_piece_read_execute_success_revoke_then_reexecute_before_publication"){
    extras.saved_read_results=[digest(read.value)];revoked=true;const before=c.authority_calls;const again=yield* Effect.exit(observedRead("piece",lazy));
    extras.second_read_authority_calls=c.authority_calls-before;extras.second_read_text_materializations=Exit.isSuccess(again)&&again.value!==null?1:0;
    extras.original_scope_live_at_reentry=originalLive;extras.value_callback_live_at_reentry=valueLive;extras.second_read_fixed_failure=failureCode(again);
    if(Exit.isFailure(again))return yield* Effect.failCause(again.cause);return yield* Effect.fail(fixedFailure("private_stdio_owned"));
   }
   // A write may have reached a sink before its failing/lost acknowledgement.
   const attempt:AttemptedOutputTrace={phase,bytes:digest(read.value),ack:false};trace.push(attempt);
   const after=action(`sink.${phase}.after_read`);if(after?.startsWith("suspend_then_"))return yield* suspend(after);
   if(after==="fail_fixed")return yield* Effect.fail(fixedFailure("private_stdio_sink"));attempt.ack=true;
  }).pipe(Effect.ensuring(Effect.sync(()=>{pendingSink--;valueLive=false;currentContext="";}))),
  flush:(ticket,gate)=>Effect.gen(function*():Effect.gen.Return<void,FixedFailure>{
   enter();c.flush_calls++;pendingSink++;peakSink=Math.max(peakSink,pendingSink);savedGates.flush=gate.beforeFlush(ticket);
   const op=action("sink.flush.gate"),before=c.authority_calls;const exit=yield* Effect.exit(gate.beforeFlush(op==="foreign_ticket_Proxy"?proxy():ticket));
   if(Exit.isFailure(exit)){extras.probe_checks=c.authority_calls-before;extras.probe_traps=c.property_traps;return yield* Effect.failCause(exit.cause);}c.flush_gate_calls++;
   if(action("sink.flush.after_gate")==="fail_fixed")return yield* Effect.fail(fixedFailure("private_stdio_sink"));trace.push({phase:"flush",ack:true});
  }).pipe(Effect.ensuring(Effect.sync(()=>{pendingSink--;})))};
  const dispatcher:FrameDispatcher={availability:input.availability==="existing_private_rpc"?{profile:"existing_private_rpc",maximumDecodedUTF8Bytes:65536}:{profile:"synthetic_source_framing",maximumDecodedUTF8Bytes:6291456},
   handle:(line,view,issuer)=>Effect.gen(function*():Effect.gen.Return<OwnedReply|null,FixedFailure>{
    enter();dispatchLive=true;c.dispatcher_calls++;targetLine=line;savedLineToken=line;savedIssuer=issuer;
    const op=action("dispatcher.line_read");currentContext="dispatcher.line_read.current";const lazy=view.text(op==="foreign_line_Proxy"?proxy():line);savedLine=lazy;
    const before=c.authority_calls;const exit=yield* Effect.exit(observedRead("line",lazy));currentContext="";
    if(Exit.isFailure(exit))return yield* Effect.failCause(exit.cause);
    if(exit.value===null){extras.probe_checks=c.authority_calls-before;extras.probe_traps=c.property_traps;return yield* Effect.fail(fixedFailure("private_stdio_owned"));}
    lexical.push(exit.value);
    if(op==="save_same_lazy_line_read_execute_success_revoke_then_reexecute"){
     extras.saved_read_results=[digest(exit.value)];revoked=true;const before=c.authority_calls;const again=yield* Effect.exit(observedRead("line",lazy));extras.second_read_authority_calls=c.authority_calls-before;
     extras.second_read_text_materializations=Exit.isSuccess(again)&&again.value!==null?1:0;extras.second_read_fixed_failure=failureCode(again);extras.original_scope_live_at_reentry=originalLive;extras.dispatcher_callback_live_at_reentry=dispatchLive;
     if(Exit.isFailure(again))return yield* Effect.failCause(again.cause);return yield* Effect.fail(fixedFailure("private_stdio_owned"));
    }
    const witness=seedMode?{kind:"source_ping",id:"1"}:input.source_semantic_witnesses[semanticIndex++];assert.ok(witness);
    if(witness.kind==="source_notification_no_response")return null;
    let wire=witness.kind==="source_ping"?`{"id":${witness.id},"jsonrpc":"2.0","result":{}}`:'{"error":{"code":-32700,"message":"Parse error"},"id":null,"jsonrpc":"2.0"}';
    if(input.reply_primitive&&!seedMode){const primitive=input.reply_primitive;
     if(primitive.encoding==="scalar_segments"){assert.ok(primitive.segments);wire=primitive.segments.map(s=>s.text.repeat(s.repeat)).join("");}
     else{assert.equal(primitive.encoding,"utf16_units");assert.ok(primitive.units);wire=String.fromCharCode(...primitive.units);}
     extras.reply_input_code_units=wire.length;
     let valid=true;for(let at=0;at<wire.length;at++){const code=wire.charCodeAt(at);if(code>=0xd800&&code<=0xdbff){const next=wire.charCodeAt(++at);if(!(next>=0xdc00&&next<=0xdfff))valid=false;}else if(code>=0xdc00&&code<=0xdfff)valid=false;}
     extras.reply_input_utf8_bytes=valid?Buffer.byteLength(wire):null;
    }
    c.reply_issue_calls++;const issued=issuer.issue(line,wire);
    if(input.reply_primitive&&!seedMode)extras.reply_issue_result=issued===null?null:"owned_reply";
    if(issued===null)return null;
    if(seedMode){seedReply=issued;seedLine=line;return null;}
    const replyOp=action("dispatcher.reply");
    if(replyOp==="foreign_reply_Proxy"){extras.probe_checks=0;extras.probe_traps=c.property_traps;return proxyFor(issued);}
    if(replyOp==="other_line_same_factory"){assert.ok(seedReply);responseCount++;return seedReply;}
    responseCount++;return issued;
   }).pipe(Effect.ensuring(Effect.sync(()=>{dispatchLive=false;currentContext="";})))};
  const withIo:IoOwner["withIo"]=<A>(life:CapturedLifetime,issuer:CommitIssuer,use:(ticket:OwnedIoTicket,io:Io)=>Effect.Effect<A,FixedFailure>):Effect.Effect<A,FixedFailure>=>
   Effect.uninterruptibleMask(restore=>Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,FixedFailure,Scope.Scope>{
    if(!life.isLive())return yield* Effect.fail(fixedFailure("owned_handoff_closed"));
    targetLife=life;let phase:Fiber.Fiber<A,FixedFailure>|null=null;
    let stopRequested=false,cancelRequested=false,watcherStarted=false,watcherCompletions=0,closedObservations=0,useCalls=0,commitCalls=0;
    const readyMode=peek("owner.before_prepare")==="assert_closed_watcher_registered_and_pending";
    const gapMode=peek("owner.prepare")==="close_original_synchronously_while_handle_unbound_then_suspend_interruptibly";
    const requestStop=(fiber:Fiber.Fiber<A,FixedFailure>):Effect.Effect<void>=>Effect.suspend(()=>{
     if(cancelRequested||fiber.pollUnsafe()!==undefined)return Effect.void;cancelRequested=true;
     if(gapMode)extras.phase_cancellation_requests=(typeof extras.phase_cancellation_requests==="number"?extras.phase_cancellation_requests:0)+1;
     return Fiber.interrupt(fiber);
    });
    c.outstanding_watchers++;
    const watcherBody:Effect.Effect<void>=Effect.gen(function*(){
     watcherStarted=true;yield* life.closed;closedObservations++;stopRequested=true;
     if(gapMode){extras.phase_handle_bound_at_watcher_replay=phase!==null;extras.latched_stop_before_handle_binding=phase===null&&stopRequested;}
     const actual=phase;if(actual!==null)yield* requestStop(actual);
    }).pipe(Effect.ensuring(Effect.sync(()=>{watcherCompletions++;c.outstanding_watchers--;})));
    const watcher=yield* Effect.forkChild(restore(watcherBody),{startImmediately:true});
    watcher.currentDispatcher.flush();
    // The known body has exactly one suspension, the original replayable close
    // Effect. Actual pending Exit and zero completion witness registration.
    assert.equal(watcherStarted,true);assert.equal(watcher.pollUnsafe(),undefined);assert.equal(watcherCompletions,0);
    if(action("owner.before_prepare")==="assert_closed_watcher_registered_and_pending"){
     extras.watcher_started_before_prepare=watcherStarted;extras.watcher_pending_before_prepare=watcher.pollUnsafe()===undefined;
     extras.watcher_completion_count_before_close=watcherCompletions;
    }
    c.outstanding_phase_fibers++;
    const phaseBody=Effect.scoped(Effect.gen(function*():Effect.gen.Return<A,FixedFailure,Scope.Scope>{
     const prepareOp=action("owner.prepare");let preparationResumed=false;
     const prepare:Effect.Effect<void>=Effect.gen(function*(){
      if(prepareOp==="close_original_synchronously_while_handle_unbound_then_suspend_interruptibly"){
       extras.phase_handle_bound_at_prepare_entry=phase!==null;extras.original_scope_live_at_prepare_entry=life.isLive();
       yield* Scope.close(original,Exit.succeed(undefined));extras.original_close_completed=!originalLive;extras.original_close_claims_resource_ACK=false;
       extras.phase_handle_bound_at_original_close=phase!==null;extras.original_scope_live_after_close=life.isLive();
       watcher.currentDispatcher.flush();assert.equal(closedObservations,1);assert.equal(watcherCompletions,1);assert.equal(stopRequested,true);
       return yield* Effect.never;
      }
      if(prepareOp?.startsWith("suspend_then_"))return yield* suspend(prepareOp);
     }).pipe(Effect.onInterrupt(()=>Effect.sync(()=>{extras.preparation_cancellation_ACK=true;extras.phase_resumed=preparationResumed;if(gapMode)extras.phase_resumed_after_prepare_suspend=preparationResumed;})));
     // The cancellation hook encloses synchronous close as well as suspension.
     yield* prepare;preparationResumed=true;
     if(!life.isLive()||stopRequested)return yield* Effect.fail(fixedFailure("owned_handoff_closed"));
     const ticket=yield* Effect.acquireRelease(Effect.sync(()=>{
      commitCalls++;const issued=issuer.commit();assert.ok(issued);targetTicket=issued;c.allocation_calls++;return issued;
     }),()=>Effect.gen(function*(){
      c.aggregate_release_attempts++;const op=action("owner.cleanup");
      if(op==="hold_then_ACK"){yield* Deferred.succeed(cleanupEntered,undefined);yield* Deferred.await(cleanupGate);}
      if(op?.startsWith("fail_fixed"))return yield* failDefect("private_stdio_cleanup");c.aggregate_release_ACKs++;
     }));
     const wait=action("owner.registered_wait");if(wait?.startsWith("suspend_then_"))return yield* suspend(wait);
     if(!life.isLive()||stopRequested)return yield* Effect.fail(fixedFailure("owned_handoff_closed"));
     useCalls++;return yield* use(ticket,io);
    })).pipe(Effect.ensuring(Effect.sync(()=>{c.outstanding_phase_fibers--;})));
    const started=yield* Effect.forkChild(restore(phaseBody),{startImmediately:true});phase=started;
    if(gapMode){extras.phase_handle_bound_after_start_returns=phase!==null;extras.latched_stop_consumed_after_handle_binding=stopRequested;}
    if(stopRequested)yield* requestStop(started);
    const wait=yield* Effect.exit(restore(Fiber.await(started)));
    // Protected stops and joins acknowledge cleanup, independent of ordinary
    // failure, external cancellation, or original-Scope closure.
    yield* Fiber.interrupt(watcher);yield* Fiber.interrupt(started);
    const ended=yield* Fiber.await(started);yield* Fiber.await(watcher);
    if(readyMode)extras.watcher_completion_count_after_close=watcherCompletions;
    if(gapMode){extras.closed_signal_observations=closedObservations;extras.phase_join_completed=started.pollUnsafe()!==undefined;extras.watcher_join_completed=watcher.pollUnsafe()!==undefined;extras.use_calls=useCalls;extras.commit_calls=commitCalls;extras.controller_close_calls=controllerCloseCalls;}
    if(cleanupFailed(ended))return yield* Effect.fail(fixedFailure("private_stdio_cleanup"));
    if(Exit.isFailure(wait))return yield* Effect.failCause(wait.cause);
    if(!life.isLive())return yield* Effect.fail(fixedFailure("owned_handoff_closed"));
    if(Exit.isFailure(ended))return yield* Effect.failCause(ended.cause);
    return ended.value;
   })));
  const owner:IoOwner={withIo};
  const construction:Effect.Effect<StdioFrames,FixedFailure,Scope.Scope>=createStdioFrames({current,owner,dispatcher});
  const supplied:Effect.Effect<StdioFrames,FixedFailure>=Scope.provide(original)(construction);
  frames=yield* supplied;const surface=frames;
  const separateSeed=input.setup?.kind==="separate_factory_EOF_ticket"||input.actions.some(a=>a.op==="other_factory_ticket");
  const priorReplySeed=input.setup?.kind==="same_factory_prior_exchange_reply"||input.actions.some(a=>a.op==="other_line_same_factory");
  let seedObservation:{counts:ActualCounts;terminal:boolean;relation:"same"|"different"}|null=null;
  if(separateSeed){const seed=yield* foreignTicketSeed();seedTicket=seed.ticket;seedObservation={counts:seed.counts,terminal:seed.terminal!==null,relation:"different"};}
  if(priorReplySeed){
   seedMode=true;const before={...c};const seedTerminal=yield* surface.exchange("{\"version\":1}");
   seedTicket=targetTicket;seedObservation={counts:difference(c,before),terminal:surface.inspect(seedTerminal)!==null,relation:"same"};assert.ok(seedReply);assert.ok(seedLine);
   seedMode=false;phaseOrdinals.clear();chunkIndex=0;semanticIndex=0;savedGates.source=null;savedGates.flush=null;savedLine=null;savedPiece=null;savedIssuer=null;savedLineToken=null;
   lexical.length=0;trace.length=0;rawPeak=0;rawCount=0;bufferSize=0;observedRaw=[];overflow=false;empty=0;overflowLines=0;frameCount=0;responseCount=0;pendingSlot=null;
   baseline={...c};
  }
  let request=input.request;const requestOp=action("request");
  if(requestOp==="throwing_Proxy")request=proxy();else if(requestOp==="revoked_Proxy"){const p=Proxy.revocable({},{});p.revoke();request=p.proxy;}
  if(action("controller.before_exchange")==="close_original"){controllerCloseCalls++;yield* Scope.close(original,Exit.succeed(undefined));}
  const main=yield* Effect.forkChild(surface.exchange(request),{startImmediately:true});
  const control:Effect.Effect<void,FixedFailure>=Effect.gen(function*(){
   const op=yield* Deferred.await(signal);
   if(op.includes("close_original")){controllerCloseCalls++;yield* Scope.close(original,Exit.succeed(undefined));extras.original_close_claims_resource_ACK=false;extras.original_close_completed=!originalLive;}
   else {
    if(op.includes("second_exchange")){const before={...c};busyExit=yield* Effect.exit(surface.exchange(input.request));busyCounts=difference(c,before);}
    const stopping=yield* Effect.forkChild(Fiber.interrupt(main),{startImmediately:true});
    if(peek("owner.cleanup")==="hold_then_ACK"){
     yield* Deferred.await(cleanupEntered);extras.before_cleanup_ACK_terminal=main.pollUnsafe()!==undefined;
     const busy=yield* Effect.exit(surface.exchange(input.request));extras.busy_before_cleanup_ACK=(failureCode(busy)==="private_stdio_busy"||failureCode(busy)==="owned_handoff_closed")&&main.pollUnsafe()===undefined&&c.aggregate_release_ACKs===baseline.aggregate_release_ACKs;
     extras.phase_resumed=resumedSuspensions!==0;yield* Deferred.succeed(cleanupGate,undefined);
    }
    yield* Fiber.join(stopping);
   }
   if(op.includes("close_original")&&peek("owner.cleanup")==="hold_then_ACK"){
    extras.original_close_completed_while_ACK_pending=!originalLive;yield* Deferred.await(cleanupEntered);extras.before_cleanup_ACK_terminal=main.pollUnsafe()!==undefined;
    const busy=yield* Effect.exit(surface.exchange(input.request));extras.busy_before_cleanup_ACK=(failureCode(busy)==="private_stdio_busy"||failureCode(busy)==="owned_handoff_closed")&&main.pollUnsafe()===undefined&&c.aggregate_release_ACKs===baseline.aggregate_release_ACKs;
    extras.phase_resumed=resumedSuspensions!==0;yield* Deferred.succeed(cleanupGate,undefined);
   }
  });
  const controller=yield* Effect.forkChild(control,{startImmediately:true});
  const result=yield* Fiber.await(main);yield* Fiber.interrupt(controller);
  let failure:Code|null=null,kind:SceneKind="completion",terminal:TerminalMetadata|null=null;
  if(Exit.isSuccess(result))terminal=surface.inspect(result.value);else{failure=failureCode(result);kind=failure===null?"interruption":"private_failure";}
  if(peek("owner.cleanup")==="fail_fixed_then_repeat_exchange"){
   const beforeChecks=c.authority_calls,beforeAllocations=c.allocation_calls;const again=yield* Effect.exit(surface.exchange(input.request));extras.repeat_failure=failureCode(again);extras.repeat_authority_calls=c.authority_calls-beforeChecks;extras.repeat_allocations=c.allocation_calls-beforeAllocations;
  }
  if(action("after_terminal")==="inspect_foreign_Proxy"){const before=c.authority_calls;extras.terminal_probe_result=surface.inspect(proxy());extras.probe_checks=c.authority_calls-before;extras.probe_traps=c.property_traps;}
  if(savedGates.source){const before=c.authority_calls;const exit=yield* Effect.exit(savedGates.source);extras.source_gate_expired_probe=failureCode(exit);extras.expired_probe_authority_calls=c.authority_calls-before;}
  if(savedGates.flush){const before=c.authority_calls;const exit=yield* Effect.exit(savedGates.flush);extras.flush_gate_expired_probe=failureCode(exit);extras.expired_probe_authority_calls=c.authority_calls-before;}else extras.flush_gate_expired_probe=null;
  if(peek("sink.value.after_read")==="suspend_then_external_interrupt"){
   extras.pending_sink_calls_max=peakSink;extras.cleanup_ack_required=c.aggregate_release_ACKs-baseline.aggregate_release_ACKs===1;extras.closed_sink_error_fixed=failure===null||!failure.includes("SYNTHETIC_SECRET");extras.real_pipe_qualification=false;
  }
  if(input.setup&&seedObservation){extras.seed_observation={allocation_calls:seedObservation.counts.allocation_calls,aggregate_release_attempts:seedObservation.counts.aggregate_release_attempts,aggregate_release_ACKs:seedObservation.counts.aggregate_release_ACKs,
   returned_terminal:seedObservation.terminal,seed_token_distinct_from_target:seedTicket!==targetTicket,source_factory_relation:seedObservation.relation,
   seed_reply_line_distinct_from_target:seedObservation.relation==="same"?seedLine!==targetLine:null};}
  assert.equal(reachedActions.size,input.actions.length,"all declared actions must be reached by actual callbacks");
  const output=trace.flatMap(t=>t.phase==="flush"?[]:[t.bytes.segments[0]!.text]).join("");
  const providerEcho=JSON.stringify({failure,terminal,lexical,trace,output}).includes("SYNTHETIC_SECRET");
  if(busyExit!==null&&busyCounts!==null){
   const observation:SceneObservation={...extras,kind:Exit.isFailure(busyExit)?"private_failure":"completion",fixed_failure:failureCode(busyExit),returned_terminal:null,
    lexical_lines:[],output_trace:[],stdout_utf8:null,stderr_utf8:"",publication_ambiguous:false,raw_buffer_peak:0,pending_sink_calls_peak:0,
    counts:busyCounts,provider_echo:providerEcho,late_noncleanup_callbacks:lateCallbacks,native_pipe_qualified:false,
    counter_window:"second_exchange_only",background_aggregate_release_ACKs:c.aggregate_release_ACKs-baseline.aggregate_release_ACKs,busy_until_ACK:c.aggregate_release_ACKs-baseline.aggregate_release_ACKs===1};return observation;
  }
  // Extensions precede, and cannot overwrite, the explicitly typed fixed fields.
  const observation:SceneObservation={...extras,kind,fixed_failure:failure,returned_terminal:terminal,lexical_lines:lexical.map(digest),output_trace:trace,
   stdout_utf8:Exit.isSuccess(result)?digest(output):null,stderr_utf8:"",publication_ambiguous:trace.length!==0&&!Exit.isSuccess(result),
   raw_buffer_peak:rawPeak,pending_sink_calls_peak:peakSink,counts:difference(c,baseline),provider_echo:providerEcho,late_noncleanup_callbacks:lateCallbacks,native_pipe_qualified:false,
   raw_bytes:rawCount,empty_lines:empty,overflow_lines:overflowLines,frames:frameCount,responses:responseCount};return observation;
 }));
}
for(const scene of stdioFramingFixture.cases){test(`independent stdio framing literal: ${scene.case_id}`,async()=>{
 const closed:Effect.Effect<SceneObservation,FixedFailure>=runScene(scene.stimulus);
 const observed=await Effect.runPromise(closed);
 for(const [key,expected]of Object.entries(scene.expected))assert.deepEqual(sameBytes(observed[key]),sameBytes(expected),`${scene.case_id}: ${key}`);
});}
test("immutable reviewed stdio295 literal/source profile raw pin",async()=>{
 const raw=await readFile(new URL("../../../tests/surfaces/stdio-framing-vectors.ts",import.meta.url));
 assert.equal(createHash("sha256").update(raw).digest("hex"),"cd87897ff0432791e7900b6c53648f6abef8664ebdd20cbe93ae3f7b052b5a28");assert.equal(stdioFramingFixture.cases.length,295);
});
