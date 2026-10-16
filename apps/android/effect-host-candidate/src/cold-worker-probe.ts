import React from "react";
import { NativeModules } from "react-native";
import * as Effect from "effect/Effect";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Exit from "effect/Exit";
import { CandidateSession, inspectCandidate } from "healthmd-candidate-capabilities";

// Packaged registration only: no AppRegistry, UI, old entry, autorun operation or customer data.
type ColdCase = "actual_schedule_no_activity" | "unknown_schema_before_acquire" | "expiry_before_acquire" | "stop_waits_native_ack" | "duplicate_request_no_double_acquire";
type ColdRequest = Readonly<{schema: "healthmd.candidate_cold_worker"; version: 1; case_id: ColdCase; sequence: 0|1|2|3|4; ttl_ms: number}>;
interface Bridge {
  take(): Promise<string|null>;
  check(work: string): Promise<boolean>;
  acquire(work: string): Promise<string>;
  inspect(work: string, handle: string): Promise<string>;
  release(work: string, handle: string): Promise<void>;
  terminal(work: string, code: string): Promise<void>;
  failEngine(): void;
}
class OwnedTicket { readonly #owned = true; }
class OwnedTerminal { readonly #owned = true; }
class ReviewedCandidateEngine { readonly #owned = true; }
interface ColdMailbox {
  take(): Promise<OwnedTicket|null>;
  open(ticket: OwnedTicket): Effect.Effect<{readonly inspect: Effect.Effect<"ready">; readonly release: Effect.Effect<void>}>;
  checkCurrent(ticket: OwnedTicket): Effect.Effect<void>;
  acknowledge(ticket: OwnedTicket, terminal: OwnedTerminal): Effect.Effect<void>;
}
const cases: readonly ColdCase[] = ["actual_schedule_no_activity", "unknown_schema_before_acquire", "expiry_before_acquire", "stop_waits_native_ack", "duplicate_request_no_double_acquire"];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const fixed = () => new Error("cold_boundary_failure");
class TicketInvalid extends Error { readonly code = "ticket_invalid"; constructor() { super("ticket_invalid"); } }
const ownedTickets = new WeakMap<OwnedTicket, Readonly<{work: string; invocationId: string; processNonce: string; pid: number; generation: number; submittedElapsedMs: string; logicalKey: string; request: ColdRequest}>>();
const terminals = new WeakMap<OwnedTerminal, "ready"|"stopped"|"engine_failure"|"cleanup_unverified">();
const engines = new WeakSet<ReviewedCandidateEngine>();
const promise = <A>(f: () => Promise<A>) => Effect.promise(async () => { try { return await f(); } catch { throw fixed(); } });
function owned(ticket: OwnedTicket) {
  const data = ownedTickets.get(ticket);
  if (data === undefined) throw new TicketInvalid(); // Identity before any caller properties/Proxy traps.
  return data;
}
function issueTerminal(code: "ready"|"stopped"|"engine_failure"|"cleanup_unverified"): OwnedTerminal {
  const result: OwnedTerminal = new OwnedTerminal(); Object.freeze(result); terminals.set(result, code); return result;
}
function createMailbox(native: Bridge): ColdMailbox {
  const mailbox: ColdMailbox = {
    async take() {
      const raw = await native.take();
      if (raw === null) return null;
      // Native issuer already validates raw WorkData; this is its bounded, health-free witness.
      if (typeof raw !== "string" || raw.length > 2048 || /[^\x20-\x7e]/.test(raw)) throw fixed();
      const v: unknown = JSON.parse(raw);
      if (v === null || typeof v !== "object") throw fixed();
      const keys = Object.keys(v).sort();
      if (keys.join(",") !== "case_id,generation,invocation_id,pid,process_nonce,sequence,submitted_elapsed_ms,ttl_ms,work_id") throw fixed();
      const m = v as Record<string, unknown>;
      if (typeof m.work_id !== "string" || !uuid.test(m.work_id) || typeof m.invocation_id !== "string" || !uuid.test(m.invocation_id)
        || typeof m.process_nonce !== "string" || !uuid.test(m.process_nonce) || !Number.isInteger(m.sequence) || typeof m.sequence !== "number"
        || cases[m.sequence] !== m.case_id || typeof m.ttl_ms !== "number" || !Number.isInteger(m.ttl_ms) || m.ttl_ms < 0 || m.ttl_ms > 30000
        || typeof m.generation !== "number" || !Number.isInteger(m.generation) || m.generation < 1 || m.generation > 5
        || typeof m.submitted_elapsed_ms !== "string" || !/^(0|[1-9][0-9]{0,18})$/.test(m.submitted_elapsed_ms) || (m.submitted_elapsed_ms.length === 19 && m.submitted_elapsed_ms > "9223372036854775807")
        || typeof m.pid !== "number" || !Number.isInteger(m.pid) || m.pid < 1 || m.pid > 2147483647) throw fixed();
      const ticket: OwnedTicket = new OwnedTicket(); Object.freeze(ticket);
      ownedTickets.set(ticket, Object.freeze({work: m.work_id, invocationId: m.invocation_id, processNonce: m.process_nonce, pid: m.pid, generation: m.generation, submittedElapsedMs: m.submitted_elapsed_ms, logicalKey: `${m.case_id}:${m.sequence}`, request: Object.freeze({schema: "healthmd.candidate_cold_worker", version: 1, case_id: cases[m.sequence]!, sequence: m.sequence as 0|1|2|3|4, ttl_ms: m.ttl_ms})}));
      return ticket;
    },
    checkCurrent(ticket) {
      const {work} = owned(ticket);
      return promise(async () => { if (!await native.check(work)) throw fixed(); });
    },
    open(ticket) {
      const {work} = owned(ticket);
      return promise(async () => {
        // Native allocation is synchronous under its ownership lock; accepted acquireRelease masks the
        // Promise handoff until this returned resource is registered. No detached preparation allocation.
        const handle = await native.acquire(work);
        if (typeof handle !== "string" || !uuid.test(handle)) throw fixed();
        return Object.freeze({
          inspect: promise(async () => { if (await native.inspect(work, handle) !== "ready") throw fixed(); return "ready" as const; }),
          release: promise(() => native.release(work, handle)),
        });
      });
    },
    acknowledge(ticket, terminal) {
      const {work} = owned(ticket);
      const code = terminals.get(terminal); if (code === undefined) throw new TicketInvalid();
      return promise(async () => {
        await native.terminal(work, code);
      });
    },
  };
  return Object.freeze(mailbox);
}
// Execute the two frozen ownership stimuli against the SAME mailbox, before registration.
// This is a synthetic boundary probe; no native resource/WorkManager/journal is invoked.
async function ownershipSupplementals() {
  let acquired=0, published=0, traps=0;
  const witness=JSON.stringify({work_id:"00000000-0000-4000-8000-000000000001",invocation_id:"00000000-0000-4000-8000-000000000002",process_nonce:"00000000-0000-4000-8000-000000000003",case_id:cases[0],sequence:0,ttl_ms:30000,generation:1,pid:1,submitted_elapsed_ms:"100000"});
  const mailbox=createMailbox({take:async()=>witness,check:async()=>true,acquire:async()=>{acquired++;return "00000000-0000-4000-8000-000000000002";},inspect:async()=>"ready",release:async()=>{},terminal:async()=>{published++;},failEngine:()=>{throw fixed();}});
  const original=await mailbox.take();if(original===null)throw fixed();
  const foreign=new Proxy({}, {get(){traps++;throw fixed();},ownKeys(){traps++;throw fixed();},getPrototypeOf(){traps++;throw fixed();}});
  const observations=[];
  for(const id of ["forged_ticket_no_properties","foreign_terminal_no_properties"] as const) {
    let code="";
    try {
      if(id==="forged_ticket_no_properties")mailbox.open(foreign as OwnedTicket);
      else mailbox.acknowledge(original,foreign as OwnedTerminal);
    } catch(e) {if(e instanceof TicketInvalid)code=e.code;else throw fixed();}
    if(code!=="ticket_invalid"||traps!==0||acquired!==0||published!==0)throw fixed();
    observations.push(Object.freeze({case_id:id,code,property_traps:traps,native_acquire:acquired,ack_publish:published,journal_write:0}));
  }
  return Object.freeze(observations);
}
async function execute(mailbox: ColdMailbox, ticket: OwnedTicket) {
  const session = Layer.succeed(CandidateSession)({ acquire: mailbox.checkCurrent(ticket).pipe(Effect.andThen(mailbox.open(ticket))) });
  const fiber = Effect.runFork(inspectCandidate.pipe(Effect.provide(session)));
  const monitor = Effect.runFork(Effect.gen(function* () {
    while (fiber.pollUnsafe() === undefined) {
      const current = yield* Effect.exit(mailbox.checkCurrent(ticket));
      if (Exit.isFailure(current)) { yield* Fiber.interrupt(fiber); return; }
      yield* Effect.sleep("10 millis");
    }
  }));
  const exit = await Effect.runPromise(Fiber.await(fiber));
  await Effect.runPromise(Fiber.interrupt(monitor));
  // The native terminal gate chooses stopped/expired from its latest own state; JS cannot revive it.
  const terminal = issueTerminal(Exit.isSuccess(exit) ? "ready" : "stopped");
  await Effect.runPromise(mailbox.acknowledge(ticket, terminal));
}
function registerColdWorker(mailbox: ColdMailbox, identity: ReviewedCandidateEngine) {
  if (!engines.has(identity)) throw fixed();
  void (async () => {
    try {
      for (;;) { const ticket = await mailbox.take(); if (ticket === null) return; await execute(mailbox, ticket); }
    } catch { /* native bounded deadline emits Incomplete; no arbitrary error/report payload */ }
  })();
}
// Identity issues ONLY from this packaged observation, never arbitrary caller version fields.
declare const global: {HermesInternal?: {getRuntimeProperties(): Record<string, unknown>}};
const native = NativeModules.ColdProbe as Bridge;
try {
  const properties = global.HermesInternal?.getRuntimeProperties();
  if (React.version !== "19.2.3" || properties === undefined || properties["OSS Release Version"] !== "250829098.0.17" || properties["Bytecode Version"] !== 98) throw fixed();
  const identity: ReviewedCandidateEngine = new ReviewedCandidateEngine(); Object.freeze(identity); engines.add(identity);
  void ownershipSupplementals().then(()=>registerColdWorker(createMailbox(native), identity)).catch(()=>native.failEngine());
} catch { native.failEngine(); /* fixed registration failure, no error details */ }
